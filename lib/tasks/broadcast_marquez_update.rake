namespace :marquez do
  desc "Emite la notificación oficial y activa el aviso de actualización para Márquez Música"
  task :broadcast_update => :environment do
    company = Company.find_by(slug: 'marquez-musica') ||
              Company.where("LOWER(name) LIKE ?", "%marquez%").first

    if company.blank?
      puts "❌ Empresa Márquez Música no encontrada."
      exit 1
    end

    leader = company.users.find_by(role: :superadmin) ||
             company.users.find_by(role: :leader) ||
             company.users.first

    notif_title = "🚀 Actualización del Sistema: Cuentas y Nómina al Día"

    notif = AppNotification.create!(
      company: company,
      sender: leader,
      target_area: 'all_areas',
      notification_type: 'general',
      title: notif_title,
      message: "¡Hola equipo de Márquez Música! Les damos la bienvenida a la versión actualizada de la plataforma. Hemos renovado el módulo de nómina y cuentas para brindarles mayor rapidez, comodidad y un desglose 100% transparente de sus pagos por evento. Todos sus registros de shows pasados y próximos continúan guardados con total seguridad.",
      action_url: "/my_payments"
    )

    puts "✅ Notificación emitida exitosamente a todas las áreas de Márquez Música (ID: #{notif.id})."
  end
end
