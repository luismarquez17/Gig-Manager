class Gig < ApplicationRecord
  belongs_to :client, optional: true
  has_many :gig_items, dependent: :destroy
  has_many :items, through: :gig_items
  has_many :staff_assignments, dependent: :destroy
  has_many :staff_members, through: :staff_assignments, source: :user
  has_many :gig_payments, dependent: :destroy
  has_many :employee_payments, dependent: :nullify
  has_many :fund_allocations, dependent: :destroy
  has_many :gig_timeline_items, dependent: :destroy
  
  validates :amount, presence: true
  validates :client_email, presence: true, if: -> { client_id.blank? }
  validates :client_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_validation :copy_client_email
  before_create :generate_portal_token
  after_save :refresh_client_priority
  after_destroy :refresh_client_priority

  # Financial helpers
  def total_received
    gig_payments.sum(:amount)
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
    amount.to_f - total_received.to_f
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
    upsells = []
    
    details_text = details.to_s.downcase
    item_names = items.pluck(:name, :category).flatten.compact.map(&:downcase)
    
    # 1. Máquina de Humo
    has_smoke = details_text.include?('humo') || details_text.include?('smoke') || details_text.include?('fog') || details_text.include?('neblina') ||
                item_names.any? { |n| n.include?('humo') || n.include?('smoke') || n.include?('fog') }
    unless has_smoke
      upsells << {
        id: :smoke_machine,
        title: 'Máquina de Humo',
        emoji: '💨',
        price: 40.0,
        currency: 'USD',
        description: 'Añade una atmósfera espectacular con nuestra máquina de humo profesional. Ideal para resaltar los efectos de las luces y el láser.',
        whatsapp_message: "Hola! Me gustaría añadir la máquina de humo por $40 USD adicionales a mi evento del día #{date&.strftime('%d/%m/%Y')}."
      }
    end

    # 2. Máquina de Sparkulas
    has_spark = details_text.include?('spark') || details_text.include?('chispa') || details_text.include?('fuego fr') ||
                item_names.any? { |n| n.include?('spark') || n.include?('chispa') }
    unless has_spark
      upsells << {
        id: :sparkulars,
        title: 'Máquina de Sparkulas',
        emoji: '✨',
        price: 30.0,
        currency: 'USD',
        description: 'Alquila una máquina de sparkulas (fuego frío) por 6 horas. Totalmente segura para interiores, perfecta para momentos cumbre del evento.',
        whatsapp_message: "Hola! Me gustaría añadir la máquina de sparkulas por $30 USD adicionales a mi evento del día #{date&.strftime('%d/%m/%Y')}."
      }
    end

    # 3. Subwoofer Premium 18"
    has_sub = details_text.include?('subwoofer') || details_text.include?('bajo') ||
              item_names.any? { |n| n.include?('subwoofer') || n.include?('bajo') }
    unless has_sub
      upsells << {
        id: :subwoofer,
        title: 'Subwoofer Premium 18"',
        emoji: '🔊',
        price: 25.0,
        currency: 'USD',
        description: 'Añade un subwoofer activo de 18 pulgadas para lograr unos bajos potentes y envolventes que harán vibrar a todos tus invitados.',
        whatsapp_message: "Hola! Me gustaría añadir el subwoofer premium de 18 pulgadas por $25 USD adicionales a mi evento del día #{date&.strftime('%d/%m/%Y')}."
      }
    end

    # 4. Horas Extra de Música
    has_extra_time = details_text.include?('hora extra') || details_text.include?('horas extra') || details_text.include?('tiempo extra') || details_text.include?('extra time')
    unless has_extra_time
      upsells << {
        id: :extra_time,
        title: 'Horas Extra de Música',
        emoji: '🎵',
        price: 40.0,
        currency: 'USD',
        description: 'Extiende la diversión del show 2 horas más con música continua en vivo para que la fiesta no pare.',
        whatsapp_message: "Hola! Me gustaría añadir 2 horas extra de música por $40 USD adicionales a mi evento del día #{date&.strftime('%d/%m/%Y')}."
      }
    end

    upsells
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