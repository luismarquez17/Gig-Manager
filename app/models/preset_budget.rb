class PresetBudget < ApplicationRecord
  has_one_attached :image

  validates :title, :description, :price, :currency, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: ["USD", "BS"] }
end
