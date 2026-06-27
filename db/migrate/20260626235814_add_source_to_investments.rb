class AddSourceToInvestments < ActiveRecord::Migration[7.1]
  def change
    add_column :investments, :source, :string
    add_column :investments, :investor_name, :string
  end
end
