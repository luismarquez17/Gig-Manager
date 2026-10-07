# frozen_string_literal: true

class GigPayment < ApplicationRecord
  include FinancialAuditable

  STATUSES = %w[approved pending_approval rejected voided].freeze

  belongs_to :gig
  belongs_to :approved_by, class_name: 'User', optional: true
  belongs_to :voided_by, class_name: 'User', optional: true
  has_one_attached :receipt_image

  CATEGORIES = %w[reinvest waste other].freeze

  PAYMENT_METHODS = {
    'cash'          => { label: 'Efectivo en Mano', emoji: '💵', bg: '#dcfce7', color: '#166534' },
    'zelle'         => { label: 'Zelle', emoji: '⚡', bg: '#ede9fe', color: '#5b21b6' },
    'bank_transfer' => { label: 'Transferencia Bancaria', emoji: '🏦', bg: '#dbeafe', color: '#1e40af' },
    'card_stripe'   => { label: 'Tarjeta / Stripe', emoji: '💳', bg: '#fef3c7', color: '#92400e' },
    'mobile_pay'    => { label: 'Pago Móvil', emoji: '📱', bg: '#ffedd5', color: '#9a3412' },
    'check'         => { label: 'Cheque', emoji: '🧾', bg: '#f1f5f9', color: '#334155' },
    'other'         => { label: 'Otro Método', emoji: '💰', bg: '#f8fafc', color: '#475569' }
  }.freeze

  before_validation :ensure_currency
  before_validation :ensure_payment_method
  before_validation :ensure_default_status
  before_validation :ensure_receipt_number, if: :approved?
  before_save :sync_receipt_image_to_base64

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS.keys }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }, allow_blank: true
  validate :amount_cannot_exceed_agreed_amount

  scope :recent_first, -> { order(date_paid: :desc, created_at: :desc) }
  scope :approved, -> { where(status: 'approved') }
  scope :pending_approval, -> { where(status: 'pending_approval') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :voided, -> { where(status: 'voided') }
  scope :active_records, -> { where.not(status: 'voided') }
  scope :reported_by_clients, -> { where(reported_by_client: true) }

  def approved?
    status == 'approved'
  end

  def pending_approval?
    status == 'pending_approval'
  end

  def rejected?
    status == 'rejected'
  end

  def voided?
    status == 'voided'
  end

  def void!(reason, user = nil)
    self.status = 'voided'
    self.voided_at = Time.current
    self.void_reason = reason.presence || 'Anulación contable por el usuario'
    self.voided_by = user if user.present?
    self.audit_reason = "Anulación de cobro: #{self.void_reason}"
    save!
  end

  def status_label
    case status
    when 'approved'         then 'Confirmado'
    when 'pending_approval' then 'En Revisión'
    when 'rejected'         then 'Rechazado'
    when 'voided'           then 'Anulado'
    else status.to_s.humanize
    end
  end

  def status_badge_bg
    case status
    when 'approved'         then '#dcfce7'
    when 'pending_approval' then '#fef3c7'
    when 'rejected'         then '#fee2e2'
    when 'voided'           then '#fee2e2'
    else '#f1f5f9'
    end
  end

  def status_badge_color
    case status
    when 'approved'         then '#166534'
    when 'pending_approval' then '#92400e'
    when 'rejected'         then '#991b1b'
    when 'voided'           then '#991b1b'
    else '#475569'
    end
  end

  def status_emoji
    case status
    when 'approved'         then '✅'
    when 'pending_approval' then '⏳'
    when 'rejected'         then '❌'
    when 'voided'           then '🚫'
    else '📄'
    end
  end

  def whatsapp_receipt_text(receipt_url = nil)
    comp_name = gig&.company&.name.presence || "Gig Manager"
    c_name = gig&.client_display_name || "Estimado(a) Cliente"
    dt = date_paid ? date_paid.strftime('%d/%m/%Y') : Date.today.strftime('%d/%m/%Y')
    amt = sprintf('%.2f', amount.to_f)
    curr = currency.presence || 'USD'
    f_num = receipt_display_number
    pm_label = payment_method_label

    lines = [
      "🧾 *COMPROBANTE DE PAGO - #{comp_name.upcase}*",
      "─────────────────────────",
      "📄 *Folio:* #{f_num}",
      "👤 *Cliente:* #{c_name}",
      "📅 *Fecha de Pago:* #{dt}",
      "💵 *Monto Abonado:* $#{amt} #{curr}",
      "💳 *Método:* #{pm_label}",
      "─────────────────────────"
    ]

    if gig.present?
      rem = sprintf('%.2f', remaining_after_this_payment)
      lines << "📊 *Saldo Restante del Evento:* $#{rem} #{curr}"
      lines << "─────────────────────────"
    end

    if receipt_url.present?
      lines << "🔗 *Ver Recibo Digital Oficial:*"
      lines << receipt_url.to_s
    end

    lines.join("\n")
  end

  def payment_method_label
    PAYMENT_METHODS.dig(payment_method, :label) || payment_method&.humanize || 'Efectivo en Mano'
  end

  def payment_method_emoji
    PAYMENT_METHODS.dig(payment_method, :emoji) || '💵'
  end

  def payment_method_badge_bg
    PAYMENT_METHODS.dig(payment_method, :bg) || '#dcfce7'
  end

  def payment_method_badge_color
    PAYMENT_METHODS.dig(payment_method, :color) || '#166534'
  end

  def receipt_display_number
    receipt_number.presence || (approved? ? ensure_receipt_number : "REC-PENDIENTE")
  end

  # Soporte para vouchers / imágenes de comprobante
  def voucher_attached?
    receipt_image_base64.present? || (receipt_image.attached? && blob_exists?(receipt_image))
  end

  def voucher_url_or_data
    if receipt_image_base64.present?
      receipt_image_base64
    elsif receipt_image.attached? && blob_exists?(receipt_image)
      receipt_image
    else
      nil
    end
  end

  # Datos calculados para el comprobante oficial
  def previous_payments_sum
    return 0.0 unless gig
    gig.gig_payments.approved.where("created_at < ? OR (created_at = ? AND id < ?)", created_at || Time.current, created_at || Time.current, id || 0).sum(:amount).to_f
  end

  def remaining_after_this_payment
    return 0.0 unless gig
    total_after = previous_payments_sum + amount.to_f
    [gig.amount.to_f - total_after, 0.0].max
  end

  private

  def ensure_currency
    self.currency = 'USD' if currency.blank? || currency != 'USD'
  end

  METHOD_ALIASES = {
    'pago_movil'    => 'mobile_pay',
    'pagomovil'     => 'mobile_pay',
    'transfer'      => 'bank_transfer',
    'transferencia' => 'bank_transfer',
    'efectivo'      => 'cash',
    'stripe'        => 'card_stripe',
    'tarjeta'       => 'card_stripe',
    'card'          => 'card_stripe'
  }.freeze

  def ensure_payment_method
    pm = payment_method.to_s.strip.downcase
    pm = METHOD_ALIASES[pm] || pm
    self.payment_method = PAYMENT_METHODS.key?(pm) ? pm : (pm.present? ? 'other' : 'cash')
  end

  def ensure_default_status
    self.status = 'approved' if status.blank?
  end

  def ensure_receipt_number
    return receipt_number if receipt_number.present?
    return unless approved?

    year = date_paid&.year || Time.current.year
    company_id = gig&.company_id || Current.company&.id

    scope = GigPayment.joins(:gig)
    scope = scope.where(gigs: { company_id: company_id }) if company_id
    scope = scope.where("receipt_number LIKE ?", "REC-#{year}-%")

    max_num = 0
    scope.pluck(:receipt_number).each do |rn|
      if rn =~ /REC-\d{4}-(\d+)/
        val = $1.to_i
        max_num = val if val > max_num
      end
    end

    seq = max_num + 1
    self.receipt_number = format("REC-%d-%05d", year, seq)
  end

  def sync_receipt_image_to_base64
    change = attachment_changes['receipt_image']
    if change.present?
      attachable = change.attachable
      data = nil
      content_type = nil

      if attachable.is_a?(Hash) && attachable[:io].respond_to?(:read)
        io = attachable[:io]
        data = io.read
        io.rewind if io.respond_to?(:rewind)
        content_type = attachable[:content_type]
      elsif attachable.respond_to?(:read)
        data = attachable.read
        attachable.rewind if attachable.respond_to?(:rewind)
        content_type = attachable.content_type if attachable.respond_to?(:content_type)
      elsif change.blob.present?
        data = (change.blob.download rescue nil)
        content_type = change.blob.content_type
      end

      if data.present?
        content_type = content_type.presence || 'image/jpeg'
        encoded = Base64.strict_encode64(data)
        self.receipt_image_base64 = "data:#{content_type};base64,#{encoded}"
      end
    elsif receipt_image_base64.blank? && receipt_image.attached? && receipt_image.blob.present?
      data = (receipt_image.blob.download rescue nil)
      if data.present?
        content_type = receipt_image.blob.content_type.presence || 'image/jpeg'
        encoded = Base64.strict_encode64(data)
        self.receipt_image_base64 = "data:#{content_type};base64,#{encoded}"
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[GigPayment#sync_receipt_image_to_base64] Error: #{e.message}")
  end

  def blob_exists?(attachment)
    return false unless attachment&.attached? && attachment.blob
    attachment.blob.service.exist?(attachment.blob.key)
  rescue StandardError
    false
  end

  def amount_cannot_exceed_agreed_amount
    return unless gig && amount.present?

    # Solo validamos contra los aprobados + este pago si está siendo aprobado
    other_approved_total = gig.gig_payments.approved.where.not(id: id).sum(:amount).to_f
    if (other_approved_total + amount.to_f) > gig.amount.to_f && approved?
      errors.add(:amount, "no puede ser mayor al monto acordado del show (#{gig.amount})")
    end
  end
end
