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
    read_attribute(:total_spent)&.to_f || gigs.sum(:amount).to_f
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

  def self.find_or_create_for_gig(company:, email: nil, name: nil, phone: nil)
    return nil if company.nil?
    return nil if email.blank? && name.blank? && phone.blank?

    name_clean = name.to_s.strip
    email_clean = email.to_s.strip.downcase
    phone_digits = phone.to_s.gsub(/\D/, '')

    existing = nil

    # 1. Si tenemos nombre especificado, buscar primero coincidencia de nombre exacto dentro de la empresa
    if name_clean.present?
      name_candidates = company.clients.where("LOWER(TRIM(name)) = ?", name_clean.downcase)
      if name_candidates.any?
        # Si hay varios con el mismo nombre, preferir el que coincida en teléfono o email
        if phone_digits.length >= 7
          existing = name_candidates.find { |c| c.phone.to_s.gsub(/\D/, '').include?(phone_digits) || phone_digits.include?(c.phone.to_s.gsub(/\D/, '')) }
        end
        if existing.nil? && email_clean.present?
          existing = name_candidates.find { |c| c.email.to_s.strip.downcase == email_clean }
        end
        existing ||= name_candidates.first
      end
    end

    # 2. Si no se encontró por nombre pero hay teléfono, buscar por teléfono SOLO si el nombre es compatible o no se dio nombre
    if existing.nil? && phone_digits.length >= 7
      phone_matches = company.clients.where.not(phone: [nil, '', '0000000000']).select do |c|
        c_digits = c.phone.to_s.gsub(/\D/, '')
        c_digits == phone_digits || (c_digits.length >= 10 && phone_digits.length >= 10 && (c_digits.end_with?(phone_digits[-7..]) || phone_digits.end_with?(c_digits[-7..])))
      end

      if phone_matches.any?
        if name_clean.blank?
          existing = phone_matches.first
        else
          # Solo vincular si el nombre del cliente existente coincide, es compatible o era genérico ("Cliente ...")
          existing = phone_matches.find do |c|
            c_name = c.name.to_s.strip.downcase
            c_name == name_clean.downcase ||
              c_name.include?(name_clean.downcase) ||
              name_clean.downcase.include?(c_name) ||
              c_name.start_with?("cliente")
          end
        end
      end
    end

    # 3. Si no se encontró, buscar por correo SOLO si el nombre es compatible o no se dio nombre
    if existing.nil? && email_clean.present?
      email_matches = company.clients.where.not(email: [nil, '']).where("LOWER(TRIM(email)) = ?", email_clean)
      if email_matches.any?
        if name_clean.blank?
          existing = email_matches.first
        else
          existing = email_matches.find do |c|
            c_name = c.name.to_s.strip.downcase
            c_name == name_clean.downcase ||
              c_name.include?(name_clean.downcase) ||
              name_clean.downcase.include?(c_name) ||
              c_name.start_with?("cliente")
          end
        end
      end
    end

    if existing.present?
      updates = {}
      updates[:email] = email if existing.email.blank? && email.present?
      updates[:phone] = phone if (existing.phone.blank? || existing.phone == "0000000000") && phone.present?
      # Si el cliente existente tenía nombre genérico como "Cliente 0414...", actualizar con el nombre real ingresado
      if name_clean.present? && (existing.name.blank? || existing.name.downcase.start_with?("cliente"))
        updates[:name] = name_clean
      end
      existing.update(updates) if updates.any?
      return existing
    end

    client_name = name_clean.presence || (email_clean.present? ? email_clean.split('@').first.capitalize : "Cliente #{phone}")
    client_phone = phone.presence || "0000000000"
    client_email = email.presence

    company.clients.create!(
      name: client_name,
      email: client_email,
      phone: client_phone
    )
  rescue StandardError => e
    Rails.logger.error("Error en Client.find_or_create_for_gig: #{e.message}")
    nil
  end

  private

  def set_default_priority
    self.priority ||= :baja
  end
end