class Song < ApplicationRecord
  include TenantScoped

  belongs_to :company

  validates :title, presence: true
  validates :genre, presence: true

  scope :active, -> { where(active: true) }
  scope :by_genre, ->(genre) { where(genre: genre) if genre.present? }

  # Lista de géneros predeterminados para categorizar canciones
  DEFAULT_GENRES = [
    'Rock / Pop en Español',
    'Pop / Disco Internacional',
    'Bailable / Tropical / Salsa / Merengue',
    'Reggaetón / Urbano',
    'Baladas / Románticas / Primer Baile',
    'Jazz / Bossa / Instrumental',
    'Clásicos / Retro'
  ].freeze
end
