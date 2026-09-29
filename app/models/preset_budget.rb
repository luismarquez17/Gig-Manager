class PresetBudget < ApplicationRecord
  include TenantScoped

  has_one_attached :image
  has_many :client_quotes, dependent: :nullify

  before_validation { self.currency = 'USD' if currency.blank? }

  validates :title, :description, :price, :currency, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: ["USD"] }

  def image_attached?
    image_base64.present? || image.attached?
  end

  def image_url_or_data
    if image_base64.present?
      image_base64
    elsif image.attached?
      image
    else
      nil
    end
  end
end
