class AddImageBase64ToPresetBudgets < ActiveRecord::Migration[7.1]
  def change
    add_column :preset_budgets, :image_base64, :text
  end
end
