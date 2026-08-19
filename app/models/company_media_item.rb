class CompanyMediaItem < ApplicationRecord
  belongs_to :company

  has_one_attached :media_file
  has_one_attached :thumbnail

  CATEGORIES = {
    "live_show" => "🔥 Show en Vivo & Tarima",
    "instruments" => "🎸 Instrumentos & Backline",
    "effects" => "✨ Iluminación & Efectos",
    "backstage" => "🎬 Montaje & Backstage"
  }.freeze

  MEDIA_TYPES = {
    "video" => "📹 Video MP4",
    "photo" => "📸 Fotografía",
    "youtube" => "▶️ Enlace YouTube"
  }.freeze

  validates :title, presence: true
  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :media_type, inclusion: { in: MEDIA_TYPES.keys }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(featured: :desc, position: :asc, created_at: :desc) }
  scope :by_category, ->(cat) { where(category: cat) if cat.present? }

  def category_label
    CATEGORIES[category] || category.titleize
  end

  def media_type_label
    MEDIA_TYPES[media_type] || media_type.titleize
  end

  def youtube_embed_url
    return nil unless youtube? && video_url.present?

    # Maneja URLs normales de youtube (watch?v=...), acortadas (youtu.be/...) o shorts
    if video_url =~ /(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})/i
      "https://www.youtube-nocookie.com/embed/#{$1}?autoplay=0&rel=0"
    else
      video_url
    end
  end

  def video?
    media_type == "video"
  end

  def photo?
    media_type == "photo"
  end

  def youtube?
    media_type == "youtube"
  end
end
