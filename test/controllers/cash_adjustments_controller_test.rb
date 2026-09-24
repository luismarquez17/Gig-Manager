require "test_helper"

class CashAdjustmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @company = companies(:one)
    @cash_adjustment = cash_adjustments(:one)
    sign_in @user
  end

  test "should get index" do
    get cash_adjustments_url
    assert_response :success
    assert_select "h1", /Caja General/
  end

  test "should get index via /caja alias" do
    get cash_register_url
    assert_response :success
    assert_select "h1", /Caja General/
  end

  test "should get new" do
    get new_cash_adjustment_url
    assert_response :success
  end

  test "should create cash_adjustment" do
    assert_difference("CashAdjustment.count") do
      post cash_adjustments_url, params: {
        cash_adjustment: {
          amount: 120.50,
          currency: "USD",
          adjustment_type: "deposit",
          date: Date.today,
          description: "Aporte extraordinario"
        }
      }
    end

    assert_redirected_to cash_adjustments_url
  end

  test "should get edit" do
    get edit_cash_adjustment_url(@cash_adjustment)
    assert_response :success
  end

  test "should update cash_adjustment" do
    patch cash_adjustment_url(@cash_adjustment), params: {
      cash_adjustment: {
        amount: 300.00,
        description: "Aporte actualizado"
      }
    }
    assert_redirected_to cash_adjustments_url
    @cash_adjustment.reload
    assert_equal 300.0, @cash_adjustment.amount.to_f
  end

  test "should destroy cash_adjustment" do
    assert_difference("CashAdjustment.count", -1) do
      delete cash_adjustment_url(@cash_adjustment)
    end

    assert_redirected_to cash_adjustments_url
  end
end
