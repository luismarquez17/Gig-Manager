class Gig < ApplicationRecord
  include TenantScoped

  belongs_to :client, optional: true
  has_many :gig_items, dependent: :destroy
  has_many :items, through: :gig_items
  has_many :staff_assignments, dependent: :destroy
  has_many :staff_members, through: :staff_assignments, source: :user
  has_many :gig_payments, dependent: :destroy
  has_many :employee_payments, dependent: :nullify
  has_many :fund_allocations, dependent: :destroy
  has_many :gig_timeline_items, dependent: :destroy
  has_many :gig_upsell_requests, dependent: :destroy
  has_many :pending_upsell_requests, -> { where(status: 'pending') }, class_name: 'GigUpsellRequest'
  has_many :client_quotes, dependent: :nullify
  
  validates :amount, presence: true
  validates :client_email, presence: true, if: -> { client_id.blank? }
  validates :client_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_validation :copy_client_email
  before_validation { self.currency = 'USD' if currency.blank? || currency != 'USD' }
  before_create :generate_portal_token
  after_save :refresh_client_priority
  after_destroy :refresh_client_priority

  # Scopes de filtrado por asignación de fondos
  scope :with_unallocated_funds, -> {
    where(
      "(SELECT COALESCE(SUM(amount), 0) FROM gig_payments WHERE gig_payments.gig_id = gigs.id) > 0 AND " \
      "(SELECT COALESCE(SUM(amount), 0) FROM gig_payments WHERE gig_payments.gig_id = gigs.id) > " \
      "(SELECT COALESCE(SUM(amount), 0) FROM fund_allocations WHERE fund_allocations.gig_id = gigs.id)"
    )
  }

  scope :without_any_fund_allocations, -> {
    where(
      "(SELECT COALESCE(SUM(amount), 0) FROM gig_payments WHERE gig_payments.gig_id = gigs.id) > 0 AND " \
      "NOT EXISTS (SELECT 1 FROM fund_allocations WHERE fund_allocations.gig_id = gigs.id)"
    )
  }

  scope :fully_allocated_funds, -> {
    where(
      "(SELECT COALESCE(SUM(amount), 0) FROM gig_payments WHERE gig_payments.gig_id = gigs.id) > 0 AND " \
      "(SELECT COALESCE(SUM(amount), 0) FROM gig_payments WHERE gig_payments.gig_id = gigs.id) <= " \
      "(SELECT COALESCE(SUM(amount), 0) FROM fund_allocations WHERE fund_allocations.gig_id = gigs.id)"
    )
  }

  # Financial helpers
  def client_display_name
    client&.name.presence || client_email.presence || "Cliente (Sin Nombre)"
  end

  def total_received
    if gig_payments.loaded?
      gig_payments.select(&:approved?).sum { |p| p.amount.to_f }
    else
      gig_payments.approved.sum(:amount).to_f
    end
  end

  def pending_client_payments
    gig_payments.pending_approval.order(created_at: :desc)
  end

  def total_employee_payouts
    employee_payments.sum(:amount)
  end

  def total_allocated
    fund_allocations.sum(:amount)
  end

  def payroll_allocations
    fund_allocations.where(fund_type: 'payroll')
  end

  def total_payroll_remaining
    payroll_allocations.sum { |allocation| allocation.remaining.to_f }
  end

  def remaining_amount
    [amount.to_f - total_received, 0.0].max
  end

  def payment_percentage
    return 0.0 if amount.to_f <= 0
    [((total_received / amount.to_f) * 100.0).round(1), 100.0].min
  end

  def paid_in_full?
    amount.to_f > 0 && total_received >= amount.to_f
  end

  def whatsapp_payment_statement_text(portal_url = nil)
    status_text = if paid_in_full?
                    "✅ SALDADO EN SU TOTALIDAD"
                  elsif total_received.positive?
                    "⏳ ABONADO PARCIALMENTE (#{payment_percentage}%)"
                  else
                    "⚠️ PENDIENTE POR ABONAR"
                  end

    comp_name = company&.name.presence || "Gig Manager"
    c_name = client_display_name.to_s.encode('UTF-8', invalid: :replace, undef: :replace)
    loc = (location.presence || 'Por definir').to_s.encode('UTF-8', invalid: :replace, undef: :replace)
    dt = date ? date.strftime('%d/%m/%Y') : 'Por definir'

    lines = [
      "📋 *ESTADO DE CUENTA - #{comp_name.to_s.upcase}*",
      "─────────────────────────",
      "👤 *Cliente:* #{c_name}",
      "📅 *Fecha:* #{dt}",
      "📍 *Ubicación:* #{loc}",
      "─────────────────────────",
      "💰 *Total Acordado:* $#{sprintf('%.2f', amount.to_f)} #{currency || 'USD'}",
      "💵 *Total Abonado:* $#{sprintf('%.2f', total_received)} #{currency || 'USD'}",
      "💳 *Saldo Pendiente:* $#{sprintf('%.2f', remaining_amount)} #{currency || 'USD'}",
      "📊 *Estado:* #{status_text}",
      "─────────────────────────"
    ]

    payments = gig_payments.order(date_paid: :asc)
    if payments.any?
      lines << "🧾 *Abonos Registrados:*"
      payments.each_with_index do |p, i|
        p_date = p.date_paid ? p.date_paid.strftime('%d/%m/%Y') : '---'
        p_cat = (p.category.presence || 'Abono').to_s.encode('UTF-8', invalid: :replace, undef: :replace)
        lines << "  • #{p_date} - $#{sprintf('%.2f', p.amount.to_f)} #{p.currency} (#{p_cat})"
      end
      lines << "─────────────────────────"
    end

    if portal_url.present?
      lines << "🔗 *Portal Privado y Recibos Digitales:*"
      lines << portal_url.to_s
    end

    lines.map { |l| l.encode('UTF-8', invalid: :replace, undef: :replace) }.join("\n")
  end

  def whatsapp_client_welcome_text(portal_url = nil)
    comp_name = company&.name.presence || "Gig Manager"
    c_name = client_display_name
    dt = date ? date.strftime('%d/%m/%Y') : 'Por definir'
    loc = location.presence || 'Por definir'
    time_str = formatted_time_range.presence || 'Horario por coordinar'

    lines = [
      "✨ *¡Hola #{c_name}! Te saluda el equipo de #{comp_name}* ✨",
      "",
      "¡Estamos muy felices de acompañarte en tu próximo evento! 🎉",
      "Hemos preparado tu *Portal Privado de Cliente* donde podrás consultar todos los detalles en tiempo real:",
      "",
      "📅 *Fecha:* #{dt}",
      "🕐 *Horario Acordado:* #{time_str}",
      "📍 *Lugar:* #{loc}",
      ""
    ]

    if portal_url.present?
      lines << "🔗 *Accede a tu Portal Exclusivo aquí:*"
      lines << portal_url.to_s
      lines << ""
      features_desc = []
      features_desc << "el cronograma del día" if company.nil? || company.module_enabled?(:gigs)
      features_desc << "validar tus abonos y recibos" if company.nil? || company.module_enabled?(:finances)
      features_desc << "solicitar adicionales" if company.nil? || company.module_enabled?(:clients_crm)
      if features_desc.any?
        lines << "Desde allí podrás revisar #{features_desc.to_sentence} para tu evento."
      end
    end

    lines << ""
    lines << "Cualquier consulta estamos a tu total disposición. ¡Será un evento inolvidable! 🙌"
    lines.join("\n")
  end

  def whatsapp_client_schedule_text(portal_url = nil)
    comp_name = company&.name.presence || "Gig Manager"
    c_name = client_display_name
    dt = date ? date.strftime('%d/%m/%Y') : 'Por definir'
    loc = location.presence || 'Por definir'

    lines = [
      "⏰ *CRONOGRAMA Y PAUTA TÉCNICA - #{comp_name.to_s.upcase}*",
      "─────────────────────────",
      "👤 *Cliente:* #{c_name}",
      "📅 *Fecha:* #{dt}",
      "📍 *Lugar:* #{loc}",
      "─────────────────────────"
    ]

    timeline_items = gig_timeline_items.order(position: :asc, time: :asc)
    if timeline_items.any?
      lines << "⏱️ *Itinerario del Evento:*"
      timeline_items.each do |item|
        t_str = item.time.presence || "--:--"
        lines << "  • *#{t_str}* - #{item.title}"
        lines << "    _#{item.description}_" if item.description.present?
      end
      lines << "─────────────────────────"
    elsif start_time.present? && end_time.present?
      lines << "⏱️ *Horario del Evento:* #{formatted_time_range}"
      lines << "─────────────────────────"
    end

    if portal_url.present?
      lines << "📱 *Portal en Vivo:* #{portal_url}"
    end

    lines.join("\n")
  end

  def whatsapp_staff_call_sheet_text(staff_user = nil, stage_url = nil)
    comp_name = company&.name.presence || "Gig Manager"
    dt = date ? date.strftime('%d/%m/%Y') : 'Por definir'
    loc = location.presence || 'Por definir'
    c_name = client_display_name
    is_venue = company&.business_type == 'venue_hall'

    assignment = staff_assignments.find_by(user_id: staff_user&.id) if staff_user.present?

    sheet_title = is_venue ? "🏛️ *PAUTA DE PERSONAL - #{comp_name.to_s.upcase}*" : "🎸 *PAUTA DE CONVOCATORIA (CALL SHEET) - #{comp_name.to_s.upcase}*"

    lines = [
      sheet_title,
      "─────────────────────────",
      "📅 *Fecha:* #{dt}",
      "👤 *Evento:* #{c_name}",
      "📍 *Ubicación:* #{loc}",
      "─────────────────────────"
    ]

    if start_time.present?
      arr_time = (start_time - 90.minutes).strftime("%I:%M %p")
      lines << "🚪 *Convocatoria / Montaje:* #{arr_time}"
      lines << "🎤 *Inicio:* #{start_time.strftime('%I:%M %p')}"
      lines << "🏁 *Finalización:* #{end_time ? end_time.strftime('%I:%M %p') : 'Por definir'}"
    else
      lines << "🕐 *Horario:* Por coordinar en el grupo"
    end

    # Dress code si existe en notas
    if details.to_s.match?(/negro|black/i)
      lines << "👔 *Código de Vestimenta:* Total Black (Todo Negro)"
    elsif details.to_s.match?(/formal|traje|etiqueta/i)
      lines << "👔 *Código de Vestimenta:* Traje Formal"
    elsif details.to_s.match?(/casual|semiformal/i)
      lines << "👔 *Código de Vestimenta:* Casual Elegante"
    elsif details.to_s.match?(/blanco|white/i)
      lines << "👔 *Código de Vestimenta:* Blanco / Claro"
    end

    if assignment.present? && assignment.agreed_amount.to_f > 0
      lines << "💰 *Pago Acordado:* $#{sprintf('%.2f', assignment.agreed_amount.to_f)} #{currency || 'USD'}"
    end

    if (company.nil? || company.module_enabled?(:songs_repertoire)) && has_music_notes?
      lines << "─────────────────────────"
      lines << "🎵 *Protocolo / Momentos Clave:*"
      lines << music_notes.to_s.lines.first(3).map { |l| "  • #{l.strip}" }.join("\n")
    end

    if stage_url.present?
      lines << "─────────────────────────"
      lines << "⚡ *Modo Escenario en Vivo (Cronograma & Detalles):*"
      lines << stage_url.to_s
    end

    lines.join("\n")
  end

  # --- MÉTRICAS DE RENTABILIDAD Y NÓMINA DEL SHOW ---
  def total_payroll_agreed
    if staff_assignments.loaded?
      staff_assignments.sum { |sa| sa.agreed_amount.to_f }
    else
      staff_assignments.sum(:agreed_amount).to_f
    end
  end

  def total_payroll_paid
    if staff_assignments.loaded?
      staff_assignments.sum { |sa| sa.total_paid }.round(2)
    else
      staff_assignments.includes(:user).sum { |sa| sa.total_paid }.round(2)
    end
  end

  def pending_payroll_amount
    [total_payroll_agreed - total_payroll_paid, 0.0].max.round(2)
  end

  # Ganancia Neta Proyectada (Monto acordado con cliente - Nómina total acordada)
  def projected_net_profit
    (amount.to_f - total_payroll_agreed).round(2)
  end

  # Margen de Ganancia Proyectado (%)
  def projected_profit_margin
    return 0.0 if amount.to_f <= 0
    ((projected_net_profit / amount.to_f) * 100.0).round(1)
  end

  # Ganancia Neta Real en Mano (Cobrado a la fecha - Nómina pagada a la fecha)
  def actual_cash_profit
    (total_received - total_payroll_paid).round(2)
  end

  def profit_health_status
    m = projected_profit_margin
    if m >= 40.0
      :excellent
    elsif m >= 20.0
      :healthy
    elsif m >= 0.0
      :tight
    else
      :loss
    end
  end

  def event_duration
    return nil unless start_time.present? && end_time.present?
    diff_seconds = end_time - start_time
    diff_seconds += 86400 if diff_seconds < 0 # Handle crossing midnight
    (diff_seconds / 3600.0).round(1)
  end

  def formatted_time_range
    return nil unless start_time.present? && end_time.present?
    start_str = start_time.strftime("%I:%M %p")
    end_str = end_time.strftime("%I:%M %p")
    duration = event_duration
    duration_str = duration == duration.to_i ? "#{duration.to_i} horas" : "#{duration} horas"
    "#{start_str} → #{end_str} · #{duration_str}"
  end

  def payment_status
    if total_received.to_f.zero?
      :unpaid
    elsif remaining_amount.positive?
      :partial
    else
      :paid
    end
  end

  def payment_status_label
    case payment_status
    when :paid
      'Pagado'
    when :partial
      'Parcial'
    else
      'Pendiente'
    end
  end

  def payment_status_badge_class
    case payment_status
    when :paid
      'bg-success'
    when :partial
      'bg-warning'
    else
      'bg-danger'
    end
  end

  def remaining_balance
    (total_received || 0) - (total_allocated || 0)
  end

  def portal_token
    token = read_attribute(:portal_token)
    if token.blank?
      token = SecureRandom.hex(16)
      update_columns(portal_token: token) if persisted?
    end
    token
  end

  def available_upsells
    return [] if company.present? && !company.module_enabled?(:clients_crm)

    upsells = []
    
    details_text = details.to_s.downcase
    item_names = items.pluck(:name, :category).flatten.compact.map(&:downcase)

    has_smoke = details_text.include?('humo') || details_text.include?('smoke') || details_text.include?('fog') || details_text.include?('neblina') ||
                item_names.any? { |n| n.include?('humo') || n.include?('smoke') || n.include?('fog') }
    has_spark = details_text.include?('spark') || details_text.include?('chispa') || details_text.include?('fuego fr') ||
                item_names.any? { |n| n.include?('spark') || n.include?('chispa') }
    has_sub = details_text.include?('subwoofer') || details_text.include?('bajo') ||
              item_names.any? { |n| n.include?('subwoofer') || n.include?('bajo') }
    has_extra_time = details_text.include?('hora extra') || details_text.include?('horas extra') || details_text.include?('tiempo extra') || details_text.include?('extra time')

    standard_catalog = if company.present?
      company.standard_upsells.all_with_defaults.select(&:active)
    else
      StandardUpsell.all_with_defaults.select(&:active)
    end
    custom_map = custom_upsells || {}

    # Obtenemos las solicitudes de adicionales de este evento para saber el estado
    requests_by_key = gig_upsell_requests.order(created_at: :desc).group_by(&:upsell_key)

    standard_catalog.each do |std|
      key_str = std.key.to_s
      custom_data = custom_map[key_str] || custom_map[std.id.to_s] || {}

      # Si está desactivado para este toque en particular, omitir
      next if custom_data['disabled'] == '1' || custom_data['disabled'] == true

      is_excluded = case key_str.downcase
                    when 'smoke_machine' then has_smoke
                    when 'sparkulars' then has_spark
                    when 'subwoofer' then has_sub
                    when 'extra_time' then has_extra_time
                    else false
                    end
      next if is_excluded

      title = custom_data['title'].presence || std.title
      emoji = custom_data['emoji'].presence || std.emoji || '🚀'
      price = custom_data['price'].present? ? custom_data['price'].to_f : std.price.to_f
      currency = custom_data['currency'].presence || std.currency || 'USD'
      description = custom_data['description'].presence || std.description || ''

      latest_request = requests_by_key[key_str]&.first
      request_status = latest_request&.status

      whatsapp_message = "Hola! Me gustaría añadir la opción #{title.downcase} por $#{price.to_i} #{currency} adicionales a mi evento del día #{date&.strftime('%d/%m/%Y')}."

      upsells << {
        id: key_str.to_sym,
        key: key_str,
        title: title,
        emoji: emoji,
        price: price,
        currency: currency,
        description: description,
        whatsapp_message: whatsapp_message,
        request_status: request_status,
        request_id: latest_request&.id
      }
    end

    upsells
  end

  def has_music_notes?
    music_notes.present? && music_notes.strip.present?
  end

  def formatted_music_notes_lines
    return [] unless has_music_notes?
    music_notes.lines.map(&:strip).reject(&:blank?)
  end

  private

  def copy_client_email
    if client_id.present? && client_email.blank?
      self.client_email = client&.email
    end
  end

  def refresh_client_priority
    # Usamos &. para evitar errores si por alguna razón el cliente es nil
    client&.update_priority!
  end

  def generate_portal_token
    self.portal_token ||= SecureRandom.hex(16)
  end
end