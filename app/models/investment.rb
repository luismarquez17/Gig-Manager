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

  validates :description, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validates :currency, presence: true, inclusion: { in: CURRENCIES }
  validates :category, presence: true, inclusion: { in: CATEGORIES }

  scope :by_category, ->(cat) { where(category: cat) if cat.present? }
  scope :by_currency, ->(cur) { where(currency: cur) if cur.present? }
  scope :recent, -> { order(date: :desc) }
end
