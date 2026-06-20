class AddDetailsToItems < ActiveRecord::Migration[7.1]
  def change
    add_column :items, :quantity, :integer
    add_column :items, :notes, :text
  end
end
