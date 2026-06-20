class AddSubCategoryToItems < ActiveRecord::Migration[7.1]
  def change
    add_column :items, :sub_category, :string
  end
end
