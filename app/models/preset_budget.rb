class PresetBudget < ApplicationRecord
  include TenantScoped

  has_one_attached :image
  has_many :client_quotes, dependent: :nullify

  before_validation { self.currency = 'USD' if currency.blank? }
  before_save :sync_image_to_base64
  after_commit :ensure_base64_persisted, on: [:create, :update]

  validates :title, :description, :price, :currency, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: ["USD"] }

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
