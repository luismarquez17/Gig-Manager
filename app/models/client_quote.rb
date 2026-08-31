# frozen_string_literal: true

class ClientQuote < ApplicationRecord
  include TenantScoped

  belongs_to :client, optional: true
  belongs_to :gig, optional: true

  enum status: {
    pending: 'pending',
    accepted: 'accepted',
    converted: 'converted'
  }

  validates :client_name, :client_email, :client_phone, presence: true

  before_validation :generate_public_token, on: :create
  before_validation :set_default_status, on: :create

  scope :recent_first, -> { order(created_at: :desc) }
  scope :convertible, -> { where(status: [:pending, :accepted]) }

  def notify_leaders_of_acceptance!
    return unless company_id.present?

    date_str = event_date ? event_date.strftime("%d/%m/%Y") : "Fecha por definir"
    loc_str = event_location.presence || "Lugar por confirmar"

    AppNotification.create(
      company: company,
      target_area: 'leaders',
      notification_type: 'gig_alert',
      title: "📋 Presupuesto Aceptado por Cliente",
      message: "#{client_name} ha aceptado la propuesta para el show del #{date_str} en #{loc_str}. Presupuesto acordado: $#{amount} #{currency}.",
      action_url: "/gigs/new?quote_id=#{id}"
    ) rescue nil
  end

  def status_label
    case status
    when 'pending'   then 'Pendiente de Cliente'
    when 'accepted'  then 'Aceptado por Cliente (Listo para Gig)'
    when 'converted' then 'Convertido en Evento (Gig)'
    else status.humanize
    end
  end

  def status_badge_style
    case status
    when 'pending'   then 'background: #fef3c7; color: #b45309;'
    when 'accepted'  then 'background: #dcfce7; color: #15803d;'
    when 'converted' then 'background: #e0e7ff; color: #4338ca;'
    else 'background: #f3f4f6; color: #374151;'
    end
  end

  private

  def generate_public_token
    self.public_token ||= SecureRandom.hex(12)
  end

  def set_default_status
    self.status ||= 'pending'
  end
end
