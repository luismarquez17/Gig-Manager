class KitItem < ApplicationRecord
  belongs_to :kit
  belongs_to :item

  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
end
