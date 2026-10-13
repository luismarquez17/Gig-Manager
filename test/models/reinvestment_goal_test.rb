# frozen_string_literal: true

require "test_helper"

class ReinvestmentGoalTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    ActsAsTenant.current_tenant = @company
  end

  test "should be valid with required attributes" do
    goal = ReinvestmentGoal.new(
      company: @company,
      title: "Estructura Truss 4m y Luces",
      objective: "Mejorar la presencia en escena",
      purpose: "Elevar luces a 3 metros de altura",
      target_amount: 800.0,
      priority: :high
    )
    assert goal.valid?
    assert_equal 0.0, goal.saved_amount
    assert_equal "active", goal.status
  end

  test "should calculate progress percentage and pending amount correctly" do
    goal = ReinvestmentGoal.create!(
      company: @company,
      title: "Consola Digital",
      target_amount: 1000.0,
      saved_amount: 250.0
    )

    assert_equal 25.0, goal.progress_percentage
    assert_equal 750.0, goal.pending_amount
  end

  test "should use items_total_cost as effective target if target_amount is 0" do
    goal = ReinvestmentGoal.create!(
      company: @company,
      title: "Set de Microfonía",
      target_amount: 0.0
    )

    goal.shopping_items.create!(
      company: @company,
      name: "Micrófono Dinámico",
      quantity: 3,
      unit_price: 100.0,
      priority: :medium
    )

    assert_equal 300.0, goal.effective_target_amount
    assert_equal 300.0, goal.pending_amount

    goal.update!(saved_amount: 150.0)
    assert_equal 50.0, goal.progress_percentage
  end

  test "should auto complete when all items are purchased" do
    goal = ReinvestmentGoal.create!(
      company: @company,
      title: "Cables y Conectores",
      target_amount: 100.0
    )

    item = goal.shopping_items.create!(
      company: @company,
      name: "Cables XLR",
      quantity: 2,
      unit_price: 50.0,
      priority: :high
    )

    assert_equal "active", goal.status

    item.update!(status: :purchased)
    goal.check_auto_completion!

    assert_equal "completed", goal.reload.status
    assert goal.completed_at.present?
  end

  test "should NOT auto complete when only a partial item is purchased against higher target amount" do
    goal = ReinvestmentGoal.create!(
      company: @company,
      title: "Truss 4 metros",
      target_amount: 800.0,
      saved_amount: 0.0
    )

    item = goal.shopping_items.create!(
      company: @company,
      name: "Truss 1 metro",
      quantity: 1,
      unit_price: 95.0,
      priority: :high
    )

    assert_equal "active", goal.status

    item.update!(status: :purchased)
    goal.check_auto_completion!

    assert_equal "active", goal.reload.status
    assert_nil goal.completed_at
    assert_equal 11.9, goal.progress_percentage
    assert_equal 705.0, goal.pending_amount
  end

  test "should reopen prematurely completed goal if pending amount remains" do
    goal = ReinvestmentGoal.create!(
      company: @company,
      title: "Truss 4 metros",
      target_amount: 800.0,
      saved_amount: 0.0,
      status: "completed",
      completed_at: Time.current
    )

    goal.shopping_items.create!(
      company: @company,
      name: "Truss 1 metro",
      quantity: 1,
      unit_price: 95.0,
      status: :purchased
    )

    goal.check_auto_completion!

    assert_equal "active", goal.reload.status
    assert_nil goal.completed_at
  end
end
