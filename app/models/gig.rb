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
  has_many :gig_reviews, dependent: :destroy
  has_many :gig_upsell_requests, dependent: :destroy
  has_many :pending_upsell_requests, -> { where(status: 'pending') }, class_name: 'GigUpsellRequest'
  has_many :client_quotes, dependent: :nullify
  
  validates :amount, presence: true
  validates :client_email, presence: true, if: -> { client_id.blank? }
  validates :client_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_validation :copy_client_email
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
  def total_received
    if gig_payments.loaded?
      gig_payments.sum { |p| p.amount.to_f }
    else
      gig_payments.sum(:amount).to_f
    end
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

    has_smoke = details_text.include?('humo') || details_text.include?('smoke') || details_text.include?('fog') || details_text.include?('neblina') ||
                item_names.any? { |n| n.include?('humo') || n.include?('smoke') || n.include?('fog') }
    has_spark = details_text.include?('spark') || details_text.include?('chispa') || details_text.include?('fuego fr') ||
                item_names.any? { |n| n.include?('spark') || n.include?('chispa') }
    has_sub = details_text.include?('subwoofer') || details_text.include?('bajo') ||
              item_names.any? { |n| n.include?('subwoofer') || n.include?('bajo') }
    has_extra_time = details_text.include?('hora extra') || details_text.include?('horas extra') || details_text.include?('tiempo extra') || details_text.include?('extra time')

    standard_catalog = StandardUpsell.all_with_defaults.select(&:active)
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

  def average_review_rating
    approved = gig_reviews.approved
    return 0 if approved.empty?
    (approved.average(:rating) || 0).to_f.round(1)
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