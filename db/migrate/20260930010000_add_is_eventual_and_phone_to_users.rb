class AddIsEventualAndPhoneToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :is_eventual, :boolean, default: false, null: false
    add_column :users, :phone, :string
    add_index :users, :is_eventual
  end
end
