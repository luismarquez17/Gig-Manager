# frozen_string_literal: true

require "test_helper"

class ShoppingItemTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    ActsAsTenant.current_tenant = @company
  end

  test "should calculate estimated_price from quantity and unit_price" do
    item = ShoppingItem.new(
      company: @company,
      name: "Cabezas Móviles LED",
      quantity: 4,
      unit_price: 150.0,
      priority: :high
    )
    assert item.valid?
    assert_equal 600.0, item.estimated_price
    assert_equal 600.0, item.total_price
    assert_equal 150.0, item.effective_unit_price
  end

  test "should calculate unit_price from estimated_price if unit_price is 0" do
    item = ShoppingItem.create!(
      company: @company,
      name: "Tramos de Truss",
      quantity: 2,
      estimated_price: 360.0,
      priority: :medium
    )
    assert_equal 180.0, item.unit_price
    assert_equal 360.0, item.total_price
  end

  test "should link to reinvestment goal" do
    goal = ReinvestmentGoal.create!(
      company: @company,
      title: "Set de Luces",
      target_amount: 1000.0
    )

    item = ShoppingItem.create!(
      company: @company,
      reinvestment_goal: goal,
      name: "Luces Par LED",
      quantity: 4,
      unit_price: 50.0,
      priority: :high
    )

    assert_equal goal, item.reinvestment_goal
    assert_includes goal.shopping_items, item
  end
end
