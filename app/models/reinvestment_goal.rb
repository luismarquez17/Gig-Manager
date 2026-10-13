# frozen_string_literal: true

class ReinvestmentGoal < ApplicationRecord
  include TenantScoped

  has_one_attached :image
  has_many :shopping_items, dependent: :nullify
  has_many :goal_savings_contributions, dependent: :destroy

  enum priority: { low: 0, medium: 1, high: 2 }

  validates :title, presence: true
  validates :target_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :saved_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: %w[USD] }
  validates :status, inclusion: { in: %w[active completed paused] }

  before_validation { self.currency = 'USD' if currency.blank? }
  before_save :sync_image_to_base64
  after_create :create_initial_contribution_if_saved_amount_present
  after_commit :ensure_base64_persisted, on: [:create, :update]

  scope :active, -> { where(status: 'active') }
  scope :completed, -> { where(status: 'completed') }
  scope :paused, -> { where(status: 'paused') }
  scope :active_first, -> { order(AASM_ORDER_SQL, priority: :desc, created_at: :desc) rescue order(priority: :desc, created_at: :desc) }
  scope :by_priority, -> { order(priority: :desc, created_at: :desc) }

  def active?
    status == 'active'
  end

  def completed?
    status == 'completed'
  end

  def paused?
    status == 'paused'
  end

  # Presupuesto total: si target_amount es 0 pero tiene ítems, toma la suma de sus ítems.
  # Si target_amount > 0 y los ítems superan el presupuesto inicial, toma el mayor.
  def effective_target_amount
    [target_amount.to_f, items_total_cost].max.round(2)
  end

  # Monto total ya conseguido para esta meta: ítems ya comprados + saldo disponible en caja de ahorro
  def total_achieved_amount
    (purchased_items_cost + saved_amount.to_f).round(2)
  end

  def progress_percentage
    eff_target = effective_target_amount
    return 0.0 if eff_target <= 0
    return 100.0 if completed? && pending_amount <= 0

    [(total_achieved_amount / eff_target * 100.0).round(1), 100.0].min
  end

  def pending_amount
    eff_target = effective_target_amount
    [eff_target - total_achieved_amount, 0.0].max.round(2)
  end

  def items_total_cost
    shopping_items.sum { |i| i.total_price }.round(2)
  end

  def pending_items_cost
    shopping_items.pending.sum { |i| i.total_price }.round(2)
  end

  def purchased_items_cost
    shopping_items.purchased.sum { |i| i.total_price }.round(2)
  end

  def completed_items_count
    shopping_items.purchased.count
  end

  def pending_items_count
    shopping_items.pending.count
  end

  # Meta realmente alcanzada: se cubrió el presupuesto total y no quedan ítems pendientes
  def target_reached?
    eff_target = effective_target_amount
    return false if eff_target <= 0

    pending_amount <= 0 && pending_items_count.zero?
  end

  def all_items_purchased?
    shopping_items.any? && pending_items_count.zero? && (purchased_items_cost >= effective_target_amount || pending_amount <= 0)
  end

  def check_auto_completion!
    return if paused?

    if target_reached?
      update_columns(status: 'completed', completed_at: Time.current) unless completed?
    elsif completed? && pending_amount > 0
      # Si una meta estaba marcada como completada pero aún le falta dinero/presupuesto, la reabre a activa
      update_columns(status: 'active', completed_at: nil)
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

  def create_initial_contribution_if_saved_amount_present
    if saved_amount.to_f > 0 && goal_savings_contributions.empty?
      goal_savings_contributions.create!(
        company: company,
        amount: saved_amount,
        currency: currency,
        date: Date.today,
        notes: "Saldo inicial de la meta"
      )
    end
  end
end
