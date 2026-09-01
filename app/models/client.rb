class Client < ApplicationRecord
  include TenantScoped

  has_many :gigs, dependent: :destroy
  has_many :client_quotes, dependent: :nullify
  
  # Permite editar los datos del show desde el formulario del cliente
  accepts_nested_attributes_for :gigs

  # Validaciones básicas para evitar errores en la base de datos
  validates :name, :phone, presence: true
  validate :validate_phone_format

  def validate_phone_format
    return if phone.blank?
    return if phone == "0000000000" # Bypass para clientes creados automáticamente
    
    # Limpiamos todo lo que no sea dígito
    digits = phone.gsub(/\D/, '')
    
    if digits.length < 10 || digits.length > 15
      errors.add(:phone, "debe tener entre 10 y 15 dígitos numéricos")
    end
    
    if phone =~ /[a-zA-Z]/
      errors.add(:phone, "no puede contener letras")
    end
  end

  # Definimos los niveles de prioridad
  enum priority: { baja: 0, media: 1, alta: 2 }

  # Asegura que todo cliente nuevo empiece con prioridad baja
  after_initialize :set_default_priority, if: :new_record?

  # 1. Presupuesto Total (Usado para el ordenamiento del Index)
  def total_spent
    gigs.sum(:amount).to_f
  end

  # 2. Método para calcular el presupuesto promedio de los últimos 3 shows
  def average_budget
    sorted_gigs = if gigs.loaded?
                    gigs.sort_by { |g| g.date || Date.new(0) }.reverse.take(3)
                  else
                    gigs.order(date: :desc).limit(3).to_a
                  end

    return 0.0 if sorted_gigs.empty?
    
    amounts = sorted_gigs.map { |g| g.amount.to_f }
    amounts.sum / amounts.size
  end

  # 3. Lógica de prioridad automática
  def update_priority!
    avg = average_budget
    
    new_priority = if avg >= 200
                     :alta
                   elsif avg >= 100
                     :media
                   else
                     :baja
                   end
    
    # Usamos update_columns para evitar disparar callbacks infinitos si los tuvieras
    update_columns(priority: Client.priorities[new_priority])
  end

  # 4. Lógica inteligente de ubicación
  def resumen_ubicacion
    locations = gigs.where.not(location: [nil, ""]).pluck(:location)
    return "Sin registros de shows" if locations.empty?
    
    # Contamos frecuencia de sitios
    conteo = locations.tally
    sitio_frecuente, max_repeticiones = conteo.max_by { |_, count| count }

    if max_repeticiones > 1
      "Mayormente en #{sitio_frecuente}"
    else
      "Último show en: #{locations.last}"
    end
  end

  def formatted_phone_for_whatsapp
    return nil if phone.blank?
    
    # Limpiamos todo lo que no sea dígito
    digits = phone.gsub(/\D/, '')
    
    # Formato venezolano: si empieza con 0 y tiene 11 dígitos (ej: 04141234567 -> 584141234567)
    if digits.start_with?('0') && digits.length == 11
      "58#{digits[1..]}"
    # Si tiene 10 dígitos y empieza con 4 (ej: 4141234567 -> 584141234567)
    elsif digits.length == 10 && digits.start_with?('4')
      "58#{digits}"
    else
      digits
    end
  end

  def whatsapp_url(text: nil)
    number = formatted_phone_for_whatsapp
    return nil if number.blank?
    
    url = "https://wa.me/#{number}"
    url += "?text=#{ERB::Util.url_encode(text)}" if text.present?
    url
  end

  # --- Métodos de Control de Deuda y Saldos ---
  def total_debt
    gigs.to_a.sum { |g| [g.remaining_amount.to_f, 0.0].max }
  end

  def unpaid_gigs
    gigs.to_a.select { |g| g.remaining_amount.to_f > 0 }
  end

  def has_debt?
    total_debt > 0
  end

  def debt_whatsapp_url
    return nil unless has_debt? && formatted_phone_for_whatsapp.present?

    lines = ["Hola *#{name}*! 👋 Te escribimos para enviarte un cordial recordatorio sobre el saldo pendiente de tu(s) evento(s):\n"]
    unpaid_gigs.each do |gig|
      fecha_str = gig.date ? gig.date.strftime("%d/%m/%Y") : "Fecha no especificada"
      loc_str = gig.location.presence || "Evento"
      lines << "• *#{loc_str}* (#{fecha_str}): Monto Total $#{'%.2f' % gig.amount.to_f} | Pagado $#{'%.2f' % gig.total_received.to_f} | *Pendiente: $#{'%.2f' % gig.remaining_amount.to_f}*"
    end

    lines << "\n💰 *Deuda Total Pendiente: $#{'%.2f' % total_debt}*"
    lines << "\nPor favor nos confirmas cuando realices el pago o si necesitas los datos bancarios. ¡Muchas gracias por tu atención! 🚀"

    whatsapp_url(text: lines.join("\n"))
  end

  def self.find_or_create_for_gig(company:, email:, name: nil, phone: nil)
    return nil if email.blank? || company.nil?

    existing = company.clients.find_by(email: email)
    return existing if existing.present?

    client_name = name.presence || email.split('@').first.capitalize
    client_phone = phone.presence || "0000000000"

    company.clients.create(
      name: client_name,
      email: email,
      phone: client_phone
    )
  rescue StandardError
    nil
  end

  private

  def set_default_priority
    self.priority ||= :baja
  end
end