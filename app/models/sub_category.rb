class SubCategory < ApplicationRecord
  validates :name, presence: true, uniqueness: { scope: :category, case_sensitive: false }
  validates :category, presence: true
end
