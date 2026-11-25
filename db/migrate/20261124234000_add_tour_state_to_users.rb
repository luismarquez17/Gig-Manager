class AddTourStateToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :tour_state, :jsonb, default: {}, null: false
  end
end
