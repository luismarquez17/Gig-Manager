class Investment < ApplicationRecord
  CATEGORIES = [
    "Equipo",
    "Transporte",
    "Taller / Reparación",
    "Marketing",
    "Local de Ensayo",
    "Otros"
  ].freeze

  CURRENCIES = %w[USD BS].freeze

  SOURCES = {
    business: "Capital del Negocio (Caja del Grupo)",
    external: "Capital Externo (Aporte Personal / Préstamo)"
  }.freeze

  validates :description, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :source, presence: true, inclusion: { in: SOURCES.keys.map(&:to_s) }

  scope :by_category, ->(cat) { where(category: cat) if cat.present? }
  scope :by_currency, ->(cur) { where(currency: cur) if cur.present? }
  scope :by_source, ->(src) { where(source: src) if src.present? }
  scope :recent, -> { order(date: :desc) }
end
