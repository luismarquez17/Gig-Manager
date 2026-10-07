class BroadcastMarquezMusicaUpdateNotification < ActiveRecord::Migration[7.1]
  def up
    company = Company.find_by(slug: 'marquez-musica') ||
              Company.where("LOWER(name) LIKE ?", "%marquez%").first

    return unless company.present?

    leader = company.users.find_by(role: :superadmin) ||
             company.users.find_by(role: :leader) ||
             company.users.first

    notif_title = "🚀 Actualización del Sistema: Cuentas y Nómina al Día"
    
    # Evitar duplicados si la migración se re-ejecuta
    unless AppNotification.where(company_id: company.id, title: notif_title).exists?
      AppNotification.create!(
        company: company,
        sender: leader,
        target_area: 'all_areas',
        notification_type: 'general',
        title: notif_title,
        message: "¡Hola equipo de Márquez Música! Les damos la bienvenida a la versión actualizada de la plataforma. Hemos renovado el módulo de nómina y cuentas para brindarles mayor rapidez, comodidad y un desglose 100% transparente de sus pagos por evento. Todos sus registros de shows pasados y próximos continúan guardados con total seguridad.",
        action_url: "/my_payments"
      )
    end
  end

  def down
    # No-op
  end
end
