class ShoppingItem < ApplicationRecord
  enum priority: { low: 0, medium: 1, high: 2 }
  enum status: { pending: 0, purchased: 1 }

  validates :name, presence: true
  validates :priority, presence: true
  validates :status, presence: true
  validates :currency, inclusion: { in: %w[USD BS EUR] }, allow_blank: true

  CATEGORIES = [
    "Cables",
    "Micrófonos",
    "Iluminación",
    "Audio / Mezcla",
    "Instrumentos",
    "Accesorios",
    "Transporte / Carga",
    "Energía / Corriente",
    "Herramientas",
    "Otros"
  ].freeze

  scope :by_priority, -> { order(priority: :desc, created_at: :desc) }
  scope :pending_first, -> { order(status: :asc, priority: :desc) }
end
