# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

class GeminiService
  DEFAULT_MODEL = 'gemini-3.5-flash'
  FALLBACK_MODELS = [
    'gemini-3.5-flash',
    'gemini-flash-lite-latest',
    'gemini-3.5-flash-lite',
    'gemini-3.8-flash',
    'gemini-flash-latest'
  ].freeze

  attr_reader :company, :user

  def initialize(company:, user:)
    @company = company
    @user = user
  end

  def self.api_key
    ENV['GEMINI_API_KEY'].presence || 
      ENV['GOOGLE_API_KEY'].presence ||
      read_env_file_key ||
      Rails.application.credentials.dig(:gemini_api_key) ||
      Rails.application.credentials.dig(:google_api_key)
  end

  def self.read_env_file_key
    env_file = Rails.root.join('.env')
    return nil unless File.exist?(env_file)
    File.readlines(env_file).each do |line|
      match = line.strip.match(/^(?:GEMINI_API_KEY|GOOGLE_API_KEY)\s*=\s*(.+)$/)
      return match[1].strip.gsub(/\A["']|["']\z/, '') if match
    end
    nil
  rescue StandardError
    nil
  end

  def self.api_key_configured?
    api_key.present?
  end

  # Punto de entrada principal para procesar mensajes del usuario
  def chat(user_message, history = [])
    unless self.class.api_key_configured?
      return unconfigured_fallback_response(user_message)
    end

    begin
      execute_conversation(user_message, history)
    rescue StandardError => e
      Rails.logger.error("[GeminiService] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      diagnostic = run_diagnostic
      {
        reply: "⚠️ Los servidores de Google Gemini están experimentando una saturación temporal de tráfico en este momento.\n\n" \
               "💰 **Saldo actual en Caja:** $#{sprintf('%.2f', diagnostic[:cash_balance])} USD\n\n" \
               "📌 Puedes reintentar tu mensaje en unos segundos o usar los accesos rápidos de la pantalla.",
        actions_taken: [],
        cards: []
      }
    end
  end

  # Diagnóstico completo de la empresa para la Caja y Operaciones (Fondo Único)
  def run_diagnostic
    upcoming_gigs = company.gigs.where('date >= ?', Date.current).order(date: :asc).limit(10).includes(:client, :staff_assignments)
    
    unstaffed_gigs = upcoming_gigs.select { |g| g.staff_assignments.empty? }
    pending_collection_gigs = upcoming_gigs.select { |g| g.remaining_amount.positive? }
    pending_approvals = GigPayment.joins(:gig).where(gigs: { company_id: company.id }).pending_approval.count rescue 0
    pending_worker_reports = company.employee_payments.pending_approval.count rescue 0

    # Estado de caja (Fondo General Único)
    cash_balance = calculate_current_cash_balance

    diagnostic_items = []

    # 1. Deudas y compromisos con músicos / trabajadores
    worker_metrics = WorkerBalanceService.build_metrics_for_company(company) rescue []
    workers_with_pending = worker_metrics.select { |m| m[:past_balance].to_f > 0 }
    total_owed_to_workers = workers_with_pending.sum { |m| m[:past_balance].to_f }.round(2)

    if total_owed_to_workers.positive?
      diagnostic_items << {
        type: 'pending_worker_payouts',
        level: 'warning',
        title: "Compromisos con Músicos ($#{sprintf('%.2f', total_owed_to_workers)} USD)",
        description: "Tienes #{workers_with_pending.count} músico(s) con pagos pendientes por liquidar: #{workers_with_pending.map { |m| "#{m[:worker]&.display_name} ($#{m[:past_balance]})" }.join(', ')}.",
        action_label: "Ver Pagos de Músicos",
        action_key: "view_worker_payments"
      }
    end

    # 2. Cierre pendiente de shows recientes (¿Qué pasó con los shows de ayer o hace 2-3 días?)
    post_gig_audits = recent_post_gig_audits
    post_gig_audits.each do |f|
      issues = []
      issues << "cobrar saldo de $#{sprintf('%.2f', f[:client_remaining])} al cliente" if f[:client_remaining].positive?
      issues << "pagar nómina a #{f[:unpaid_staff].map { |s| s[:name] }.join(', ')}" if f[:unpaid_staff].any?
      issues << "anotar gastos operativos si los hubo" if f[:no_expenses_recorded]

      diagnostic_items << {
        type: 'post_gig_reconciliation',
        level: 'warning',
        title: "🔔 Cierre Pendiente: #{f[:client_name]} (#{f[:date_str]})",
        description: "El evento fue #{f[:days_label]}. Falta: #{issues.join(' | ')}.",
        action_label: "Revisar este Show",
        action_key: "prompt_show_followup",
        prompt: "¿Qué pasó con el show de #{f[:client_name]} del #{f[:date_str]}? Ayúdame a revisar nómina, cobros y gastos."
      }
    end

    # 3. Alertas de shows sin músicos asignados
    if unstaffed_gigs.any?
      diagnostic_items << {
        type: 'unstaffed_gigs',
        level: 'danger',
        title: "#{unstaffed_gigs.count} Show(s) Próximo(s) sin Músicos Asignados",
        description: "Eventos cercanos sin personal: #{unstaffed_gigs.map { |g| "#{g.client_display_name} (#{g.date&.strftime('%d/%m')})" }.join(', ')}.",
        action_label: "Asignar con Copiloto",
        action_key: "prompt_staff_assignment"
      }
    end

    # 3. Alertas de saldos por cobrar
    if pending_collection_gigs.any?
      total_pending_cobro = pending_collection_gigs.sum(&:remaining_amount)
      diagnostic_items << {
        type: 'pending_collection',
        level: 'info',
        title: "Saldos Pendientes por Cobrar ($#{sprintf('%.2f', total_pending_cobro)} USD)",
        description: "Hay #{pending_collection_gigs.count} evento(s) próximos con saldos por liquidar.",
        action_label: "Ver Estados de Cuenta",
        action_key: "view_gigs"
      }
    end

    # 4. Reportes de pago de trabajadores pendientes de confirmación
    company.employee_payments.pending_approval.includes(:user, :gig).order(created_at: :desc).limit(5).each do |ep|
      worker_name = ep.user&.display_name || "Músico"
      amount_str = sprintf('%.2f', ep.amount)
      date_str = ep.date_paid&.strftime('%d/%m/%Y') || 'reciente'
      method_str = ep.payment_method.presence || 'Efectivo'
      gig_text = ep.gig.present? ? " (Show: #{ep.gig.client_display_name})" : ""

      diagnostic_items << {
        type: 'pending_worker_approval',
        level: 'warning',
        title: "⏳ Reporte de Pago: #{worker_name} ($#{amount_str} USD)",
        description: "#{worker_name} indicó haber recibido $#{amount_str} USD vía #{method_str} (#{date_str})#{gig_text}. Confirma si ya se le realizó.",
        action_label: "⚡ Autorizar Pago de #{worker_name}",
        action_key: "prompt_approve_payment",
        prompt: "Autoriza el reporte de pago de #{worker_name} por $#{amount_str} USD."
      }
    end

    # 5. Abonos de clientes pendientes de aprobación
    GigPayment.joins(:gig).where(gigs: { company_id: company.id }).pending_approval.includes(:gig).order(created_at: :desc).limit(5).each do |gp|
      payer = gp.payer_name || gp.gig&.client_display_name
      amount_str = sprintf('%.2f', gp.amount)
      diagnostic_items << {
        type: 'pending_gig_payment_approval',
        level: 'warning',
        title: "💳 Comprobante de Abono: #{payer} ($#{amount_str} USD)",
        description: "Comprobante de abono por $#{amount_str} USD para el show de #{gp.gig&.client_display_name}.",
        action_label: "⚡ Aprobar Abono",
        action_key: "prompt_approve_gig_payment",
        prompt: "Aprueba el abono de #{payer} por $#{amount_str} USD."
      }
    end

    {
      cash_balance: cash_balance,
      diagnostic_items: diagnostic_items,
      post_gig_audits: post_gig_audits,
      healthy: diagnostic_items.empty?,
      timestamp: Time.current.strftime('%H:%M:%S')
    }
  end

  # Detecta shows de los últimos 7 días con pendientes de nómina, cobro o gastos
  def recent_post_gig_audits
    recent_gigs = company.gigs.where('date <= ? AND date >= ?', Date.current, Date.current - 7.days).order(date: :desc).limit(3)
    
    followups = []
    recent_gigs.each do |gig|
      client_unpaid = gig.remaining_amount.positive?
      
      unpaid_staff = []
      gig.staff_assignments.includes(:user).each do |sa|
        paid = sa.direct_paid
        agreed = sa.agreed_amount.to_f
        if agreed.positive? && paid < agreed
          unpaid_staff << { user_id: sa.user_id, name: sa.user&.display_name, agreed: agreed, remaining: (agreed - paid).round(2) }
        elsif gig.employee_payments.approved.where(user_id: sa.user_id).empty? && sa.user.present?
          unpaid_staff << { user_id: sa.user_id, name: sa.user.display_name, agreed: agreed, remaining: agreed }
        end
      end

      # Gastos registrados con la fecha del gig
      expenses_count = company.cash_adjustments.where(date: gig.date, adjustment_type: :withdrawal).count

      if client_unpaid || unpaid_staff.any? || expenses_count.zero?
        days_ago = (Date.current - gig.date).to_i
        days_label = days_ago.zero? ? "hoy" : (days_ago == 1 ? "ayer" : "hace #{days_ago} días")
        followups << {
          gig_id: gig.id,
          client_name: gig.client_display_name,
          date: gig.date,
          date_str: gig.date.strftime('%d/%m/%Y'),
          days_ago: days_ago,
          days_label: days_label,
          client_remaining: gig.remaining_amount.round(2),
          unpaid_staff: unpaid_staff,
          no_expenses_recorded: expenses_count.zero?
        }
      end
    end
    followups
  rescue StandardError => e
    Rails.logger.error("[GeminiService#recent_post_gig_audits] Error: #{e.message}")
    []
  end

  private

  def execute_conversation(user_message, history)
    actions_taken = []
    cards = []

    # Construir contents para la API de Gemini
    contents = build_contents(user_message, history)

    # 1era llamada a Gemini con tools
    first_response = call_gemini_api(contents)
    candidate = first_response.dig('candidates', 0, 'content')
    parts = candidate&.dig('parts') || []

    # Buscar llamadas a funciones
    function_calls = parts.select { |p| p.key?('functionCall') }

    if function_calls.any?
      # Ejecutar las funciones
      function_responses_parts = []
      
      function_calls.each do |fc|
        call_info = fc['functionCall']
        tool_name = call_info['name']
        tool_args = call_info['args'] || {}

        result = execute_tool(tool_name, tool_args)
        actions_taken << { tool: tool_name, result: result }
        cards << result[:card] if result[:card].present?

        function_responses_parts << {
          functionResponse: {
            name: tool_name,
            response: { output: result }
          }
        }
      end

      # Segunda llamada para que Gemini sintetice la respuesta final para el usuario
      contents << {
        role: 'model',
        parts: parts
      }
      contents << {
        role: 'user',
        parts: function_responses_parts
      }

      second_response = call_gemini_api(contents, include_tools: false)
      final_text = second_response.dig('candidates', 0, 'content', 'parts', 0, 'text') || 
                   "¡Listo! He procesado tu solicitud exitosamente."

      {
        reply: final_text,
        actions_taken: actions_taken,
        cards: cards
      }
    else
      text_reply = parts.map { |p| p['text'] }.compact.join("\n")
      {
        reply: text_reply.presence || "Entendido. ¿En qué más puedo ayudarte hoy con la caja o tus eventos?",
        actions_taken: [],
        cards: []
      }
    end
  end

  def build_contents(user_message, history)
    contents = []

    # Agregar historial previo si existe
    if history.is_a?(Array)
      history.last(8).each do |turn|
        role = turn['role'] == 'user' ? 'user' : 'model'
        contents << {
          role: role,
          parts: [{ text: turn['content'].to_s }]
        }
      end
    end

    # Mensaje actual del usuario
    contents << {
      role: 'user',
      parts: [{ text: user_message.to_s }]
    }

    contents
  end

  def call_gemini_api(contents, include_tools: true, preferred_model: nil)
    models_to_try = if preferred_model
                      [preferred_model] + (FALLBACK_MODELS - [preferred_model])
                    else
                      FALLBACK_MODELS
                    end

    last_error = nil

    models_to_try.each_with_index do |model_name, index|
      api_url = "https://generativelanguage.googleapis.com/v1beta/models/#{model_name}:generateContent?key=#{self.class.api_key}"
      uri = URI(api_url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 20
      http.open_timeout = 10

      body = {
        systemInstruction: {
          parts: [{ text: system_instruction_text }]
        },
        contents: contents,
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: 1024
        }
      }

      body[:tools] = tool_declarations if include_tools

      request = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json' })
      request.body = body.to_json

      begin
        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          return JSON.parse(response.body)
        end

        parsed_error = JSON.parse(response.body) rescue { 'error' => { 'message' => response.body } }
        error_msg = parsed_error.dig('error', 'message') || response.body
        error_code = response.code.to_i

        Rails.logger.warn("[GeminiService] Model #{model_name} returned HTTP #{error_code}: #{error_msg}")

        # Transient errors (503 high demand, 429 rate limit, 500, 502, 504 server error, or 404 retired model)
        if [503, 429, 500, 502, 504, 404].include?(error_code)
          last_error = "Google Gemini (#{model_name} - HTTP #{error_code}): #{error_msg}"
          sleep 0.3 if index < models_to_try.length - 1
          next
        else
          # Client/Validation error (e.g. 400 bad request)
          raise "Google Gemini API Error (#{response.code}): #{error_msg}"
        end
      rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET => e
        Rails.logger.warn("[GeminiService] Network timeout/reset with #{model_name}: #{e.message}")
        last_error = "Timeout de conexión con #{model_name}"
        sleep 0.3 if index < models_to_try.length - 1
        next
      end
    end

    raise "Todos los modelos de Gemini están experimentando alta demanda o indisponibilidad temporal. (#{last_error})"
  end

  # ==========================================
  # SYSTEM INSTRUCTION & CONTEXT
  # ==========================================

  def system_instruction_text
    cash_balance = calculate_current_cash_balance
    today_str = Date.current.strftime('%Y-%m-%d (%A)')
    
    # Trabajadores activos
    workers_list = company.users.workers.limit(15).map do |w|
      spec = w.respond_to?(:specialty) && w.specialty.present? ? " (#{w.specialty})" : ""
      "#{w.display_name}#{spec}"
    end.join(', ')

    # Shows próximos
    upcoming = company.gigs.where('date >= ?', Date.current).order(date: :asc).limit(6).map do |g|
      "ID: #{g.id} | #{g.date&.strftime('%d/%m/%Y')} | #{g.client_display_name} | Monto: $#{g.amount} | Restante: $#{g.remaining_amount} | Músicos: #{g.staff_members.pluck(:name).compact.join(', ').presence || 'Ninguno'}"
    end.join("\n")

    # Shows recientes que requieren seguimiento y cierre operativo
    post_gig_audits = recent_post_gig_audits
    post_gig_context = if post_gig_audits.any?
      lines = post_gig_audits.map do |f|
        items = []
        items << "Falta cobrar saldo de $#{sprintf('%.2f', f[:client_remaining])} al cliente" if f[:client_remaining].positive?
        if f[:unpaid_staff].any?
          items << "Nómina sin registrar pago a: #{f[:unpaid_staff].map { |s| "#{s[:name]} ($#{s[:remaining]})" }.join(', ')}"
        end
        items << "Cero gastos de transporte/comida registrados" if f[:no_expenses_recorded]
        "• #{f[:client_name]} (#{f[:date_str]}, #{f[:days_label]}): #{items.join(' | ')}"
      end
      "SHOWS RECIENTES QUE REQUIEREN SEGUIMIENTO Y CIERRE:\n#{lines.join("\n")}"
    else
      "No hay shows recientes pendientes de cierre."
    end

    # Reportes de pagos y abonos pendientes de confirmación / autorización
    pending_worker_reports = company.employee_payments.pending_approval.includes(:user, :gig).order(created_at: :desc).limit(10)
    pending_client_abonos = GigPayment.joins(:gig).where(gigs: { company_id: company.id }).pending_approval.includes(:gig).order(created_at: :desc).limit(10)
    unread_notifs = AppNotification.for_user(user).unread_by(user).recent_first.limit(6) rescue []

    approvals_lines = []
    pending_worker_reports.each do |ep|
      gig_label = ep.gig.present? ? "Show: #{ep.gig.client_display_name}" : "Pago general / Anticipo"
      note_label = ep.notes.present? ? " | Nota: '#{ep.notes}'" : ""
      approvals_lines << "• [REPORTE DE PAGO MÚSICO] ID: #{ep.id} | Músico/Staff: #{ep.user&.display_name} | Monto: $#{sprintf('%.2f', ep.amount)} USD | Método: #{ep.payment_method.presence || 'Efectivo'} | Fecha: #{ep.date_paid&.strftime('%d/%m/%Y')} | #{gig_label}#{note_label} | Estado: PENDIENTE DE CONFIRMACIÓN"
    end
    pending_client_abonos.each do |gp|
      approvals_lines << "• [COMPROBANTE DE ABONO CLIENTE] ID: #{gp.id} | Cliente/Pagador: #{gp.payer_name || gp.gig&.client_display_name} | Monto: $#{sprintf('%.2f', gp.amount)} USD | Show: #{gp.gig&.client_display_name} | Fecha: #{gp.date_paid&.strftime('%d/%m/%Y')} | Estado: PENDIENTE DE REVISIÓN"
    end

    pending_approvals_context = if approvals_lines.any?
      "REPORTES DE PAGO Y ABONOS PENDIENTES DE AUTORIZAR POR EL LÍDER:\n#{approvals_lines.join("\n")}"
    else
      "No hay pagos ni abonos pendientes de autorizar en este momento."
    end

    notifs_lines = unread_notifs.map do |n|
      "• [#{n.created_at.strftime('%d/%m %H:%M')}] #{n.title}: #{n.message.to_s.truncate(130)}"
    end

    unread_notifs_context = if notifs_lines.any?
      "NOTIFICACIONES RECIENTES SIN LEER DEL LÍDER:\n#{notifs_lines.join("\n")}"
    else
      "No hay notificaciones sin leer."
    end

    <<~PROMPT
      Eres GigAI, el Copiloto Inteligente, Director Financiero y Operativo de Gig Manager para la empresa "#{company.name}".

      FILOSOFÍA FINANCIERA FUNDAMENTAL DE LA APP (¡MUY IMPORTANTE!):
      - En esta aplicación EXISTE ÚNICA Y EXCLUSIVAMENTE UN SOLO FONDO: La Caja General / Fondo de la Banda.
      - NO existen sub-fondos separados y NUNCA se divide el dinero de los shows en sub-cuentas ni sub-repartos.
      - TODO el dinero cobrado por shows (abonos, anticipos) y depósitos entra DIRECTAMENTE a este Fondo General Único.
      - TODOS los egresos (pagos a músicos, reparaciones, cables, transporte, inversiones, compras de equipo, retiros) salen DIRECTAMENTE de este mismo Fondo General.
      - El saldo disponible real es: Entradas totales - Salidas totales.

      TU MISIÓN PRINCIPAL:
      1. CONTROLAR LA CAJA Y EL FONDO GENERAL: Mantener el balance neto exacto. Registrar al instante gastos hormiga y salidas en efectivo (transporte, cables, hidratación, comida) mediante voz o texto para que nunca haya descuadre.
      2. AGENDAR EVENTOS Y REGISTRAR ABONOS: Crear shows, clientes, anticipos y asignar músicos con una sola instrucción sin fricción.
      3. SEGUIMIENTO PROACTIVO DE CIERRE DE SHOWS: Cuando un evento acaba de pasar (ayer o hace pocos días), ayudar al usuario a no olvidar registrar el pago a la nómina de músicos, el saldo cobrado al cliente o los gastos de transporte.
      4. GESTIÓN PROACTIVA DE NOTIFICACIONES Y AUTORIZACIÓN DE PAGOS: Leer los reportes de pago de músicos y abonos de clientes para avisar de inmediato al líder y autorizarlos o rechazarlos con órdenes sencillas en lenguaje natural.

      DATOS DE CONTEXTO ACTUAL DE LA EMPRESA:
      - Fecha de hoy: #{today_str}
      - Saldo neto disponible en el Fondo General (Caja): $#{sprintf('%.2f', cash_balance)} USD
      - Moneda principal: USD ($)
      - Personal / Músicos registrados: #{workers_list.presence || 'Sin personal registrado aún'}
      - Próximos Shows:
      #{upcoming.presence || 'No hay shows próximos en los próximos días.'}

      #{post_gig_context}

      #{pending_approvals_context}

      #{unread_notifs_context}

      REGLAS DE ACTUACIÓN:
      - PROACTIVIDAD EN PAGOS PENDIENTES Y NOTIFICACIONES (¡CRUCIAL!):
        Si en la sección "REPORTES DE PAGO Y ABONOS PENDIENTES DE AUTORIZAR" hay elementos, y el usuario te saluda ("hola", "¿qué hay pendiente?", "¿qué notificaciones tengo?", "¿tengo algo pendiente?"):
        ¡DEBES INFORMARLE DE INMEDIATO E INTUITIVAMENTE!
        Ejemplo: "¡Hola! Tienes [X] reporte(s) de pago pendiente(s) de confirmar:
        • Gabriel Morales indicó haber recibido $100.00 USD en Efectivo (06/11/2026).
        ¿Deseas que lo autorice de una vez?"
        NUNCA digas que no tienes notificaciones ni pendientes si hay pagos pendientes en la lista.
      - AUTORIZAR PAGOS:
        Si el usuario dice "autoriza el pago de [Nombre]", "aprueba el pago de Gabriel", "confirma el pago", "sí, autorízalo", "acepta el reporte", o "autorizar todos":
        Llama de inmediato a la herramienta `approve_payment` con el nombre de la persona (o `approve_all: true` si pide todos).
      - RECHAZAR PAGOS:
        Si el usuario dice "rechaza el pago de Gabriel" o "no lo aceptes":
        Llama a la herramienta `reject_payment` con el motivo del rechazo.
      - CONSULTAR NOTIFICACIONES / PENDIENTES:
        Si el usuario pide ver notificaciones o pendientes, llama a `get_pending_approvals` o enumérale de forma clara los pagos y notificaciones pendientes.
      - Si el usuario dice que gastó dinero en efectivo (ej. "anota $20 de taxi" o "gasté $15 en cables"), llama inmediatamente a la función `record_cash_adjustment` con adjustment_type: "withdrawal".
      - Si el usuario dice que cobró o entró un dinero a caja, llama a `record_cash_adjustment` con adjustment_type: "deposit" (o `record_gig_payment` si menciona un show/cliente).
      - Si el usuario pide agendar un show, usa `create_gig`. Si menciona un anticipo, inclúyelo en `advance_amount`. Si menciona músicos, inclúyelos en `staff_names`.
      - Si el usuario dice que ya le pagó a un músico o pregunta por nómina, usa `record_employee_payment` o `get_worker_balances`.
      - NUNCA le digas al usuario que debe repartir o asignar dinero a sub-fondos, porque solo existe un fondo general único.
      - ESTILO CONVERSACIONAL Y DE VOZ (MUY IMPORTANTE): Tus respuestas se leen en voz alta con audio interactivo por el navegador. Responde siempre en español natural, fluido, conciso y motivador. Sé muy claro sobre los montos y acciones realizadas, con frases directas y agradables de escuchar.
    PROMPT
  end

  # ==========================================
  # DECLARACIÓN DE HERRAMIENTAS (TOOLS)
  # ==========================================

  def tool_declarations
    [
      {
        functionDeclarations: [
          {
            name: 'record_cash_adjustment',
            description: 'Registra un movimiento directo en la Caja General (ingreso de dinero, retiro de efectivo o gasto operativo menor como taxi, cables, comida, reparaciones de emergencia).',
            parameters: {
              type: 'OBJECT',
              properties: {
                adjustment_type: {
                  type: 'STRING',
                  enum: %w[deposit withdrawal],
                  description: 'deposit para ingresos de dinero a caja; withdrawal para gastos, compras menores o retiros de efectivo'
                },
                amount: {
                  type: 'NUMBER',
                  description: 'Monto del movimiento en USD (debe ser mayor a 0)'
                },
                description: {
                  type: 'STRING',
                  description: 'Concepto o motivo detallado del movimiento (ej. Taxi show sábado, Compra de cables XLR, Aporte directo a caja)'
                },
                date: {
                  type: 'STRING',
                  description: 'Fecha en formato YYYY-MM-DD. Opcional, por defecto es hoy.'
                }
              },
              required: %w[adjustment_type amount description]
            }
          },
          {
            name: 'create_gig',
            description: 'Agenda un nuevo evento o show completo, creando el cliente si no existe, asignando monto, fecha, horario, anticipo y músicos.',
            parameters: {
              type: 'OBJECT',
              properties: {
                client_name: { type: 'STRING', description: 'Nombre completo o de contacto del cliente' },
                date: { type: 'STRING', description: 'Fecha del show en formato YYYY-MM-DD' },
                amount: { type: 'NUMBER', description: 'Monto total acordado del show en USD' },
                advance_amount: { type: 'NUMBER', description: 'Monto de anticipo o abono inicial pagado (opcional, 0 si no hubo)' },
                advance_payment_method: { type: 'STRING', description: 'Método de pago del anticipo (cash, zelle, transfer, etc.)' },
                location: { type: 'STRING', description: 'Lugar o dirección del evento' },
                start_time: { type: 'STRING', description: 'Hora de inicio (ej. 20:00 o 8:00 PM)' },
                end_time: { type: 'STRING', description: 'Hora de finalización (ej. 00:00)' },
                staff_names: {
                  type: 'ARRAY',
                  items: { type: 'STRING' },
                  description: 'Nombres de los músicos o staff que estarán asignados a este evento'
                },
                notes: { type: 'STRING', description: 'Notas adicionales o requerimientos del show' }
              },
              required: %w[client_name date amount]
            }
          },
          {
            name: 'record_gig_payment',
            description: 'Registra un abono o pago de cliente hacia un show existente.',
            parameters: {
              type: 'OBJECT',
              properties: {
                client_or_gig: { type: 'STRING', description: 'Nombre del cliente o ID del show' },
                amount: { type: 'NUMBER', description: 'Monto abonado en USD' },
                payment_method: { type: 'STRING', description: 'Método: cash, zelle, transfer, pago_movil, etc.' },
                date_paid: { type: 'STRING', description: 'Fecha del pago (YYYY-MM-DD)' },
                is_advance: { type: 'BOOLEAN', description: 'true si es el anticipo inicial del show' },
                notes: { type: 'STRING', description: 'Notas o referencia del pago' }
              },
              required: %w[client_or_gig amount]
            }
          },
          {
            name: 'record_employee_payment',
            description: 'Registra el pago de nómina o anticipo a un músico o miembro del staff por su trabajo en un show o pago general, descontándolo del Fondo General.',
            parameters: {
              type: 'OBJECT',
              properties: {
                worker_name: { type: 'STRING', description: 'Nombre del músico o trabajador' },
                amount: { type: 'NUMBER', description: 'Monto pagado en USD' },
                gig_id_or_client: { type: 'STRING', description: 'Show o cliente al que corresponde el pago (opcional)' },
                payment_method: { type: 'STRING', description: 'Método: cash, zelle, transfer, pago_movil' },
                date_paid: { type: 'STRING', description: 'Fecha del pago (YYYY-MM-DD)' },
                notes: { type: 'STRING', description: 'Notas o concepto del pago' }
              },
              required: %w[worker_name amount]
            }
          },
          {
            name: 'get_worker_balances',
            description: 'Consulta los saldos y deudas pendientes de pago con cada músico o miembro del staff por shows realizados.',
            parameters: {
              type: 'OBJECT',
              properties: {}
            }
          },
          {
            name: 'get_financial_and_operational_status',
            description: 'Obtiene el estado financiero del Fondo General (saldo disponible, entradas, salidas) y compromisos de la empresa.',
            parameters: {
              type: 'OBJECT',
              properties: {}
            }
          },
          {
            name: 'approve_payment',
            description: 'Autoriza, confirma o aprueba un reporte de pago enviado por un músico/trabajador o un comprobante de abono enviado por un cliente. También puede autorizar todos los pagos pendientes si el usuario lo solicita.',
            parameters: {
              type: 'OBJECT',
              properties: {
                worker_or_client_name: {
                  type: 'STRING',
                  description: 'Nombre del músico, trabajador o cliente cuyo pago se desea autorizar (ej. "Gabriel Morales", "Gabriel")'
                },
                payment_id: {
                  type: 'INTEGER',
                  description: 'ID exacto del pago a autorizar (opcional si se especifica el nombre)'
                },
                payment_type: {
                  type: 'STRING',
                  enum: %w[employee_payment gig_payment all],
                  description: 'Tipo de pago a autorizar. "employee_payment" para pagos a músicos, "gig_payment" para abonos de clientes, "all" para autorizar todo lo pendiente.'
                },
                approve_all: {
                  type: 'BOOLEAN',
                  description: 'true si el usuario solicita autorizar todos los pagos o reportes pendientes'
                }
              }
            }
          },
          {
            name: 'reject_payment',
            description: 'Rechaza un reporte de pago enviado por un músico o un comprobante de abono con un motivo de rechazo.',
            parameters: {
              type: 'OBJECT',
              properties: {
                worker_or_client_name: {
                  type: 'STRING',
                  description: 'Nombre del músico, trabajador o cliente cuyo pago se desea rechazar'
                },
                payment_id: {
                  type: 'INTEGER',
                  description: 'ID del pago a rechazar (opcional si se especifica el nombre)'
                },
                reason: {
                  type: 'STRING',
                  description: 'Motivo o razón del rechazo para notificar a la persona'
                }
              },
              required: %w[reason]
            }
          },
          {
            name: 'get_pending_approvals',
            description: 'Consulta detallada de todos los pagos, abonos y notificaciones pendientes de autorización o revisión.',
            parameters: {
              type: 'OBJECT',
              properties: {}
            }
          }
        ]
      }
    ]
  end

  # ==========================================
  # EJECUCIÓN DE HERRAMIENTAS (TOOL RUNNER)
  # ==========================================

  def execute_tool(tool_name, args)
    case tool_name
    when 'record_cash_adjustment'
      tool_record_cash_adjustment(args)
    when 'create_gig'
      tool_create_gig(args)
    when 'record_gig_payment'
      tool_record_gig_payment(args)
    when 'record_employee_payment'
      tool_record_employee_payment(args)
    when 'get_worker_balances'
      tool_get_worker_balances(args)
    when 'get_financial_and_operational_status'
      tool_get_financial_status(args)
    when 'approve_payment'
      tool_approve_payment(args)
    when 'reject_payment'
      tool_reject_payment(args)
    when 'get_pending_approvals'
      tool_get_pending_approvals(args)
    else
      { success: false, message: "Herramienta desconocida: #{tool_name}" }
    end
  rescue StandardError => e
    Rails.logger.error("[GeminiService#execute_tool] Error ejecutando #{tool_name}: #{e.message}")
    { success: false, message: "Error al ejecutar #{tool_name}: #{e.message}" }
  end

  def tool_record_cash_adjustment(args)
    type = args['adjustment_type'].to_s == 'deposit' ? :deposit : :withdrawal
    amount = args['amount'].to_f
    desc = args['description'].to_s.strip
    date = parse_date(args['date']) || Date.current

    adjustment = company.cash_adjustments.create!(
      user: user,
      adjustment_type: type,
      amount: amount,
      description: desc,
      date: date,
      currency: 'USD',
      status: 'approved'
    )

    new_balance = calculate_current_cash_balance
    action_type_label = type == :deposit ? 'Ingreso registrado en Caja' : 'Gasto/Retiro registrado en Caja'
    emoji = type == :deposit ? '💵' : '💸'

    {
      success: true,
      message: "#{emoji} #{action_type_label}: $#{sprintf('%.2f', amount)} USD por concepto de '#{desc}'. Nuevo saldo en caja: $#{sprintf('%.2f', new_balance)} USD.",
      new_balance: new_balance,
      card: {
        type: 'cash_adjustment',
        title: "#{emoji} #{action_type_label}",
        amount: "$#{sprintf('%.2f', amount)} USD",
        description: desc,
        date: date.strftime('%d/%m/%Y'),
        url: "/caja"
      }
    }
  end

  def tool_create_gig(args)
    ActiveRecord::Base.transaction do
      client_name = args['client_name'].to_s.strip
      client = find_or_create_client(client_name, args['client_phone'], args['client_email'])

      gig_date = parse_date(args['date']) || Date.current
      total_amount = args['amount'].to_f

      gig = company.gigs.create!(
        client: client,
        date: gig_date,
        amount: total_amount,
        currency: 'USD',
        location: args['location'].presence || 'Por definir',
        details: args['notes'].presence || 'Agendado con Gig IA Copilot',
        start_time: args['start_time'].presence,
        end_time: args['end_time'].presence
      )

      # 1. Registrar anticipo si fue provisto
      advance_amount = args['advance_amount'].to_f
      if advance_amount.positive?
        gig.gig_payments.create!(
          amount: advance_amount,
          currency: 'USD',
          date_paid: Date.current,
          is_advance: true,
          payment_method: args['advance_payment_method'].presence || 'cash',
          payer_name: client.name,
          category: 'other',
          status: 'approved',
          notes: 'Anticipo inicial registrado vía Gig IA Copilot'
        )
      end

      # 2. Asignar músicos o staff si se mencionaron
      assigned_names = []
      if args['staff_names'].is_a?(Array) && args['staff_names'].any?
        args['staff_names'].each do |name|
          w = find_or_create_worker(name)
          if w.present?
            gig.staff_assignments.find_or_create_by!(user: w) do |sa|
              sa.agreed_amount = 0.0
            end
            assigned_names << w.display_name
          end
        end
      end

      remaining = gig.remaining_amount
      assigned_text = assigned_names.any? ? " Staff asignado: #{assigned_names.join(', ')}." : ""
      advance_text = advance_amount.positive? ? " Anticipo de $#{sprintf('%.2f', advance_amount)} registrado." : ""

      {
        success: true,
        message: "🎸 Show agendado con éxito para #{client.name} el #{gig_date.strftime('%d/%m/%Y')} por $#{sprintf('%.2f', total_amount)} USD.#{advance_text}#{assigned_text} Saldo pendiente: $#{sprintf('%.2f', remaining)} USD.",
        gig_id: gig.id,
        card: {
          type: 'gig_created',
          title: "🎸 Show Agendado: #{client.name}",
          amount: "$#{sprintf('%.2f', total_amount)} USD",
          details: "#{gig_date.strftime('%d/%m/%Y')} | #{gig.location}#{advance_text}",
          url: "/gigs/#{gig.id}"
        }
      }
    end
  end

  def tool_record_gig_payment(args)
    search_term = args['client_or_gig'].to_s.strip
    gig = find_gig_by_search(search_term)

    unless gig
      return { success: false, message: "No pude encontrar ningún show activo o reciente para '#{search_term}'." }
    end

    amount = args['amount'].to_f
    date_paid = parse_date(args['date_paid']) || Date.current
    payment_method = args['payment_method'].presence || 'cash'
    is_advance = args['is_advance'] == true
    notes = args['notes'].presence || 'Abono registrado vía Gig IA Copilot'

    payment = gig.gig_payments.create!(
      amount: amount,
      currency: 'USD',
      date_paid: date_paid,
      is_advance: is_advance,
      payment_method: payment_method,
      payer_name: gig.client_display_name,
      category: 'other',
      status: 'approved',
      notes: notes
    )

    remaining = gig.remaining_amount
    status_label = gig.paid_in_full? ? "¡SHOW SALDADO POR COMPLETO! 🎉" : "Saldo pendiente: $#{sprintf('%.2f', remaining)} USD."

    {
      success: true,
      message: "💳 Abono de $#{sprintf('%.2f', amount)} USD registrado para el show de #{gig.client_display_name}. #{status_label}",
      card: {
        type: 'payment_recorded',
        title: "💳 Abono Registrado ($#{sprintf('%.2f', amount)} USD)",
        amount: "$#{sprintf('%.2f', amount)} USD",
        details: "#{gig.client_display_name} - #{status_label}",
        url: "/gigs/#{gig.id}"
      }
    }
  end

  def tool_record_employee_payment(args)
    worker_name = args['worker_name'].to_s.strip
    worker = find_worker_by_search(worker_name)
    unless worker
      return { success: false, message: "No pude encontrar al músico o trabajador '#{worker_name}'." }
    end

    amount = args['amount'].to_f
    date_paid = parse_date(args['date_paid']) || Date.current
    payment_method = args['payment_method'].presence || 'cash'
    notes = args['notes'].presence || 'Pago de nómina registrado vía GigAI Copilot'

    gig = nil
    if args['gig_id_or_client'].present?
      gig = find_gig_by_search(args['gig_id_or_client'])
    end

    payment = company.employee_payments.create!(
      user: worker,
      gig: gig,
      amount: amount,
      expected_amount: amount,
      date_paid: date_paid,
      payment_method: payment_method,
      status: 'approved',
      funding_source: 'payroll_fund',
      notes: notes
    )

    new_balance = calculate_current_cash_balance
    gig_info = gig ? " para el show de #{gig.client_display_name}" : ""

    {
      success: true,
      message: "💵 Pago de nómina de $#{sprintf('%.2f', amount)} USD registrado para #{worker.display_name}#{gig_info}. Descontado del Fondo General. Saldo disponible actual en caja: $#{sprintf('%.2f', new_balance)} USD.",
      new_balance: new_balance,
      card: {
        type: 'employee_payment',
        title: "💵 Pago a Músico: #{worker.display_name}",
        amount: "-$#{sprintf('%.2f', amount)} USD",
        details: "#{date_paid.strftime('%d/%m/%Y')} | #{payment_method}#{gig_info}",
        url: "/employee_payments"
      }
    }
  end

  def tool_get_worker_balances(_args)
    metrics = WorkerBalanceService.build_metrics_for_company(company) rescue []
    with_balance = metrics.select { |m| m[:past_balance].to_f > 0 }
    total_owed = with_balance.sum { |m| m[:past_balance].to_f }.round(2)

    details_list = with_balance.map do |m|
      "• #{m[:worker]&.display_name}: $#{sprintf('%.2f', m[:past_balance].to_f)} USD pendiente"
    end

    msg = if total_owed.positive?
            "👥 Tienes compromisos pendientes con #{with_balance.count} músico(s) por un total de $#{sprintf('%.2f', total_owed)} USD:\n#{details_list.join("\n")}"
          else
            "✅ ¡Excelente! No tienes pagos pendientes con ningún músico en este momento."
          end

    {
      success: true,
      message: msg,
      total_owed: total_owed,
      workers: details_list,
      card: {
        type: 'worker_balances',
        title: "👥 Balances con Músicos",
        amount: "$#{sprintf('%.2f', total_owed)} USD",
        details: total_owed.positive? ? "#{with_balance.count} músico(s) con saldo pendiente" : "Cuentas al día con todo el equipo",
        url: "/employee_payments"
      }
    }
  end

  def tool_get_financial_status(_args)
    diagnostic = run_diagnostic
    {
      success: true,
      cash_balance: diagnostic[:cash_balance],
      alerts_count: diagnostic[:diagnostic_items].count,
      diagnostic_summary: diagnostic[:diagnostic_items].map { |d| "#{d[:title]}: #{d[:description]}" }.join(" | ")
    }
  end

  def tool_approve_payment(args)
    approve_all = args['approve_all'] == true || args['payment_type'] == 'all'
    target_name = args['worker_or_client_name'].to_s.strip.downcase
    payment_id = args['payment_id'].to_i

    approved_items = []

    # 1. Caso: Autorizar todos los pagos y abonos pendientes
    if approve_all
      company.employee_payments.pending_approval.find_each do |ep|
        approve_single_employee_payment(ep)
        approved_items << "Pago a #{ep.user&.display_name} ($#{sprintf('%.2f', ep.amount)} USD)"
      end

      GigPayment.joins(:gig).where(gigs: { company_id: company.id }).pending_approval.find_each do |gp|
        approve_single_gig_payment(gp)
        approved_items << "Abono de #{gp.payer_name || gp.gig&.client_display_name} ($#{sprintf('%.2f', gp.amount)} USD)"
      end

      if approved_items.empty?
        return { success: true, message: "No había ningún pago ni abono pendiente por autorizar en este momento." }
      end

      new_balance = calculate_current_cash_balance
      return {
        success: true,
        message: "✅ ¡Listos todos! Se autorizaron con éxito #{approved_items.count} pagos y abonos pendientes:\n#{approved_items.map { |i| "• #{i}" }.join("\n")}\n\nSaldo actual en Caja General: $#{sprintf('%.2f', new_balance)} USD.",
        new_balance: new_balance,
        card: {
          type: 'payment_approved',
          title: "✅ #{approved_items.count} Pagos Autorizados",
          amount: "Múltiples",
          details: approved_items.join(', '),
          url: "/employee_payments"
        }
      }
    end

    # 2. Buscar pago específico (por ID o por nombre)
    employee_payment = nil
    gig_payment = nil

    if payment_id.positive?
      employee_payment = company.employee_payments.pending_approval.find_by(id: payment_id)
      gig_payment = GigPayment.joins(:gig).where(gigs: { company_id: company.id }).pending_approval.find_by(id: payment_id) unless employee_payment
    end

    if target_name.present? && !employee_payment && !gig_payment
      # Buscar en pagos a músicos por nombre o correo
      employee_payment = company.employee_payments.pending_approval.joins(:user)
                                .where('LOWER(users.name) LIKE ? OR LOWER(users.email) LIKE ?', "%#{target_name}%", "%#{target_name}%")
                                .order(created_at: :desc).first

      # Si no, buscar en abonos de clientes
      unless employee_payment
        gig_payment = GigPayment.joins(:gig).where(gigs: { company_id: company.id }).pending_approval
                                .where('LOWER(payer_name) LIKE ? OR LOWER(gigs.client_email) LIKE ?', "%#{target_name}%", "%#{target_name}%")
                                .order(created_at: :desc).first
      end
    end

    # Si no se pasó ni ID ni nombre, pero hay un único pago pendiente, tomarlo automáticamente
    if !employee_payment && !gig_payment && target_name.blank? && payment_id.zero?
      pending_eps = company.employee_payments.pending_approval
      pending_gps = GigPayment.joins(:gig).where(gigs: { company_id: company.id }).pending_approval
      if pending_eps.count == 1 && pending_gps.count.zero?
        employee_payment = pending_eps.first
      elsif pending_gps.count == 1 && pending_eps.count.zero?
        gig_payment = pending_gps.first
      end
    end

    if employee_payment
      approve_single_employee_payment(employee_payment)
      new_balance = calculate_current_cash_balance
      worker_name = employee_payment.user&.display_name
      amount_str = sprintf('%.2f', employee_payment.amount)

      {
        success: true,
        message: "✅ ¡Pago autorizado con éxito! Se aprobó el reporte de **#{worker_name}** por **$#{amount_str} USD** (#{employee_payment.payment_method.presence || 'Efectivo'}). El saldo del músico ha sido actualizado y se le notificó la confirmación.\n\nSaldo actual disponible en Caja General: $#{sprintf('%.2f', new_balance)} USD.",
        new_balance: new_balance,
        card: {
          type: 'payment_approved',
          title: "✅ Pago Autorizado: #{worker_name}",
          amount: "$#{amount_str} USD",
          details: "#{employee_payment.payment_method.presence || 'Efectivo'} • Fecha: #{employee_payment.date_paid&.strftime('%d/%m/%Y')}",
          url: "/employee_payments"
        }
      }
    elsif gig_payment
      approve_single_gig_payment(gig_payment)
      new_balance = calculate_current_cash_balance
      payer_name = gig_payment.payer_name || gig_payment.gig&.client_display_name
      amount_str = sprintf('%.2f', gig_payment.amount)

      {
        success: true,
        message: "✅ ¡Abono autorizado con éxito! Se aprobó el comprobante de **#{payer_name}** por **$#{amount_str} USD** para el show de #{gig_payment.gig&.client_display_name}. El dinero ya está sumado a la Caja General.\n\nSaldo actual en Caja: $#{sprintf('%.2f', new_balance)} USD.",
        new_balance: new_balance,
        card: {
          type: 'payment_approved',
          title: "✅ Abono Autorizado: #{payer_name}",
          amount: "$#{amount_str} USD",
          details: "Show: #{gig_payment.gig&.client_display_name}",
          url: "/gigs/#{gig_payment.gig_id}"
        }
      }
    else
      {
        success: false,
        message: "No encontré ningún pago o abono pendiente de autorización que coincida con '#{target_name.presence || payment_id}'."
      }
    end
  end

  def approve_single_employee_payment(ep)
    ActiveRecord::Base.transaction do
      ep.funding_source = 'payroll_fund' if ep.funding_source.blank?
      ep.status = 'approved'
      ep.approved_at = Time.current
      ep.save!
    end

    # Notificar al trabajador
    target_area = ep.user&.musician? ? 'musicians' : 'staffs'
    amount_formatted = "$#{sprintf('%.2f', ep.amount)}"
    show_label = ep.gig.present? ? (ep.gig.client&.name || "Show del #{ep.gig.date&.strftime('%d/%m/%Y')}") : "Pago general"

    AppNotification.create(
      company: company,
      sender: user,
      recipient: ep.user,
      target_area: target_area,
      notification_type: 'payment_alert',
      title: "✅ Pago Confirmado",
      message: "Tu reporte de pago de #{amount_formatted} (#{show_label}) ha sido confirmado y aprobado por el líder vía GigAI Copilot. Tu balance ha sido actualizado.",
      action_url: "/my_payments"
    ) rescue nil

    # Marcar como leída la notificación de este reporte en el buzón del líder
    if ep.user.present?
      notifs = AppNotification.for_user(user).unread_by(user).where(sender_id: ep.user_id, notification_type: 'payment_alert')
      notifs.each { |n| n.mark_as_read_by!(user) rescue nil }
    end
  end

  def approve_single_gig_payment(gp)
    gp.audit_reason = "Aprobación de abono por #{user.display_name} vía GigAI Copilot"
    gp.approved_at = Time.current
    gp.approved_by = user
    gp.status = 'approved'
    gp.save!

    # Marcar como leída la notificación correspondiente si existía
    notifs = AppNotification.for_user(user).unread_by(user).where("action_url LIKE ?", "%/gigs/#{gp.gig_id}%")
    notifs.each { |n| n.mark_as_read_by!(user) rescue nil }
  end

  def tool_reject_payment(args)
    target_name = args['worker_or_client_name'].to_s.strip.downcase
    payment_id = args['payment_id'].to_i
    reason = args['reason'].presence || "Rechazado por el líder vía GigAI Copilot."

    employee_payment = nil
    if payment_id.positive?
      employee_payment = company.employee_payments.pending_approval.find_by(id: payment_id)
    end
    if target_name.present? && !employee_payment
      employee_payment = company.employee_payments.pending_approval.joins(:user)
                                .where('LOWER(users.name) LIKE ?', "%#{target_name}%")
                                .order(created_at: :desc).first
    end
    if !employee_payment && target_name.blank? && payment_id.zero?
      employee_payment = company.employee_payments.pending_approval.first
    end

    if employee_payment
      employee_payment.status = 'rejected'
      employee_payment.rejection_reason = reason
      employee_payment.save!

      target_area = employee_payment.user&.musician? ? 'musicians' : 'staffs'
      amount_formatted = "$#{sprintf('%.2f', employee_payment.amount)}"

      AppNotification.create(
        company: company,
        sender: user,
        recipient: employee_payment.user,
        target_area: target_area,
        notification_type: 'urgent',
        title: "❌ Reporte de Pago Rechazado",
        message: "Tu reporte de pago de #{amount_formatted} no fue aceptado: #{reason}",
        action_url: "/my_payments"
      ) rescue nil

      notifs = AppNotification.for_user(user).unread_by(user).where(sender_id: employee_payment.user_id, notification_type: 'payment_alert')
      notifs.each { |n| n.mark_as_read_by!(user) rescue nil }

      {
        success: true,
        message: "❌ El reporte de pago de **#{employee_payment.user&.display_name}** por **$#{amount_formatted} USD** fue rechazado. Se le notificó con el motivo: '#{reason}'.",
        card: {
          type: 'payment_rejected',
          title: "❌ Pago Rechazado: #{employee_payment.user&.display_name}",
          amount: "$#{amount_formatted} USD",
          details: "Motivo: #{reason}",
          url: "/employee_payments"
        }
      }
    else
      { success: false, message: "No encontré ningún reporte de pago pendiente para rechazar." }
    end
  end

  def tool_get_pending_approvals(_args)
    pending_worker_reports = company.employee_payments.pending_approval.includes(:user, :gig).order(created_at: :desc)
    pending_client_abonos = GigPayment.joins(:gig).where(gigs: { company_id: company.id }).pending_approval.includes(:gig).order(created_at: :desc)
    unread_notifs = AppNotification.for_user(user).unread_by(user).recent_first.limit(5) rescue []

    worker_items = pending_worker_reports.map do |ep|
      "• ⏳ **#{ep.user&.display_name}** reportó **$#{sprintf('%.2f', ep.amount)} USD** vía #{ep.payment_method.presence || 'Efectivo'} el #{ep.date_paid&.strftime('%d/%m/%Y')}#{ep.notes.present? ? " (Nota: #{ep.notes})" : ""}"
    end

    client_items = pending_client_abonos.map do |gp|
      "• 💳 **#{gp.payer_name || gp.gig&.client_display_name}** abonó **$#{sprintf('%.2f', gp.amount)} USD** para el show de #{gp.gig&.client_display_name}"
    end

    notif_items = unread_notifs.map do |n|
      "• 🔔 **#{n.title}**: #{n.message.to_s.truncate(100)}"
    end

    total_pending_count = worker_items.count + client_items.count

    summary_text = if total_pending_count.positive?
      parts = []
      parts << "Tienes **#{worker_items.count} reporte(s) de músicos** pendientes de autorizar:\n#{worker_items.join("\n")}" if worker_items.any?
      parts << "Tienes **#{client_items.count} comprobante(s) de clientes** pendientes de confirmar:\n#{client_items.join("\n")}" if client_items.any?
      parts << "Otras notificaciones sin leer:\n#{notif_items.join("\n")}" if notif_items.any?
      parts << "💡 *Puedes decirme 'Autoriza el pago de [Nombre]' o 'Autoriza todos los pagos' y lo haré al instante.*"
      parts.join("\n\n")
    else
      "✅ ¡No tienes pagos ni abonos pendientes de autorizar! Todo está al día."
    end

    {
      success: true,
      pending_count: total_pending_count,
      message: summary_text,
      worker_reports: worker_items,
      client_abonos: client_items,
      unread_notifications: notif_items
    }
  end

  # ==========================================
  # HELPERS
  # ==========================================

  def calculate_current_cash_balance
    total_gigs_received = GigPayment.joins(:gig).where(gigs: { company_id: company.id }).approved.sum(:amount).to_f
    total_cash_deposits = company.cash_adjustments.inflows.sum(:amount).to_f
    total_inflow = total_gigs_received + total_cash_deposits

    total_payroll_paid = company.employee_payments.approved.where.not(funding_source: 'external_capital').sum(:amount).to_f
    total_maintenance = MaintenanceRecord.joins(:item).where(items: { company_id: company.id }).sum(:cost).to_f
    total_investments = company.investments.sum(:amount).to_f
    total_cash_withdrawals = company.cash_adjustments.outflows.sum(:amount).to_f
    total_outflow = total_payroll_paid + total_maintenance + total_investments + total_cash_withdrawals

    (total_inflow - total_outflow).round(2)
  end

  def find_or_create_client(name, phone, email)
    clean_name = name.to_s.strip
    client = company.clients.where('LOWER(name) = ?', clean_name.downcase).first

    client ||= company.clients.create!(
      name: clean_name,
      phone: phone.presence || "0000000000",
      email: email.presence || "#{clean_name.parameterize.presence || 'cliente'}@temp.gigmanager.local",
      priority: 2
    )
    client
  end

  def find_or_create_worker(name)
    clean_name = name.to_s.strip
    return nil if clean_name.blank?

    worker = company.users.workers.where('LOWER(name) = ? OR LOWER(email) LIKE ?', clean_name.downcase, "#{clean_name.downcase}%").first
    worker ||= User.create_eventual_worker!(company: company, name: clean_name, role: 'musician')
    worker
  end

  def find_worker_by_search(query)
    clean = query.to_s.strip.downcase
    return nil if clean.blank?
    company.users.workers.where('LOWER(name) LIKE ? OR LOWER(email) LIKE ?', "%#{clean}%", "%#{clean}%").first ||
      find_or_create_worker(query)
  end

  def find_gig_by_search(query)
    clean = query.to_s.strip.downcase
    return nil if clean.blank?

    # Buscar por id directo
    if clean.match?(/^\d+$/)
      return company.gigs.find_by(id: clean.to_i)
    end

    # Buscar por cliente en shows activos o recientes
    company.gigs.joins(:client)
           .where('LOWER(clients.name) LIKE ?', "%#{clean}%")
           .order(date: :desc)
           .first ||
      company.gigs.where('LOWER(client_email) LIKE ?', "%#{clean}%").order(date: :desc).first
  end

  def parse_date(date_str)
    return nil if date_str.blank?
    Date.parse(date_str.to_s) rescue nil
  end

  def unconfigured_fallback_response(user_message)
    # Si la clave no está configurada, podemos seguir ofreciendo el diagnóstico de la caja localmente!
    diagnostic = run_diagnostic
    alerts_text = diagnostic[:diagnostic_items].map { |i| "• *#{i[:title]}*: #{i[:description]}" }.join("\n")

    {
      reply: "👋 ¡Hola! Soy **Gig IA Copilot**.\n\n" \
             "💰 **Saldo actual en Caja:** $#{sprintf('%.2f', diagnostic[:cash_balance])} USD\n\n" \
             "🔍 **Diagnóstico de tu Empresa:**\n#{alerts_text.presence || '✅ ¡Todo se encuentra al día!'}\n\n" \
             "💡 *Nota:* Para habilitar el procesamiento por voz y comandos inteligentes completos en lenguaje natural con Google Gemini, agrega tu clave gratuita `GEMINI_API_KEY` en tus variables de entorno o credenciales.",
      actions_taken: [],
      cards: []
    }
  end
end
