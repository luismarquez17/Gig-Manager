class CreateFinancialAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_audit_logs do |t|
      t.references :company, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :auditable_type, null: false
      t.bigint :auditable_id, null: false
      t.string :action, null: false, default: 'created'
      t.decimal :amount_before, precision: 12, scale: 2
      t.decimal :amount_after, precision: 12, scale: 2
      t.string :currency, default: 'USD', null: false
      t.text :reason
      t.jsonb :details, default: {}, null: false
      t.string :ip_address

      t.timestamps
    end

    add_index :financial_audit_logs, [:company_id, :created_at]
    add_index :financial_audit_logs, [:auditable_type, :auditable_id]
    add_index :financial_audit_logs, :action
  end
end
