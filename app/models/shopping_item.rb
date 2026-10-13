# frozen_string_literal: true

class ShoppingItem < ApplicationRecord
  include TenantScoped

  has_one_attached :image
  belongs_to :reinvestment_goal, optional: true

  enum priority: { low: 0, medium: 1, high: 2 }
  enum status: { pending: 0, purchased: 1 }

  before_validation :sync_pricing_defaults
  before_save :sync_image_to_base64
  after_commit :ensure_base64_persisted, on: [:create, :update]
  after_save :trigger_goal_check!
  after_destroy :trigger_goal_check!

  validates :name, presence: true
  validates :priority, presence: true
  validates :status, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: %w[USD] }, allow_blank: true

  CATEGORIES = [
    "Cables",
    "Micrófonos",
    "Iluminación",
    "Audio / Mezcla",
    "Instrumentos",
    "Estructuras / Tarimas",
    "Accesorios",
    "Transporte / Carga",
    "Energía / Corriente",
    "Herramientas",
    "Otros"
  ].freeze

  scope :by_priority, -> { order(priority: :desc, created_at: :desc) }
  scope :pending_first, -> { order(status: :asc, priority: :desc) }

  def total_price
    q = quantity.to_i > 0 ? quantity.to_i : 1
    if unit_price.to_f > 0
      (q * unit_price.to_f).round(2)
    else
      estimated_price.to_f.round(2)
    end
  end

  def effective_unit_price
    q = quantity.to_i > 0 ? quantity.to_i : 1
    if unit_price.to_f > 0
      unit_price.to_f.round(2)
    elsif estimated_price.to_f > 0
      (estimated_price.to_f / q).round(2)
    else
      0.0
    end
  end

  def image_attached?
    image_base64.present? || (image.attached? && blob_exists?(image))
  end

  def image_url_or_data
    if image_base64.present?
      image_base64
    elsif image.attached? && blob_exists?(image)
      image
    else
      nil
    end
  end

  private

  def sync_pricing_defaults
    self.currency = 'USD' if currency.blank?
    self.quantity = 1 if quantity.to_i <= 0
    if unit_price.to_f > 0
      self.estimated_price = (quantity.to_i * unit_price.to_f).round(2)
    elsif estimated_price.to_f > 0 && unit_price.to_f.zero?
      self.unit_price = (estimated_price.to_f / quantity.to_i).round(2)
    end
  end

  def trigger_goal_check!
    reinvestment_goal&.check_auto_completion!
  end

  def sync_image_to_base64
    change = attachment_changes['image']
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
        self.image_base64 = "data:#{content_type};base64,#{encoded}"
      end
    elsif image_base64.blank? && image.attached? && image.blob.present?
      data = (image.blob.download rescue nil)
      if data.present?
        content_type = image.blob.content_type.presence || 'image/jpeg'
        encoded = Base64.strict_encode64(data)
        self.image_base64 = "data:#{content_type};base64,#{encoded}"
      end
    end
  end

  def ensure_base64_persisted
    return if image_base64.present? || !image.attached? || image.blob.nil?

    if blob_exists?(image)
      data = (image.blob.download rescue nil)
      if data.present?
        content_type = image.blob.content_type.presence || 'image/jpeg'
        encoded = Base64.strict_encode64(data)
        update_column(:image_base64, "data:#{content_type};base64,#{encoded}")
      end
    end
  rescue StandardError => e
    Rails.logger.warn("ensure_base64_persisted error: #{e.message}")
  end

  def blob_exists?(attachment)
    return false unless attachment&.attached? && attachment.blob
    attachment.blob.service.exist?(attachment.blob.key)
  rescue StandardError
    false
  end
end
