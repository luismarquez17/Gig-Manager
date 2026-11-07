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

    # Contexto rápido de Inventario y Taller
    total_equipos = company.items.count rescue 0
    equipos_danados = company.items.where(status: 'Dañado').count rescue 0
    equipos_en_taller = MaintenanceRecord.joins(:item).where(items: { company_id: company.id }, status: [:pending, :in_repair]).count rescue 0
    repairs_active = MaintenanceRecord.joins(:item).where(items: { company_id: company.id }, status: [:pending, :in_repair]).includes(:item).limit(4) rescue []
    taller_lines = repairs_active.map { |r| "• #{r.item&.name} (Costo: $#{r.cost} USD, Estado: #{r.status}): #{r.description.to_s.truncate(60)}" }
    taller_context = if taller_lines.any?
      "TALLER Y MANTENIMIENTO ACTIVO (#{equipos_en_taller} equipos):\n#{taller_lines.join("\n")}"
    else
      "Taller al día: no hay reparaciones activas pendientes."
    end

    # Contexto rápido de Upsells y Paquetes
    upsells_list = StandardUpsell.where(company_id: [company.id, nil]).active_catalog.limit(6).map { |u| "#{u.emoji} #{u.title} ($#{u.price} USD)" }.join(', ') rescue ""
    packages_list = company.preset_budgets.limit(4).map { |p| "#{p.title} ($#{p.price} USD)" }.join(', ') rescue ""

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
      5. GESTIÓN INTEGRAL DE OPERACIONES (INVENTARIO, TALLER, UPSELLS Y REPORTES):
         - Inventario: Conocer el stock de equipos, disponibilidad y estado físico (cables, cornetas, luces, etc.).
         - Taller: Monitorear equipos en reparación, costos acumulados y registrar ingresos de equipos dañados al taller.
         - Paquetes & Upsells: Recomendar servicios adicionales (humo, chisperos, subwoofers, horas extra) y paquetes de presupuesto.
         - Reporte Mensual Comparativo: Generar reportes financieros detallados entre el mes actual y el mes anterior con cálculo de variaciones (% delta).

      DATOS DE CONTEXTO ACTUAL DE LA EMPRESA:
      - Fecha de hoy: #{today_str}
      - Saldo neto disponible en el Fondo General (Caja): $#{sprintf('%.2f', cash_balance)} USD
      - Moneda principal: USD ($)
      - Personal / Músicos registrados: #{workers_list.presence || 'Sin personal registrado aún'}
      - Próximos Shows:
      #{upcoming.presence || 'No hay shows próximos en los próximos días.'}
      - Resumen de Inventario: #{total_equipos} equipos en catálogo (#{equipos_danados} dañados, #{equipos_en_taller} en taller).
      - Catálogo de Upsells disponibles: #{upsells_list.presence || 'Ninguno configurado'}
      - Paquetes de Shows: #{packages_list.presence || 'Estándar'}

      #{post_gig_context}

      #{taller_context}

      #{pending_approvals_context}

      #{unread_notifs_context}

      REGLAS DE ACTUACIÓN:
      - REPORTE MENSUAL COMPARATIVO (¡MUY IMPORTANTE!):
        Si el usuario te dice: "dame un reporte de este mes comparado con el anterior", "¿cómo vamos este mes vs el mes pasado?", "comparativa mensual", "reporte de este mes":
        Llama INMEDIATAMENTE a la herramienta `get_monthly_comparative_report`. Al recibir los datos, resume en tu respuesta hablada y escrita los números clave: Cobranzas de shows, gastos de caja, nómina de músicos, gastos en taller, saldo neto final y los porcentajes de variación (% delta).
      - INVENTARIO DE EQUIPOS:
        Si el usuario pregunta por equipos, cables, cornetas, luces, consolas, stock o disponibilidad (ej. "¿cuántos micrófonos tenemos?", "¿tenemos cables disponibles?", "¿qué equipos están dañados?"):
        Llama a la herramienta `get_inventory_status`.
      - TALLER Y MANTENIMIENTO:
        Si el usuario pregunta por el taller, reparaciones o equipos dañados (ej. "¿qué tenemos en el taller?", "¿cuánto hemos gastado en reparaciones?"):
        Llama a `get_workshop_status`.
        Si el usuario dice que mandó o va a mandar un equipo al taller (ej. "manda la corneta al taller porque suena con ruido, costará $30"):
        Llama a `record_maintenance_entry`.
      - PAQUETES Y UPSELLS:
        Si el usuario pregunta por los paquetes de shows, precios de servicios adicionales o upsells (ej. "¿qué upsells ofrecemos?", "¿cuánto cobramos por la máquina de humo?"):
        Llama a `get_packages_and_upsells`.
      - OTRAS ÁREAS (METAS, COMPRAS, COTIZACIONES):
        Si el usuario pregunta por la lista de compras de equipos o metas de ahorro, llama a `get_company_area_overview`.
      - PROACTIVIDAD EN PAGOS PENDIENTES Y NOTIFICACIONES:
        Si en la sección "REPORTES DE PAGO Y ABONOS PENDIENTES DE AUTORIZAR" hay elementos, y el usuario te saluda ("hola", "¿qué hay pendiente?", "¿qué notificaciones tengo?"):
        ¡INFORMA DE INMEDIATO!
      - AUTORIZAR PAGOS:
        Si el usuario dice "autoriza el pago de [Nombre]", "aprueba el pago de Gabriel", "confirma el pago", "sí, autorízalo", o "autorizar todos":
        Llama de inmediato a la herramienta `approve_payment` con el nombre de la persona (o `approve_all: true` si pide todos).
      - RECHAZAR PAGOS:
        Si el usuario dice "rechaza el pago de Gabriel" o "no lo aceptes":
        Llama a la herramienta `reject_payment` con el motivo del rechazo.
      - CONSULTAR NOTIFICACIONES / PENDIENTES:
        Si el usuario pide ver notificaciones o pendientes, llama a `get_pending_approvals`.
      - CAJA Y GASTOS DIRECTOS:
        Si el usuario dice que gastó dinero en efectivo (ej. "anota $20 de taxi" o "gasté $15 en cables"), llama a `record_cash_adjustment` con adjustment_type: "withdrawal".
        Si entró dinero a caja, llama a `record_cash_adjustment` con adjustment_type: "deposit" (o `record_gig_payment` si menciona un show/cliente).
      - AGENDAR Y NÓMINA:
        Usa `create_gig`, `record_employee_payment` y `get_worker_balances` según corresponda.
      - NUNCA le digas al usuario que debe repartir o asignar dinero a sub-fondos, porque solo existe un fondo general único.
      - ESTILO CONVERSACIONAL Y DE VOZ: Tus respuestas se leen en voz alta con audio interactivo por el navegador. Responde siempre en español natural, fluido, conciso y motivador. Sé muy claro sobre los montos y acciones realizadas, con frases directas y agradables de escuchar.
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
          },
          {
            name: 'get_inventory_status',
            description: 'Consulta el inventario de equipos (disponibilidad, cantidades, estado excelente/operativo/dañado, y categorías como cables, cornetas, luces, pantallas, consolas).',
            parameters: {
              type: 'OBJECT',
              properties: {
                category: {
                  type: 'STRING',
                  description: 'Categoría opcional a filtrar (ej. "Cables", "Cornetas", "Luces", "Microfonos", "Consolas")'
                },
                status: {
                  type: 'STRING',
                  enum: %w[Excelente Operativo Dañado],
                  description: 'Estado físico del equipo para filtrar'
                },
                search_query: {
                  type: 'STRING',
                  description: 'Nombre o término de búsqueda del equipo (ej. "xlr", "shure", "jbl", "pantalla")'
                }
              }
            }
          },
          {
            name: 'get_workshop_status',
            description: 'Consulta el taller y área de reparaciones/mantenimiento (equipos en reparación, costo acumulado, historial técnico y averías reportadas).',
            parameters: {
              type: 'OBJECT',
              properties: {
                status_filter: {
                  type: 'STRING',
                  enum: %w[active pending in_repair fixed discarded all],
                  description: 'Filtro de estado: "active" (en taller/reparación), "fixed" (reparados), "discarded" (descartados) o "all". Por defecto es "active".'
                },
                item_name: {
                  type: 'STRING',
                  description: 'Nombre del equipo a consultar en el taller (opcional)'
                }
              }
            }
          },
          {
            name: 'record_maintenance_entry',
            description: 'Registra el ingreso de un equipo averiado al taller o actualiza el estado de una reparación, especificando la falla y el costo.',
            parameters: {
              type: 'OBJECT',
              properties: {
                item_name: {
                  type: 'STRING',
                  description: 'Nombre del equipo que entra al taller (ej. "Corneta JBL", "Cable XLR 10m")'
                },
                description: {
                  type: 'STRING',
                  description: 'Descripción detallada de la falla o trabajo a realizar (ej. "Falso contacto en conector XLR", "Cono de bajo quemado")'
                },
                cost: {
                  type: 'NUMBER',
                  description: 'Costo estimado o pagado por la reparación en USD'
                },
                status: {
                  type: 'STRING',
                  enum: %w[pending in_repair fixed discarded],
                  description: 'Estado del mantenimiento. Por defecto es "in_repair".'
                }
              },
              required: %w[item_name description]
            }
          },
          {
            name: 'get_packages_and_upsells',
            description: 'Consulta los paquetes de shows predefinidos (PresetBudgets), catálogo de servicios adicionales / upsells (máquinas de humo, sparkulas, subwoofers, horas extra) y kits de equipos.',
            parameters: {
              type: 'OBJECT',
              properties: {
                filter: {
                  type: 'STRING',
                  enum: %w[all upsells preset_budgets kits client_requests],
                  description: 'Filtro para ver solo upsells, solo paquetes de shows, solo kits de equipos o todo el catálogo.'
                }
              }
            }
          },
          {
            name: 'get_monthly_comparative_report',
            description: 'Genera un reporte financiero y operativo comparativo profundo entre dos meses (por defecto este mes vs el mes anterior). Analiza cobranzas de shows, total facturado, gastos de caja en efectivo, nómina de músicos, gastos en taller, saldo neto y porcentajes de variación (% delta).',
            parameters: {
              type: 'OBJECT',
              properties: {
                target_month: {
                  type: 'STRING',
                  description: 'Mes a evaluar (ej. "current", "este mes", "2026-11", "noviembre"). Por defecto es el mes actual.'
                },
                compare_month: {
                  type: 'STRING',
                  description: 'Mes con el cual comparar (ej. "previous", "mes anterior", "2026-10", "octubre"). Por defecto es el mes anterior.'
                }
              }
            }
          },
          {
            name: 'get_company_area_overview',
            description: 'Consulta el estado de otras áreas clave de la empresa: metas de reinversión/ahorro, lista de compras de equipos pendientes y presupuestos emitidos a clientes.',
            parameters: {
              type: 'OBJECT',
              properties: {
                area: {
                  type: 'STRING',
                  enum: %w[all goals shopping quotes],
                  description: 'Área específica a consultar: "goals" (metas de ahorro), "shopping" (lista de compras de equipos), "quotes" (cotizaciones enviadas) o "all".'
                }
              }
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
    when 'get_inventory_status'
      tool_get_inventory_status(args)
    when 'get_workshop_status'
      tool_get_workshop_status(args)
    when 'record_maintenance_entry'
      tool_record_maintenance_entry(args)
    when 'get_packages_and_upsells'
      tool_get_packages_and_upsells(args)
    when 'get_monthly_comparative_report'
      tool_get_monthly_comparative_report(args)
    when 'get_company_area_overview'
      tool_get_company_area_overview(args)
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
  # HERRAMIENTAS DE INVENTARIO Y TALLER
  # ==========================================

  def tool_get_inventory_status(args)
    category = args['category'].to_s.strip
    status_filter = args['status'].to_s.strip
    query = args['search_query'].to_s.strip.downcase

    scope = company.items.includes(:inventory_items)
    scope = scope.where('LOWER(category) = ?', category.downcase) if category.present?
    scope = scope.where(status: status_filter) if status_filter.present?
    if query.present?
      scope = scope.where('LOWER(name) LIKE ? OR LOWER(sub_category) LIKE ? OR LOWER(category) LIKE ?', "%#{query}%", "%#{query}%", "%#{query}%")
    end

    items = scope.order(category: :asc, name: :asc).limit(40)
    total_company_items = company.items.count
    damaged_total = company.items.where(status: 'Dañado').count
    operativo_total = company.items.where(status: ['Operativo', 'Excelente']).count

    lines = items.map do |item|
      "• **#{item.name}** (#{item.category || 'General'}#{item.sub_category.present? ? " - #{item.sub_category}" : ''}): Total: #{item.total_count} (Disponibles: #{item.available_count}, Dañados: #{item.damaged_count}, Taller: #{item.maintenance_count}) | Estado: #{item.status}"
    end

    summary = if items.empty?
      "📦 No se encontraron equipos en inventario que coincidan con la búsqueda."
    else
      "📦 **Inventario de Equipos (#{items.count} resultados):**\n\n#{lines.join("\n")}\n\n" \
      "📊 **Balance Global:** #{total_company_items} equipos registrados en total (#{operativo_total} operativos/excelentes, #{damaged_total} con daños/alerta)."
    end

    {
      success: true,
      total_listed: items.count,
      message: summary,
      card: {
        type: 'inventory_status',
        title: "📦 Inventario de Equipos",
        amount: "#{operativo_total}/#{total_company_items} Operativos",
        details: "#{damaged_total} con daños o en taller • #{company.items.pluck(:category).compact.uniq.count} categorías",
        url: "/items"
      }
    }
  end

  def tool_get_workshop_status(args)
    status_filter = args['status_filter'].to_s.strip.downcase
    item_name = args['item_name'].to_s.strip.downcase

    scope = MaintenanceRecord.joins(:item).where(items: { company_id: company.id }).includes(:item)

    case status_filter
    when 'pending'
      scope = scope.where(status: :pending)
    when 'in_repair'
      scope = scope.where(status: :in_repair)
    when 'fixed'
      scope = scope.where(status: :fixed)
    when 'discarded'
      scope = scope.where(status: :discarded)
    when 'all'
      # sin filtro
    else
      scope = scope.where(status: [:pending, :in_repair])
    end

    if item_name.present?
      scope = scope.where('LOWER(items.name) LIKE ?', "%#{item_name}%")
    end

    records = scope.order(created_at: :desc).limit(20)
    total_spent_in_repairs = MaintenanceRecord.joins(:item).where(items: { company_id: company.id }).sum(:cost).to_f
    active_repairs_count = MaintenanceRecord.joins(:item).where(items: { company_id: company.id }, status: [:pending, :in_repair]).count

    lines = records.map do |mr|
      item_title = mr.item&.name || "Equipo ##{mr.item_id}"
      cost_str = "$#{sprintf('%.2f', mr.cost)} USD"
      date_str = mr.started_at&.strftime('%d/%m/%Y') || mr.created_at.strftime('%d/%m/%Y')
      status_label = case mr.status
                     when 'pending' then '⏳ Pendiente'
                     when 'in_repair' then '🔧 En reparación'
                     when 'fixed' then '✅ Reparado'
                     when 'discarded' then '🗑️ Descartado'
                     else mr.status
                     end
      "• **#{item_title}** [#{status_label}] | Costo: #{cost_str} | Desde: #{date_str} | Falla: #{mr.description}"
    end

    summary = if records.empty?
      "🛠️ **Taller y Mantenimiento:**\nNo hay equipos registrados bajo este criterio. Actualmente hay #{active_repairs_count} equipos activos en reparación."
    else
      "🛠️ **Taller y Mantenimiento (#{records.count} registros):**\n\n#{lines.join("\n")}\n\n" \
      "💰 Total histórico invertido en reparaciones: **$#{sprintf('%.2f', total_spent_in_repairs)} USD**."
    end

    {
      success: true,
      total_listed: records.count,
      active_repairs_count: active_repairs_count,
      message: summary,
      card: {
        type: 'workshop_status',
        title: "🛠️ Taller y Reparaciones",
        amount: "#{active_repairs_count} en taller",
        details: "Gasto acumulado: $#{sprintf('%.2f', total_spent_in_repairs)} USD",
        url: "/maintenance_records"
      }
    }
  end

  def tool_record_maintenance_entry(args)
    item_name = args['item_name'].to_s.strip
    desc = args['description'].to_s.strip
    cost = args['cost'].to_f
    status_param = args['status'].to_s.strip.downcase
    status_enum = case status_param
                  when 'fixed' then :fixed
                  when 'discarded' then :discarded
                  when 'pending' then :pending
                  else :in_repair
                  end

    item = company.items.where('LOWER(name) LIKE ?', "%#{item_name.downcase}%").first
    unless item
      return { success: false, message: "No encontré en el inventario ningún equipo llamado '#{item_name}'." }
    end

    record = MaintenanceRecord.create!(
      item: item,
      description: desc.presence || "Ingreso al taller por mantenimiento reportado vía GigAI Copilot",
      cost: [cost, 0.0].max,
      status: status_enum,
      started_at: Date.current
    )

    item.sync_status_from_inventory!

    status_label = status_enum == :in_repair ? "en reparación" : status_enum.to_s
    cost_str = "$#{sprintf('%.2f', record.cost)} USD"
    {
      success: true,
      message: "🛠️ ¡Equipo enviado al taller con éxito!\n• **Equipo:** #{item.name}\n• **Estado:** #{status_label}\n• **Costo asignado:** #{cost_str}\n• **Falla:** #{record.description}.",
      card: {
        type: 'workshop_status',
        title: "🛠️ Ingreso a Taller: #{item.name}",
        amount: cost_str,
        details: record.description.to_s.truncate(80),
        url: "/maintenance_records"
      }
    }
  end

  # ==========================================
  # PAQUETES Y UPSELLS
  # ==========================================

  def tool_get_packages_and_upsells(args)
    filter = args['filter'].to_s.strip.downcase

    upsells = StandardUpsell.where(company_id: [company.id, nil]).active_catalog
    packages = company.preset_budgets.order(position: :asc, created_at: :asc)
    kits = company.kits.includes(kit_items: :item)
    client_requests = GigUpsellRequest.where(company_id: company.id).order(created_at: :desc).limit(10)

    parts = []

    if %w[all upsells ''].include?(filter)
      upsell_lines = upsells.map do |u|
        "• #{u.emoji} **#{u.title}**: $#{sprintf('%.2f', u.price)} #{u.currency}#{u.description.present? ? " - #{u.description.truncate(90)}" : ''}"
      end
      parts << "✨ **Catálogo de Servicios Adicionales (Upsells):**\n#{upsell_lines.join("\n")}" if upsell_lines.any?
    end

    if %w[all preset_budgets packages ''].include?(filter)
      pkg_lines = packages.map do |p|
        "• 🎸 **#{p.title}**: $#{sprintf('%.2f', p.price)} #{p.currency}#{p.description.present? ? " - #{p.description.truncate(90)}" : ''}"
      end
      parts << "📦 **Paquetes y Presupuestos Predefinidos de Shows:**\n#{pkg_lines.join("\n")}" if pkg_lines.any?
    end

    if %w[all kits ''].include?(filter)
      kit_lines = kits.map do |k|
        gear = k.kit_items.map { |ki| "#{ki.item&.name} (x#{ki.quantity})" }.join(', ')
        "• 🎛️ **Kit '#{k.name}'**: #{gear.presence || 'Sin equipos asignados'}"
      end
      parts << "🧰 **Kits de Equipos para Shows:**\n#{kit_lines.join("\n")}" if kit_lines.any?
    end

    if %w[all client_requests ''].include?(filter) && client_requests.any?
      req_lines = client_requests.map do |cr|
        "• #{cr.emoji} **#{cr.title}** para show de #{cr.gig&.client_display_name} | $#{cr.price} USD | Estado: #{cr.status.upcase}"
      end
      parts << "📋 **Solicitudes Recientes de Upsells por Clientes:**\n#{req_lines.join("\n")}"
    end

    summary = parts.join("\n\n")

    {
      success: true,
      message: summary,
      upsells_count: upsells.count,
      packages_count: packages.count,
      kits_count: kits.count,
      card: {
        type: 'packages_upsells',
        title: "✨ Paquetes & Upsells",
        amount: "#{upsells.count} Upsells Activos",
        details: "#{packages.count} Paquetes • #{kits.count} Kits de Sonido",
        url: "/standard_upsells"
      }
    }
  end

  # ==========================================
  # REPORTE COMPARATIVO MENSUAL
  # ==========================================

  def tool_get_monthly_comparative_report(args)
    target_date = parse_month_string(args['target_month'], Date.current)
    compare_date = parse_month_string(args['compare_month'], Date.current.prev_month)

    # Si por alguna razón comparan el mismo mes, forzar que compare_date sea el mes anterior
    compare_date = target_date.prev_month if target_date.year == compare_date.year && target_date.month == compare_date.month

    target_start = target_date.beginning_of_month
    target_end = target_date.end_of_month
    comp_start = compare_date.beginning_of_month
    comp_end = compare_date.end_of_month

    target_m = calculate_month_metrics(target_start, target_end)
    comp_m = calculate_month_metrics(comp_start, comp_end)

    # Variaciones porcentuales (% delta)
    delta_revenue = calc_delta(target_m[:total_collected], comp_m[:total_collected])
    delta_contracted = calc_delta(target_m[:gigs_amount], comp_m[:gigs_amount])
    delta_gigs = calc_delta(target_m[:gigs_count], comp_m[:gigs_count])
    delta_cash_expenses = calc_delta(target_m[:cash_withdrawals], comp_m[:cash_withdrawals])
    delta_payroll = calc_delta(target_m[:payroll_paid], comp_m[:payroll_paid])
    delta_maintenance = calc_delta(target_m[:maintenance_cost], comp_m[:maintenance_cost])
    delta_net = calc_delta(target_m[:net_cashflow], comp_m[:net_cashflow])

    target_label = month_label_es(target_date)
    compare_label = month_label_es(compare_date)

    summary_text = <<~REPORT
      📊 **Reporte Comparativo: #{target_label} vs. #{compare_label}**

      💰 **1. Ingresos y Cobranzas de Shows:**
      • **Recaudado en Shows:** $#{sprintf('%.2f', target_m[:total_collected])} USD (#{target_m[:payments_count]} cobros) vs. $#{sprintf('%.2f', comp_m[:total_collected])} USD (#{format_delta(delta_revenue)})
      • **Valor Contratado en Shows:** $#{sprintf('%.2f', target_m[:gigs_amount])} USD vs. $#{sprintf('%.2f', comp_m[:gigs_amount])} USD (#{format_delta(delta_contracted)})
      • **Cantidad de Shows:** #{target_m[:gigs_count]} shows vs. #{comp_m[:gigs_count]} shows (#{format_delta(delta_gigs)})

      💸 **2. Egresos y Salidas del Fondo General:**
      • **Nómina pagada a Músicos/Staff:** $#{sprintf('%.2f', target_m[:payroll_paid])} USD (#{target_m[:payroll_count]} pagos) vs. $#{sprintf('%.2f', comp_m[:payroll_paid])} USD (#{format_delta(delta_payroll)})
      • **Gastos Operativos en Efectivo (Caja):** $#{sprintf('%.2f', target_m[:cash_withdrawals])} USD vs. $#{sprintf('%.2f', comp_m[:cash_withdrawals])} USD (#{format_delta(delta_cash_expenses)})
      • **Gastos de Taller y Reparaciones:** $#{sprintf('%.2f', target_m[:maintenance_cost])} USD vs. $#{sprintf('%.2f', comp_m[:maintenance_cost])} USD (#{format_delta(delta_maintenance)})

      📈 **3. Flujo Neto de Efectivo (Margen de Caja):**
      • **#{target_label}:** $#{sprintf('%.2f', target_m[:net_cashflow])} USD
      • **#{compare_label}:** $#{sprintf('%.2f', comp_m[:net_cashflow])} USD
      • **Variación Neta:** #{format_delta(delta_net)}

      💡 **Diagnóstico Operativo:**
      #{generate_report_insight(target_m, comp_m, delta_revenue, delta_net)}
    REPORT

    {
      success: true,
      message: summary_text.strip,
      target_month: target_label,
      compare_month: compare_label,
      metrics: {
        target: target_m,
        compare: comp_m,
        deltas: {
          revenue: delta_revenue,
          contracted: delta_contracted,
          gigs: delta_gigs,
          payroll: delta_payroll,
          cash_expenses: delta_cash_expenses,
          net: delta_net
        }
      },
      card: {
        type: 'comparative_report',
        title: "📊 Comparativa: #{target_label} vs. #{compare_label}",
        amount: "$#{sprintf('%.2f', target_m[:net_cashflow])} USD Neto",
        details: "Cobrado: $#{sprintf('%.2f', target_m[:total_collected])} (#{format_delta(delta_revenue)}) • Nómina: $#{sprintf('%.2f', target_m[:payroll_paid])} • Shows: #{target_m[:gigs_count]}",
        url: "/financials"
      }
    }
  end

  def calculate_month_metrics(start_date, end_date)
    # Shows
    gigs_scope = company.gigs.where(date: start_date..end_date)
    gigs_count = gigs_scope.count
    gigs_amount = gigs_scope.sum(:amount).to_f
    gigs_completed = gigs_scope.where('date <= ?', Date.current).count

    # Cobranzas de shows (GigPayment aprobados)
    gp_scope = GigPayment.joins(:gig)
                         .where(gigs: { company_id: company.id }, status: 'approved')
                         .where(date_paid: start_date..end_date)
    total_collected = gp_scope.sum(:amount).to_f
    payments_count = gp_scope.count

    # Caja General (Movimientos directos en efectivo)
    cash_deposits = company.cash_adjustments.inflows.approved.where(date: start_date..end_date).sum(:amount).to_f
    cash_withdrawals = company.cash_adjustments.outflows.approved.where(date: start_date..end_date).sum(:amount).to_f

    # Nómina a músicos / personal
    ep_scope = company.employee_payments.approved
                      .where.not(funding_source: 'external_capital')
                      .where(date_paid: start_date..end_date)
    payroll_paid = ep_scope.sum(:amount).to_f
    payroll_count = ep_scope.count

    # Taller / Reparaciones iniciadas en el mes
    m_scope = MaintenanceRecord.joins(:item)
                               .where(items: { company_id: company.id })
                               .where(started_at: start_date..end_date)
    maintenance_cost = m_scope.sum(:cost).to_f

    # Totales
    total_inflow = (total_collected + cash_deposits).round(2)
    total_outflow = (cash_withdrawals + payroll_paid + maintenance_cost).round(2)
    net_cashflow = (total_inflow - total_outflow).round(2)

    {
      gigs_count: gigs_count,
      gigs_amount: gigs_amount.round(2),
      gigs_completed: gigs_completed,
      total_collected: total_collected.round(2),
      payments_count: payments_count,
      cash_deposits: cash_deposits.round(2),
      cash_withdrawals: cash_withdrawals.round(2),
      payroll_paid: payroll_paid.round(2),
      payroll_count: payroll_count,
      maintenance_cost: maintenance_cost.round(2),
      total_inflow: total_inflow,
      total_outflow: total_outflow,
      net_cashflow: net_cashflow
    }
  end

  def tool_get_company_area_overview(args)
    area = args['area'].to_s.strip.downcase

    parts = []

    # Metas de reinversión / ahorro
    if %w[all goals ''].include?(area)
      goals = company.reinvestment_goals.where(status: 'active').order(priority: :asc)
      if goals.any?
        goal_lines = goals.map do |g|
          pct = g.target_amount.to_f.positive? ? ((g.saved_amount.to_f / g.target_amount.to_f) * 100).round(1) : 0
          "• 🎯 **#{g.title}**: Ahorrado $#{sprintf('%.2f', g.saved_amount)} de $#{sprintf('%.2f', g.target_amount)} USD (#{pct}%)"
        end
        parts << "🎯 **Metas de Reinversión y Ahorro:**\n#{goal_lines.join("\n")}"
      end
    end

    # Lista de compras de equipo
    if %w[all shopping ''].include?(area)
      shopping = company.shopping_items.where(status: :pending).by_priority.limit(8)
      if shopping.any?
        shop_lines = shopping.map do |s|
          "• 🛒 **#{s.name}** (x#{s.quantity}): ~$#{sprintf('%.2f', s.total_price)} USD [Prioridad: #{s.priority.upcase}]"
        end
        parts << "🛒 **Lista de Compras de Equipos (Pendientes):**\n#{shop_lines.join("\n")}"
      end
    end

    # Presupuestos / Cotizaciones a clientes
    if %w[all quotes ''].include?(area)
      quotes = company.client_quotes.recent_first.limit(5)
      if quotes.any?
        quote_lines = quotes.map do |q|
          "• 📋 **#{q.display_client_name}**: $#{sprintf('%.2f', q.amount)} USD (#{q.package_display_title}) | Estado: #{q.status_label}"
        end
        parts << "📋 **Presupuestos y Cotizaciones Recientes:**\n#{quote_lines.join("\n")}"
      end
    end

    summary = parts.any? ? parts.join("\n\n") : "Todas las áreas consultadas se encuentran al día."

    {
      success: true,
      message: summary,
      card: {
        type: 'area_overview',
        title: "🏢 Vista General de la Empresa",
        amount: "#{company.reinvestment_goals.where(status: 'active').count} Metas Activas",
        details: "#{company.shopping_items.where(status: :pending).count} Compras pendientes • #{company.client_quotes.count} Cotizaciones",
        url: "/reinvestment_goals"
      }
    }
  end

  def parse_month_string(str, default_date)
    return default_date if str.blank? || str.downcase == 'current' || str.downcase == 'este mes'
    return default_date.prev_month if str.downcase == 'previous' || str.downcase == 'mes anterior'

    clean = str.to_s.strip.downcase

    # Formato numérico YYYY-MM
    if clean =~ /^(\d{4})-(\d{1,2})$/
      return Date.new($1.to_i, $2.to_i, 1) rescue default_date
    end

    # Meses en español
    months_es = {
      'enero' => 1, 'febrero' => 2, 'marzo' => 3, 'abril' => 4,
      'mayo' => 5, 'junio' => 6, 'julio' => 7, 'agosto' => 8,
      'septiembre' => 9, 'octubre' => 10, 'noviembre' => 11, 'diciembre' => 12
    }

    months_es.each do |m_name, m_num|
      if clean.include?(m_name)
        year_match = clean.scan(/\b(20\d\d)\b/).flatten.first
        year = year_match.present? ? year_match.to_i : default_date.year
        return Date.new(year, m_num, 1) rescue default_date
      end
    end

    Date.parse(str).beginning_of_month rescue default_date
  end

  def month_label_es(date)
    months = %w[Enero Febrero Marzo Abril Mayo Junio Julio Agosto Septiembre Octubre Noviembre Diciembre]
    "#{months[date.month - 1]} #{date.year}"
  end

  def calc_delta(curr, prev)
    c = curr.to_f
    p = prev.to_f
    return 0.0 if p.zero? && c.zero?
    return 100.0 if p.zero? && c > 0
    return -100.0 if c.zero? && p > 0
    (((c - p) / p.abs) * 100).round(1)
  end

  def format_delta(delta)
    if delta > 0
      "+#{delta}% ↗️"
    elsif delta < 0
      "#{delta}% ↘️"
    else
      "0.0% ➡️"
    end
  end

  def generate_report_insight(target_m, comp_m, delta_revenue, delta_net)
    insights = []
    if delta_revenue > 0
      insights << "Las cobranzas de shows crecieron un #{delta_revenue}% respecto al mes anterior."
    elsif delta_revenue < 0
      insights << "Las cobranzas de shows disminuyeron un #{delta_revenue.abs}% frente al mes previo."
    else
      insights << "Las cobranzas se mantuvieron estables respecto al mes previo."
    end

    if target_m[:net_cashflow] > comp_m[:net_cashflow]
      insights << "El flujo neto de caja mejoró en $#{sprintf('%.2f', target_m[:net_cashflow] - comp_m[:net_cashflow])} USD."
    elsif target_m[:net_cashflow] < comp_m[:net_cashflow]
      insights << "El margen neto de caja se redujo en $#{sprintf('%.2f', comp_m[:net_cashflow] - target_m[:net_cashflow])} USD."
    end

    if target_m[:maintenance_cost].positive?
      insights << "Se registraron $#{sprintf('%.2f', target_m[:maintenance_cost])} USD en reparaciones de taller."
    end

    insights.join(" ")
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
