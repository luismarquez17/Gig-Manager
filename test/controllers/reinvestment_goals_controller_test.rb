# frozen_string_literal: true

require "test_helper"

class ReinvestmentGoalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @company = companies(:one)
    @goal = ReinvestmentGoal.create!(
      company: @company,
      title: "Consola Digital",
      objective: "Reemplazar la analógica",
      purpose: "Grabación multipista y mezcla digital",
      target_amount: 1200.0,
      saved_amount: 400.0,
      priority: :high
    )
    sign_in @user
  end

  test "should get index" do
    get reinvestment_goals_url
    assert_response :success
    assert_select "h1", /Simulador Financiero/
  end

  test "should get show" do
    get reinvestment_goal_url(@goal)
    assert_response :success
    assert_select "h1", /Consola Digital/
  end

  test "should get new" do
    get new_reinvestment_goal_url
    assert_response :success
    assert_select "h1", /Nueva Meta de Reinversión/
  end

  test "should create reinvestment_goal" do
    assert_difference("ReinvestmentGoal.count") do
      post reinvestment_goals_url, params: {
        reinvestment_goal: {
          title: "Estructura Truss 4m",
          objective: "Montar iluminación profesional",
          purpose: "Elevar las luces a 3 metros",
          target_amount: 500.0,
          priority: "high"
        }
      }
    end

    new_goal = ReinvestmentGoal.last
    assert_redirected_to reinvestment_goal_url(new_goal)
  end

  test "should get edit" do
    get edit_reinvestment_goal_url(@goal)
    assert_response :success
  end

  test "should update reinvestment_goal" do
    patch reinvestment_goal_url(@goal), params: {
      reinvestment_goal: {
        title: "Consola Digital Behringer X32",
        target_amount: 1500.0
      }
    }
    assert_redirected_to reinvestment_goal_url(@goal)
    assert_equal "Consola Digital Behringer X32", @goal.reload.title
    assert_equal 1500.0, @goal.target_amount
  end

  test "should deposit into goal" do
    assert_difference("GoalSavingsContribution.count") do
      post deposit_reinvestment_goal_url(@goal), params: {
        amount: 150.0,
        notes: "Ahorro de fin de semana"
      }
    end

    assert_response :redirect
    assert_equal 550.0, @goal.reload.saved_amount # 400 + 150
  end

  test "should quick purchase item" do
    item = @goal.shopping_items.create!(
      company: @company,
      name: "Case para consola",
      quantity: 1,
      unit_price: 200.0,
      priority: :medium
    )

    post quick_purchase_item_reinvestment_goal_url(@goal, item_id: item.id)
    assert_redirected_to add_to_inventory_shopping_item_path(item)
    assert item.reload.purchased?
  end

  test "should toggle goal status" do
    patch toggle_status_reinvestment_goal_url(@goal)
    assert_response :redirect
    assert_equal "completed", @goal.reload.status

    patch toggle_status_reinvestment_goal_url(@goal)
    assert_response :redirect
    assert_equal "active", @goal.reload.status
  end

  test "should destroy reinvestment_goal" do
    assert_difference("ReinvestmentGoal.count", -1) do
      delete reinvestment_goal_url(@goal)
    end

    assert_redirected_to reinvestment_goals_url
  end
end
