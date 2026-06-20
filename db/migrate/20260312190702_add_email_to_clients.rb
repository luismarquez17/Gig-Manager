class AddEmailToClients < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:clients, :email)
      add_column :clients, :email, :string
    end
  end
end
