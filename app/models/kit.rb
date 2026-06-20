class Kit < ApplicationRecord
  has_many :kit_items, dependent: :destroy
  has_many :items, through: :kit_items

  accepts_nested_attributes_for :kit_items, allow_destroy: true, reject_if: :all_blank

  validates :name, presence: true, uniqueness: true
end
