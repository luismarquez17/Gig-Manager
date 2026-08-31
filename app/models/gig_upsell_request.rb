class GigUpsellRequest < ApplicationRecord
  belongs_to :gig
  belongs_to :company, optional: true

  STATUSES = %w[pending approved rejected].freeze

  validates :upsell_key, presence: true
  validates :title, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, presence: true, inclusion: { in: STATUSES }

  before_validation :set_company_from_gig, if: -> { gig.present? && company_id.blank? }
  before_create :set_requested_at, if: -> { requested_at.blank? }

  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :ordered, -> { order(created_at: :desc) }

  def pending?
    status == 'pending'
  end

  def approved?
    status == 'approved'
  end

  def rejected?
    status == 'rejected'
  end

  def approve!
    return true if approved?

    transaction do
      update!(
        status: 'approved',
        processed_at: Time.current
      )

      # Actualiza el monto del show automáticamente
      gig.amount = gig.amount.to_f + price.to_f

      # Si es hora extra, suma 1 hora al horario final si está configurado
      is_extra_time = upsell_key == 'extra_time' || upsell_key.to_s.include?('time') || upsell_key.to_s.include?('hora') || title.to_s.downcase.include?('hora')
      if is_extra_time && gig.end_time.present?
        gig.end_time = gig.end_time + 1.hour
      end

      # Registra la nota en los detalles del contrato
      timestamp = Time.current.strftime("%d/%m/%Y %I:%M %p")
      price_formatted = sprintf("%.2f", price.to_f)
      curr = currency.presence || gig.currency.presence || 'USD'
      note = "Adicional añadido (#{timestamp}): #{title} (+$#{price_formatted} #{curr})"
      gig.details = gig.details.present? ? "#{gig.details}\n• #{note}" : "• #{note}"

      gig.save!
    end
    true
  end

  def reject!
    return true if rejected?

    update!(
      status: 'rejected',
      processed_at: Time.current
    )
  end

  private

  def set_company_from_gig
    self.company_id = gig&.company_id
  end

  def set_requested_at
    self.requested_at = Time.current
  end
end
