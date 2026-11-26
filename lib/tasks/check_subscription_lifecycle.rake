# frozen_string_literal: true

namespace :subscriptions do
  desc "Evalúa el ciclo de vida de suscripción de todas las empresas (recordatorio 2 días, gracia 3 días, suspensión por no pago)"
  task check_lifecycle: :environment do
    puts "🚀 Iniciando verificación de ciclo de vida de suscripciones SaaS..."
    count = 0
    Company.find_each do |company|
      company.check_subscription_lifecycle!
      count += 1
    end
    puts "✅ Verificación completada para #{count} empresa(s)."
  end
end
