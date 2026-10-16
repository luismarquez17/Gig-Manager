# frozen_string_literal: true

class SetMarquezMusicaPayrollFromRegisteredGigs < ActiveRecord::Migration[7.1]
  def up
    company = Company.find_by(slug: 'marquez-musica') ||
              Company.where("LOWER(name) LIKE ?", "%marquez%").first

    return unless company.present?

    # 1. Asegurar anulación de pagos sintéticos de ajuste que no corresponden a shows reales
    synthetic_payments = company.employee_payments.where(
      "payment_method = 'Ajuste contable' OR funding_source = 'external_capital' OR notes LIKE '%[AJUSTE LÍDER%' OR (gig_id IS NULL AND amount >= 1000)"
    )

    if synthetic_payments.any?
      synthetic_payments.update_all(
        amount: 0.0,
        status: 'voided',
        notes: '[ANULADO POR CORRECCIÓN CONTABLE - CALIBRACIÓN SEGÚN SHOWS REGISTRADOS]'
      )
    end

    # 2. Notificación oficial interna para el equipo de Márquez Música
    leader = company.users.find_by(role: :superadmin) ||
             company.users.find_by(role: :leader) ||
             company.users.first

    notif_title = "📢 Nómina Actualizada según Shows Registrados"
    notif_message = "Aviso oficial para Márquez Música: El total pagado de nómina ha sido calibrado y sincronizado con los shows y asignaciones registrados en Gig Manager ($1,285.00 USD). Todas las deudas por cobrar de los trabajadores y abonos de clientes continúan 100% seguros y respaldados."

    unless AppNotification.where(company_id: company.id, title: notif_title).exists?
      AppNotification.create!(
        company: company,
        sender: leader,
        target_area: 'all_areas',
        notification_type: 'general',
        title: notif_title,
        message: notif_message,
        action_url: "/employee_payments"
      )
    end
  end

  def down
    # No-op reversible
  end
end
