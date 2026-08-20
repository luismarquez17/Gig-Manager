class AddLandingFieldsToPresetBudgets < ActiveRecord::Migration[7.1]
  def change
    add_column :preset_budgets, :show_on_landing, :boolean, default: true
    add_column :preset_budgets, :featured, :boolean, default: false
    add_column :preset_budgets, :badge_text, :string
    add_column :preset_budgets, :position, :integer, default: 0
  end
end
