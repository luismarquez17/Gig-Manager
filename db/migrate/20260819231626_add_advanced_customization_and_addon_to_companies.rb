class AddAdvancedCustomizationAndAddonToCompanies < ActiveRecord::Migration[7.1]
  def change
    # Flag para cobrar el módulo de Landing Page por separado (Add-on SaaS)
    add_column :companies, :landing_enabled, :boolean, default: true, null: false
    add_column :companies, :landing_plan, :string, default: "pro" # starter, pro, enterprise

    # Temas, Colores y Estilos
    add_column :companies, :landing_theme_color, :string, default: "#8b5cf6"
    add_column :companies, :landing_accent_color, :string, default: "#06b6d4"
    add_column :companies, :landing_bg_style, :string, default: "midnight" # midnight, carbon, royal

    # Textos del Hero y CTA
    add_column :companies, :landing_hero_title, :string
    add_column :companies, :landing_hero_subtitle, :string
    add_column :companies, :landing_hero_cta_text, :string, default: "Simular Mi Presupuesto en Vivo"

    # Configuración de secciones visibles (JSONB)
    add_column :companies, :landing_sections_config, :jsonb, default: {
      "show_metrics" => true,
      "show_packages" => true,
      "show_calculator" => true,
      "show_media" => true,
      "show_team" => true,
      "show_reviews" => true,
      "show_faq" => true
    }

    # Preguntas Frecuentes personalizables (JSONB)
    add_column :companies, :landing_faqs, :jsonb, default: []
  end
end
