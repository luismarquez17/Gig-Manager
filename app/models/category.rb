class Category < ApplicationRecord
  validates :name, presence: true, uniqueness: { case_sensitive: false }

  # Ordenar por nombre por defecto
  default_scope { order(name: :asc) }
end
