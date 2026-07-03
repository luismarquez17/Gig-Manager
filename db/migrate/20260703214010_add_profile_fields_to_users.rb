class AddProfileFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :name, :string
    add_column :users, :specialty, :string
    add_column :users, :bio, :text
  end
end
