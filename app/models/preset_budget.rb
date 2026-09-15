class PresetBudget < ApplicationRecord
  include TenantScoped

  has_one_attached :image
  has_many :client_quotes, dependent: :nullify

  validates :title, :description, :price, :currency, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: ["USD", "BS"] }
end
