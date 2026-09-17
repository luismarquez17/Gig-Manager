# frozen_string_literal: true

class ClientQuote < ApplicationRecord
  include TenantScoped

  belongs_to :client, optional: true
  belongs_to :gig, optional: true
  belongs_to :preset_budget, optional: true

  enum status: {
    pending: 'pending',
    accepted: 'accepted',
    converted: 'converted'
  }

  validates :client_name, :client_phone, presence: true, if: -> { accepted? || converted? }

  before_validation :generate_public_token, on: :create
  before_validation :set_default_status, on: :create
  before_save :sync_or_create_client!, if: -> { company.present? && (client_name.present? || client_phone.present?) }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :convertible, -> { where(status: [:pending, :accepted]) }

  def display_client_name
    client_name.presence || "Enlace Abierto ##{id}"
  end

  def package_display_title
    package_name.presence || preset_budget&.title || "Personalizado"
  end

  def notify_leaders_of_acceptance!
    return unless company_id.present?

    date_str = event_date ? event_date.strftime("%d/%m/%Y") : "Fecha por definir"
    loc_str = event_location.presence || "Lugar por confirmar"
    pkg_str = package_name.presence || preset_budget&.title
    pkg_info = pkg_str.present? ? " [Paquete: #{pkg_str}]" : ""
    adv_info = advance_amount.to_f > 0 ? " (Adelanto: $#{advance_amount} #{currency})" : ""

    AppNotification.create(
      company: company,
      target_area: 'leaders',
      notification_type: 'gig_alert',
      title: "📋 Presupuesto Recibido de Cliente",
      message: "#{display_client_name} ha completado su cotización para el show del #{date_str} en #{loc_str}#{pkg_info}. Total: $#{amount} #{currency}#{adv_info}.",
      action_url: "/gigs/new?quote_id=#{id}"
    ) rescue nil
  end

  def status_label
    case status
    when 'pending'
      client_name.present? ? 'Pendiente de Cliente' : 'Enlace Abierto (Sin Asignar)'
    when 'accepted'
      'Confirmado por Cliente (Listo para Gig)'
    when 'converted'
      'Convertido en Evento (Gig)'
    else
      status.humanize
    end
  end

  def status_badge_style
    case status
    when 'pending'
      client_name.present? ? 'background: #fef3c7; color: #b45309;' : 'background: #f1f5f9; color: #475569;'
    when 'accepted'
      'background: #dcfce7; color: #15803d;'
    when 'converted'
      'background: #e0e7ff; color: #4338ca;'
    else
      'background: #f3f4f6; color: #374151;'
    end
  end

  def sync_or_create_client!
    return unless company.present?
    return if client_name.blank? && client_phone.blank?

    # Si ya tiene un client_id asignado pero el nombre del cliente no coincide con client_name
    if client.present? && client_name.present? && client.name.to_s.strip.downcase != client_name.to_s.strip.downcase
      self.client_id = nil
    end

    return if client_id.present?

    matched_client = Client.find_or_create_for_gig(
      company: company,
      name: client_name,
      phone: client_phone,
      email: client_email
    )
    self.client_id = matched_client.id if matched_client.present?
  end

  def generate_public_token
    self.public_token ||= SecureRandom.hex(12)
  end

  def set_default_status
    self.status ||= 'pending'
  end
end
