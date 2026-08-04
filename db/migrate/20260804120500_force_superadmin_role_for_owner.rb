class ForceSuperadminRoleForOwner < ActiveRecord::Migration[7.1]
  def up
    token = SecureRandom.hex(12)

    # 1. Asegurar empresa Márquez Música
    execute <<-SQL
      INSERT INTO companies (name, slug, status, monthly_fee, currency, invitation_token, created_at, updated_at)
      SELECT 'Márquez Música', 'marquez-musica', 0, 0.00, 'USD', '#{token}', NOW(), NOW()
      WHERE NOT EXISTS (SELECT 1 FROM companies WHERE slug = 'marquez-musica');
    SQL

    company_record = execute("SELECT id FROM companies WHERE slug = 'marquez-musica' LIMIT 1").first
    company_id = company_record["id"]

    # 2. Asociar cualquier registro sin empresa a Márquez Música
    %w[users clients gigs items kits investments preset_budgets standard_upsells shopping_items finance_settings employee_payments].each do |table_name|
      execute("UPDATE #{table_name} SET company_id = #{company_id} WHERE company_id IS NULL;")
    end

    # 3. Forzar rol Superadmin (role: 4) y contraseña (123456) para luismarquezocando2006@gmail.com
    encrypted_pass = Devise::Encryptor.digest(User, '123456')
    user_record = execute("SELECT id FROM users WHERE email = 'luismarquezocando2006@gmail.com' LIMIT 1").first

    if user_record
      execute <<-SQL
        UPDATE users 
        SET role = 4, encrypted_password = '#{encrypted_pass}', company_id = #{company_id} 
        WHERE email = 'luismarquezocando2006@gmail.com';
      SQL
    else
      execute <<-SQL
        INSERT INTO users (email, encrypted_password, role, company_id, name, created_at, updated_at)
        VALUES ('luismarquezocando2006@gmail.com', '#{encrypted_pass}', 4, #{company_id}, 'Luis Márquez', NOW(), NOW());
      SQL
    end
  end

  def down
  end
end
