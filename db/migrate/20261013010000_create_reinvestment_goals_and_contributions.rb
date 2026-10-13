# frozen_string_literal: true

class CreateReinvestmentGoalsAndContributions < ActiveRecord::Migration[7.1]
  def change
    create_table :reinvestment_goals do |t|
      t.references :company, null: false, foreign_key: true, index: true
      t.string :title, null: false
      t.text :objective
      t.text :purpose
      t.decimal :target_amount, precision: 12, scale: 2, default: 0.0, null: false
      t.decimal :saved_amount, precision: 12, scale: 2, default: 0.0, null: false
      t.string :currency, default: 'USD', null: false
      t.string :status, default: 'active', null: false
      t.text :image_base64
      t.integer :priority, default: 1, null: false
      t.date :target_date
      t.datetime :completed_at

      t.timestamps
    end
    add_index :reinvestment_goals, :status

    add_reference :shopping_items, :reinvestment_goal, foreign_key: true, index: true
    add_column :shopping_items, :quantity, :integer, default: 1, null: false
    add_column :shopping_items, :unit_price, :decimal, precision: 12, scale: 2, default: 0.0, null: false
    add_column :shopping_items, :image_base64, :text

    create_table :goal_savings_contributions do |t|
      t.references :company, null: false, foreign_key: true, index: true
      t.references :reinvestment_goal, null: false, foreign_key: true, index: true
      t.references :gig, foreign_key: true, index: true
      t.references :user, foreign_key: true, index: true
      t.decimal :amount, precision: 12, scale: 2, default: 0.0, null: false
      t.string :currency, default: 'USD', null: false
      t.date :date, null: false
      t.text :notes

      t.timestamps
    end
  end
end
