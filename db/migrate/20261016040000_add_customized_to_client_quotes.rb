class AddCustomizedToClientQuotes < ActiveRecord::Migration[7.1]
  def up
    add_column :client_quotes, :customized, :boolean, default: false, null: false

    # Backfill existing client quotes: if they have a preset budget or amount > 0 or details present
    ClientQuote.reset_column_information
    ClientQuote.unscoped.find_each do |quote|
      is_custom = quote.preset_budget_id.present? || 
                  quote.amount.to_f > 0 || 
                  (quote.details.present? && !quote.details.to_s.strip.empty?) || 
                  (quote.package_name.present? && quote.package_name != 'Servicio Personalizado')
      quote.update_columns(customized: is_custom) if is_custom
    end
  end

  def down
    remove_column :client_quotes, :customized
  end
end
