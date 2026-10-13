# frozen_string_literal: true

require "test_helper"

class GoalRecommendationServiceTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    ActsAsTenant.current_tenant = @company

    @goal = ReinvestmentGoal.create!(
      company: @company,
      title: "Iluminación Robótica y Estructura",
      target_amount: 800.0,
      saved_amount: 300.0
    )

    @item_structure = @goal.shopping_items.create!(
      company: @company,
      name: "4 metros de estructura truss",
      quantity: 1,
      unit_price: 180.0,
      priority: :high
    )

    @item_lights = @goal.shopping_items.create!(
      company: @company,
      name: "Luces móviles Beam",
      quantity: 4,
      unit_price: 150.0, # total 600.0
      priority: :high
    )
  end

  test "should identify fully affordable items with available cash" do
    # Con $300 ahorrados en la meta:
    # La estructura cuesta $180, cabe perfectamente.
    service = GoalRecommendationService.new(company: @company, goal: @goal)
    affordable = service.fully_affordable_items

    assert_includes affordable, @item_structure
    refute_includes affordable, @item_lights # cuesta $600 en total
  end

  test "should calculate partial unit affordability for expensive multi-unit items" do
    # Luces: 4 unidades a $150 c/u.
    # Con $300 disponibles, alcanza para exactamente 2 unidades de luces ($300).
    service = GoalRecommendationService.new(company: @company, goal: @goal)
    breakdown = service.items_breakdown

    light_entry = breakdown.find { |b| b[:item] == @item_lights }
    assert_not_nil light_entry
    assert_equal 4, light_entry[:quantity]
    assert_equal 150.0, light_entry[:unit_price]
    assert_equal 600.0, light_entry[:total_price]
    assert_equal 2, light_entry[:units_affordable]
    assert_equal 300.0, light_entry[:partial_cost]
    assert_equal 50.0, light_entry[:percent_covered]
    assert_equal 300.0, light_entry[:missing_amount]
  end

  test "should generate smart recommendation suggestions" do
    service = GoalRecommendationService.new(company: @company, goal: @goal)
    recommendations = service.smart_recommendations

    assert recommendations.any?
    ready = recommendations.find { |r| r[:type] == :ready_to_buy }
    assert_not_nil ready
    assert_equal @item_structure.id, ready[:item_id]
    assert_includes ready[:title], "4 metros de estructura"

    summary = recommendations.find { |r| r[:type] == :final_goal_summary }
    assert_not_nil summary
    assert_equal 500.0, summary[:deficit] # 800 - 300 = 500
  end
end
