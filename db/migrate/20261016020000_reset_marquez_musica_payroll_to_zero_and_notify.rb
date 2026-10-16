# frozen_string_literal: true

class ResetMarquezMusicaPayrollToZeroAndNotify < ActiveRecord::Migration[7.1]
  def up
    company = Company.find_by(slug: 'marquez-musica') ||
              Company.where("LOWER(name) LIKE ?", "%marquez%").first

    return unless company.present?

    # 1. Asegurar fecha de corte oficial
    company.update_columns(financial_reset_date: Date.new(2026, 10, 13))

    # 2. Anular de forma segura en base de datos todos los pagos sintéticos / ajustes que inflaron la nómina a $34,800+
    synthetic_payments = company.employee_payments.where(
      "payment_method = 'Ajuste contable' OR funding_source = 'external_capital' OR notes LIKE '%[AJUSTE LÍDER%' OR (gig_id IS NULL AND amount >= 1000)"
    )

    if synthetic_payments.any?
      synthetic_payments.update_all(
        amount: 0.0,
        status: 'voided',
        notes: '[ANULADO POR CORRECCIÓN CONTABLE - REINICIO A $0.00]'
      )
    end

    # 3. Notificación oficial interna para todo el equipo de Márquez Música
    leader = company.users.find_by(role: :superadmin) ||
             company.users.find_by(role: :leader) ||
             company.users.first

    notif_title = "📢 Actualización de Nómina: Total Pagado Reiniciado a $0.00"
    notif_message = "Aviso oficial para el equipo de Márquez Música: Se ha calibrado y ajustado el Total Pagado de nómina, iniciando limpiamente en $0.00 para este nuevo ciclo contable. Todas las deudas por cobrar de los trabajadores y los abonos de eventos se mantienen 100% seguros e intactos."

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
