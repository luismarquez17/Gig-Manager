namespace :business do
  desc "Configura Gero Producciones o cualquier salón de fiesta con el perfil venue_academy, módulos y combos de salón"
  task :setup_gero_producciones => :environment do
    company = Company.find_by("slug ILIKE ? OR name ILIKE ?", "%gero%", "%gero%")
    if company.blank?
      puts "🏢 Creando Gero Producciones..."
      company = Company.create!(
        name: "Gero Producciones",
        slug: "gero-producciones",
        business_type: "venue_academy",
        plan_tier: "salon",
        status: :active,
        subscription_status: "active",
        monthly_fee: 15.00,
        currency: "USD"
      )
    end

    puts "✨ Aplicando defaults de Salón & Academia a #{company.name} (ID: #{company.id})..."
    company.apply_venue_academy_defaults!
    puts "✅ ¡Gero Producciones configurado exitosamente con modo Salón de Fiestas & Academia, módulos optimizados y combos cargados!"
  end

  desc "Configura cualquier empresa por slug para que utilice el modo Salón & Academia"
  task :setup_venue => :environment do
    slug = ENV["COMPANY_SLUG"] || ARGV[1]
    if slug.blank?
      puts "❌ Debes especificar el COMPANY_SLUG. Ejemplo: bin/rails business:setup_venue COMPANY_SLUG=mi-salon"
      exit 1
    end

    company = Company.find_by(slug: slug)
    if company.blank?
      puts "❌ Empresa con slug '#{slug}' no encontrada."
      exit 1
    end

    company.apply_venue_academy_defaults!
    puts "✅ Empresa '#{company.name}' configurada exitosamente en modo Salón de Fiestas & Academia."
  end
end
