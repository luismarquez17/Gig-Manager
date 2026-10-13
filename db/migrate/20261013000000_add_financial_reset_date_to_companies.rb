# frozen_string_literal: true

class AddFinancialResetDateToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :financial_reset_date, :date

    reversible do |dir|
      dir.up do
        company = Company.find_by(slug: 'marquez-musica') ||
                  Company.where("LOWER(name) LIKE ?", "%marquez%").first

        if company.present?
          company.update_columns(financial_reset_date: Date.new(2026, 10, 13))

          leader = company.users.find_by(role: :superadmin) ||
                   company.users.find_by(role: :leader) ||
                   company.users.first

          notif_title = "✨ Actualización Operativa: Nuevo Ciclo de Cuentas y Nómina"
          unless AppNotification.where(company_id: company.id, title: notif_title).exists?
            AppNotification.create!(
              company: company,
              sender: leader,
              target_area: 'all_areas',
              notification_type: 'general',
              title: notif_title,
              message: "¡Hola equipo de Márquez Música! Les informamos que a partir de hoy (13 de Octubre) entra en vigencia un nuevo ciclo contable limpio en la app para mayor precisión y comodidad. Todas sus deudas por cobrar y los abonos de clientes para los próximos shows están 100% seguros e intactos.",
              action_url: "/my_payments"
            )
          end
        end
      end
    end
  end
end
