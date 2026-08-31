class Company < ApplicationRecord
  enum status: { active: 0, suspended: 1, past_due: 2, trial: 3 }

  has_many :users, dependent: :destroy
  has_many :clients, dependent: :destroy
  has_many :gigs, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :kits, dependent: :destroy
  has_many :investments, dependent: :destroy
  has_many :preset_budgets, dependent: :destroy
  has_many :standard_upsells, dependent: :destroy
  has_many :shopping_items, dependent: :destroy
  has_many :finance_settings, dependent: :destroy
  has_many :employee_payments, dependent: :destroy
  has_many :subscription_payments, dependent: :destroy
  has_many :gig_reviews, through: :gigs
  has_many :gig_upsell_requests, dependent: :destroy
  has_many :company_media_items, dependent: :destroy
  has_many :client_quotes, dependent: :destroy

  has_one_attached :landing_logo
  has_one_attached :landing_hero_video
  has_one_attached :landing_hero_image

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :invitation_token, uniqueness: true, allow_nil: true
  validates :monthly_fee, numericality: { greater_than_or_equal_to: 0 }

  before_validation :generate_slug_and_token, on: :create
  before_create :set_default_trial_period

  def set_default_trial_period
    self.trial_started_at ||= Time.current
    self.trial_ends_at ||= 30.days.from_now
    self.subscription_status ||= "trialing"
    self.plan_tier ||= "starter"
  end

  def trial_active?
    subscription_status == "trialing" && trial_ends_at.present? && trial_ends_at > Time.current
  end

  def trial_expired?
    subscription_status == "trialing" && trial_ends_at.present? && trial_ends_at <= Time.current
  end

  def days_left_in_trial
    return 0 unless trial_ends_at.present? && trial_ends_at > Time.current
    ((trial_ends_at - Time.current) / 1.day).ceil
  end

  def active_subscription?
    subscription_status == "active"
  end

  def access_granted?
    return true if active_subscription? || trial_active?
    false
  end

  def landing_page_enabled_by_plan?
    plan_tier == "pro" || (trial_active? && landing_enabled?)
  end

  def leaders
    users.where(role: [:leader, :superadmin])
  end


  def primary_leader
    leaders.first
  end

  def regenerate_token!
    update!(invitation_token: SecureRandom.hex(12))
  end

  def status_badge_class
    case status.to_sym
    when :active
      "bg-emerald-500/10 text-emerald-400 border-emerald-500/20"
    when :suspended
      "bg-rose-500/10 text-rose-400 border-rose-500/20"
    when :past_due
      "bg-amber-500/10 text-amber-400 border-amber-500/20"
    when :trial
      "bg-blue-500/10 text-blue-400 border-blue-500/20"
    else
      "bg-slate-500/10 text-slate-400 border-slate-500/20"
    end
  end

  def approved_reviews
    gig_reviews.where(gig_reviews: { approved: true })
  end

  def average_rating
    reviews = approved_reviews
    return 5.0 if reviews.empty?
    (reviews.average(:rating) || 5.0).to_f.round(1)
  end

  def landing_section_visible?(key)
    return true unless landing_sections_config.is_a?(Hash)
    landing_sections_config[key.to_s] != false && landing_sections_config[key.to_s] != "false"
  end

  def brand_name_for_landing
    if landing_sections_config.is_a?(Hash) && landing_sections_config["custom_brand_name"].present?
      return landing_sections_config["custom_brand_name"].to_s.strip
    end
    name
  end

  def logo_height_px
    if landing_sections_config.is_a?(Hash) && landing_sections_config["logo_height"].to_i > 0
      landing_sections_config["logo_height"].to_i.clamp(25, 120)
    else
      50
    end
  end

  def hero_image_blur_px
    if landing_sections_config.is_a?(Hash) && landing_sections_config.key?("hero_image_blur")
      landing_sections_config["hero_image_blur"].to_i.clamp(0, 30)
    else
      8
    end
  end

  def hero_image_opacity_pct
    if landing_sections_config.is_a?(Hash) && landing_sections_config.key?("hero_image_opacity")
      landing_sections_config["hero_image_opacity"].to_i.clamp(5, 100)
    else
      35
    end
  end

  def show_brand_name_with_logo?
    return true unless landing_sections_config.is_a?(Hash)
    return true unless landing_sections_config.key?("show_brand_name_with_logo")
    landing_sections_config["show_brand_name_with_logo"] == "1" || landing_sections_config["show_brand_name_with_logo"] == true || landing_sections_config["show_brand_name_with_logo"] == "true"
  end

  TEMPLATES_CATALOG = {
    "classic_stage" => {
      name: "Clásica Escenario",
      badge: "INCLUIDO ($0/mes)",
      price: "$0 / mes",
      description: "Diseño elegante en modo oscuro con efecto cristal (glassmorphism), tipografía moderna y tarjetas balanceadas.",
      font: "'Outfit', sans-serif",
      style_class: "template-classic-stage"
    },
    "neon_festival" => {
      name: "Neón Festival Cyberpunk",
      badge: "PRO FESTIVAL ($15/mes)",
      price: "$15 / mes",
      description: "Bordes fosforescentes de neón, gradientes de alto contraste, tipografía Cyber Grotesk y animaciones dinámicas.",
      font: "'Space Grotesk', sans-serif",
      style_class: "template-neon-festival"
    },
    "royal_gala" => {
      name: "Royal Gala Luxury & Bodas VIP",
      badge: "VIP ROYAL ($29/mes)",
      price: "$29 / mes",
      description: "Diseño suntuoso de alta gala para bodas de lujo, tipografía serif dorada, acentos champagne y estética aristocrática.",
      font: "'Playfair Display', serif",
      style_class: "template-royal-gala"
    },
    "minimal_acoustic" => {
      name: "Minimal Studio & Acústico Refinado",
      badge: "STUDIO MINIMAL ($19/mes)",
      price: "$19 / mes",
      description: "Estética minimalista de estudio de grabación, fondo azabache mate, líneas ultra finas y foco absoluto en los precios.",
      font: "'Inter', sans-serif",
      style_class: "template-minimal-acoustic"
    }
  }.freeze

  TEMPLATE_DEFAULTS = {
    "classic_stage" => {
      theme_color: "#8b5cf6",
      accent_color: "#06b6d4",
      font_family: "'Outfit', sans-serif",
      gradient_style: "linear_neon",
      bg_style: "stage_lights"
    },
    "neon_festival" => {
      theme_color: "#ec4899",
      accent_color: "#10b981",
      font_family: "'Space Grotesk', sans-serif",
      gradient_style: "linear_neon",
      bg_style: "stage_lights"
    },
    "royal_gala" => {
      theme_color: "#eab308",
      accent_color: "#ca8a04",
      font_family: "'Playfair Display', serif",
      gradient_style: "radial_glow",
      bg_style: "royal"
    },
    "minimal_acoustic" => {
      theme_color: "#64748b",
      accent_color: "#38bdf8",
      font_family: "'Inter', sans-serif",
      gradient_style: "solid_bold",
      bg_style: "carbon"
    }
  }.freeze

  AVAILABLE_FONTS = {
    "default" => "Predeterminada por Plantilla",
    "Outfit" => "Outfit (Moderna & Balanceada)",
    "Space Grotesk" => "Space Grotesk (Cyber & Festival)",
    "Playfair Display" => "Playfair Display (Serif Elegante & Bodas)",
    "Inter" => "Inter (Minimal & Estudio Refinado)",
    "Cinzel" => "Cinzel (Imperial Classical & Gala)",
    "Montserrat" => "Montserrat (Versátil Urban Pop)",
    "Syne" => "Syne (Vanguardista & Artística)"
  }.freeze

  GRADIENT_STYLES = {
    "linear_neon" => "Degradado Lineal Neón (Primario ➔ Secundario)",
    "radial_glow" => "Resplandor Radial Centrado (Glow)",
    "triple_mesh" => "Degradado Múltiple Neón (Primario ➔ Secundario ➔ Esmeralda)",
    "solid_bold" => "Color Sólido Puro (Sin Degradado)"
  }.freeze

  BG_STYLES = {
    "midnight" => {
      name: "Midnight Blue & Orbes Neón (Por defecto)",
      bg_color: "#070914",
      bg_image: "radial-gradient(circle at 20% 20%, %{p_glow} 0%, transparent 45%), radial-gradient(circle at 80% 70%, %{a_glow} 0%, transparent 50%)"
    },
    "carbon" => {
      name: "Carbon Luxury & Malla de Titanio",
      bg_color: "#0c0d10",
      bg_image: "linear-gradient(135deg, rgba(255,255,255,0.03) 25%, transparent 25%), linear-gradient(225deg, rgba(255,255,255,0.03) 25%, transparent 25%), linear-gradient(45deg, rgba(255,255,255,0.03) 25%, transparent 25%), linear-gradient(315deg, rgba(255,255,255,0.03) 25%, transparent 25%)",
      bg_size: "24px 24px"
    },
    "royal" => {
      name: "Royal Velvet & Reflejos Champagne",
      bg_color: "#050716",
      bg_image: "radial-gradient(ellipse at 50% 0%, rgba(234, 179, 8, 0.22) 0%, transparent 70%), radial-gradient(circle at 85% 85%, %{p_glow} 0%, transparent 50%)"
    },
    "concert_smoke" => {
      name: "Luces de Escenario & Humo de Concierto",
      bg_color: "#050508",
      bg_image: "radial-gradient(ellipse at 50% -10%, %{p_glow} 0%, transparent 65%), radial-gradient(circle at 50% 100%, %{a_glow} 0%, transparent 65%)"
    },
    "cyber_grid" => {
      name: "Matriz Cyberpunk & Malla Neón 3D",
      bg_color: "#050811",
      bg_image: "linear-gradient(rgba(255,255,255,0.06) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.06) 1px, transparent 1px)",
      bg_size: "40px 40px"
    },
    "pure_dark" => {
      name: "Negro OLED Puro Absolute Black",
      bg_color: "#000000",
      bg_image: "none"
    }
  }.freeze

  def use_custom_theme?
    return false unless landing_sections_config.is_a?(Hash)
    landing_sections_config["use_custom_theme"] == "1" || landing_sections_config["use_custom_theme"] == true || landing_sections_config["use_custom_theme"] == "true"
  end

  def native_template_defaults
    TEMPLATE_DEFAULTS[landing_template] || TEMPLATE_DEFAULTS["classic_stage"]
  end

  def reset_template_defaults!(template_key = nil)
    key = (template_key.presence || landing_template).to_s
    defaults = TEMPLATE_DEFAULTS[key] || TEMPLATE_DEFAULTS["classic_stage"]
    cfg = landing_sections_config.is_a?(Hash) ? landing_sections_config.dup : {}
    cfg["use_custom_theme"] = false
    update!(
      landing_theme_color: defaults[:theme_color],
      landing_accent_color: defaults[:accent_color],
      landing_font_family: defaults[:font_family],
      landing_gradient_style: defaults[:gradient_style],
      landing_bg_style: defaults[:bg_style],
      landing_sections_config: cfg
    )
  end

  def template_price(key)
    prices = landing_template_prices.is_a?(Hash) ? landing_template_prices : {}
    if prices.key?(key.to_s)
      prices[key.to_s].to_f
    else
      default_prices = { "classic_stage" => 0.0, "neon_festival" => 15.0, "royal_gala" => 29.0, "minimal_acoustic" => 19.0 }
      default_prices[key.to_s] || 0.0
    end
  end

  def template_price_formatted(key)
    price = template_price(key)
    if price <= 0
      "$0 / mes (INCLUIDO)"
    else
      "$#{price.to_i} / mes"
    end
  end

  def template_badge_formatted(key, fallback_badge = nil)
    price = template_price(key).to_i
    category_name = case key.to_s
                    when "classic_stage" then "INCLUIDO"
                    when "neon_festival" then "PRO FESTIVAL"
                    when "royal_gala" then "VIP ROYAL"
                    when "minimal_acoustic" then "STUDIO MINIMAL"
                    else "PLANTILLA"
                    end

    if price <= 0
      "#{category_name} ($0/mes)"
    else
      "#{category_name} ($#{price}/mes)"
    end
  end

  def font_css
    if use_custom_theme? && landing_font_family.present? && landing_font_family != "default" && AVAILABLE_FONTS.key?(landing_font_family)
      if landing_font_family == "Playfair Display" || landing_font_family == "Cinzel"
        "'#{landing_font_family}', serif"
      else
        "'#{landing_font_family}', sans-serif"
      end
    else
      native_template_defaults[:font_family]
    end
  end

  def theme_hex
    if use_custom_theme? && landing_theme_color.present?
      landing_theme_color
    else
      native_template_defaults[:theme_color]
    end
  end

  def accent_hex
    if use_custom_theme? && landing_accent_color.present?
      landing_accent_color
    else
      native_template_defaults[:accent_color]
    end
  end

  def bg_style_data
    bg_key = use_custom_theme? ? (landing_bg_style.presence || native_template_defaults[:bg_style]) : native_template_defaults[:bg_style]
    BG_STYLES[bg_key] || BG_STYLES["midnight"]
  end

  def bg_style_css
    p_glow = theme_hex + "55"
    a_glow = accent_hex + "44"
    data = bg_style_data
    raw_img = data[:bg_image] % { p_glow: p_glow, a_glow: a_glow } rescue data[:bg_image]
    {
      color: data[:bg_color],
      image: raw_img,
      size: data[:bg_size] || "auto"
    }
  end

  def template_data
    TEMPLATES_CATALOG[landing_template] || TEMPLATES_CATALOG["classic_stage"]
  end

  def gradient_css
    p_hex = theme_hex
    s_hex = accent_hex
    style = use_custom_theme? ? (landing_gradient_style.presence || native_template_defaults[:gradient_style]) : native_template_defaults[:gradient_style]

    case style
    when "radial_glow"
      "radial-gradient(circle at 50% 50%, #{p_hex} 0%, #{s_hex} 100%)"
    when "triple_mesh"
      "linear-gradient(135deg, #{p_hex} 0%, #{s_hex} 50%, #10b981 100%)"
    when "solid_bold"
      p_hex
    else # linear_neon
      "linear-gradient(135deg, #{p_hex} 0%, #{s_hex} 100%)"
    end
  end

  def effective_faqs
    if landing_faqs.present? && landing_faqs.is_a?(Array) && landing_faqs.any?
      landing_faqs
    else
      default_faqs
    end
  end

  def default_faqs
    [
      {
        "q" => "¿Con cuánta anticipación debo reservar la fecha?",
        "a" => "Recomendamos apartar con al menos 3 a 6 semanas de antelación para garantizar la disponibilidad del equipo y músicos en tu fecha deseada."
      },
      {
        "q" => "¿El presupuesto incluye sonido e iluminación profesional?",
        "a" => "¡Sí! Nuestros paquetes incluyen el sistema de sonido profesional ajustado al tamaño de tu evento, consolas y operadores técnicos dedicados."
      },
      {
        "q" => "¿En qué zonas y lugares realizan sus presentaciones?",
        "a" => "Nos presentamos en Maracaibo, San Francisco, Costa Oriental y todo el estado Zulia, además de traslados a nivel nacional según la ubicación del evento."
      },
      {
        "q" => "¿Cómo es el proceso de contratación y pagos?",
        "a" => "Se formaliza mediante contrato digital seguro con un 50% de anticipo para congelar la fecha, y el saldo restante se liquida el día del show."
      }
    ]
  end

  def effective_calculator_formats
    if landing_calculator_formats.present? && landing_calculator_formats.is_a?(Array) && landing_calculator_formats.any?
      landing_calculator_formats
    else
      default_calculator_formats
    end
  end

  def default_calculator_formats
    [
      { "key" => "acoustic", "name" => "Acústico", "musicians" => "Dúo / Trío", "price" => 400, "emoji" => "🎻" },
      { "key" => "full_band", "name" => "Banda Completa", "musicians" => "5 Músicos", "price" => 750, "emoji" => "🎸" },
      { "key" => "big_band", "name" => "Big Band", "musicians" => "Metales & Show (8+ Músicos)", "price" => 1200, "emoji" => "🎺" }
    ]
  end

  def landing_upsells
    standard_upsells.where(active: true, show_on_landing: true).order(landing_position: :asc, created_at: :asc)
  end

  def landing_preset_budgets
    preset_budgets.where(show_on_landing: true).order(featured: :desc, position: :asc, created_at: :asc)
  end

  def all_preset_budgets
    preset_budgets.order(featured: :desc, position: :asc, created_at: :asc)
  end

  def landing_staff_members
    users.where(role: [:leader, :musician, :staff, :superadmin], show_on_landing: true).order(landing_position: :asc, created_at: :asc)
  end

  def all_staff_members
    users.where(role: [:leader, :musician, :staff, :superadmin]).order(landing_position: :asc, created_at: :asc)
  end

  private

  def generate_slug_and_token
    self.slug ||= name.to_s.parameterize.presence || SecureRandom.hex(4)
    self.invitation_token ||= SecureRandom.hex(12)
  end
end
