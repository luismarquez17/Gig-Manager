class StandardUpsell < ApplicationRecord
  include TenantScoped

  validates :title, presence: true

  before_validation :ensure_key

  scope :active_catalog, -> { where(active: true).order(created_at: :asc) }

  DEFAULT_UPSELLS_DATA = [
    {
      key: 'smoke_machine',
      title: 'Máquina de Humo',
      emoji: '💨',
      price: 40.0,
      currency: 'USD',
      description: 'Añade una atmósfera espectacular con nuestra máquina de humo profesional. Ideal para resaltar los efectos de las luces y el láser. (Nota: No recomendada para lugares muy al aire libre ya que el viento disipa el humo y no se aprecia su efecto).',
      active: true
    },
    {
      key: 'sparkulars',
      title: 'Máquina de Sparkulas',
      emoji: '✨',
      price: 30.0,
      currency: 'USD',
      description: 'Alquila una máquina de sparkulas (fuego frío) por 6 horas. Totalmente segura para interiores, perfecta para momentos cumbre del evento.',
      active: true
    },
    {
      key: 'subwoofer',
      title: 'Subwoofer Premium 18"',
      emoji: '🔊',
      price: 25.0,
      currency: 'USD',
      description: 'Añade un subwoofer activo de 18 pulgadas para lograr unos bajos potentes y envolventes que harán vibrar a todos tus invitados.',
      active: true
    },
    {
      key: 'extra_time',
      title: 'Horas Extra de Música',
      emoji: '🎵',
      price: 40.0,
      currency: 'USD',
      description: 'Extiende la diversión del show 2 horas más con música continua en vivo para que la fiesta no pare.',
      active: true
    }
  ].freeze

  def self.seed_defaults!
    DEFAULT_UPSELLS_DATA.each do |attrs|
      upsell = find_or_initialize_by(key: attrs[:key])
      if upsell.new_record?
        upsell.title = attrs[:title]
        upsell.emoji = attrs[:emoji]
        upsell.price = attrs[:price]
        upsell.currency = attrs[:currency]
        upsell.description = attrs[:description]
        upsell.active = attrs[:active]
        upsell.save!
      end
    end
  end

  def self.all_with_defaults
    seed_defaults! if count.zero?
    all.order(created_at: :asc)
  end

  private

  def ensure_key
    self.key = title.to_s.parameterize.underscore if key.blank? && title.present?
  end
end
