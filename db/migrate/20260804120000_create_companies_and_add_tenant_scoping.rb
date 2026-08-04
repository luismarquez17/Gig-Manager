class CreateCompaniesAndAddTenantScoping < ActiveRecord::Migration[7.1]
  def change
    create_table :companies do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :status, default: 0, null: false
      t.decimal :monthly_fee, precision: 12, scale: 2, default: 0.0, null: false
      t.string :currency, default: "USD"
      t.integer :billing_day, default: 1
      t.string :invitation_token
      t.string :contact_email
      t.string :contact_phone
      t.text :notes

      t.timestamps
    end

    add_index :companies, :slug, unique: true
    add_index :companies, :invitation_token, unique: true

    add_reference :users, :company, foreign_key: true, null: true
    add_reference :clients, :company, foreign_key: true, null: true
    add_reference :gigs, :company, foreign_key: true, null: true
    add_reference :items, :company, foreign_key: true, null: true
    add_reference :kits, :company, foreign_key: true, null: true
    add_reference :investments, :company, foreign_key: true, null: true
    add_reference :preset_budgets, :company, foreign_key: true, null: true
    add_reference :standard_upsells, :company, foreign_key: true, null: true
    add_reference :shopping_items, :company, foreign_key: true, null: true
    add_reference :finance_settings, :company, foreign_key: true, null: true
    add_reference :employee_payments, :company, foreign_key: true, null: true

    reversible do |dir|
      dir.up do
        token = SecureRandom.hex(12)
        execute <<-SQL
          INSERT INTO companies (name, slug, status, monthly_fee, currency, invitation_token, created_at, updated_at)
          VALUES ('Márquez Música', 'marquez-musica', 0, 0.00, 'USD', '#{token}', NOW(), NOW());
        SQL

        company_id = execute("SELECT id FROM companies WHERE slug = 'marquez-musica' LIMIT 1").first["id"]

        %w[users clients gigs items kits investments preset_budgets standard_upsells shopping_items finance_settings employee_payments].each do |table_name|
          execute("UPDATE #{table_name} SET company_id = #{company_id} WHERE company_id IS NULL;")
        end
      end
    end
  end
end
