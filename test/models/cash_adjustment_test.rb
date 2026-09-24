require "test_helper"

class CashAdjustmentTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    @user = users(:one)
  end

  test "should be valid with valid attributes" do
    adj = CashAdjustment.new(
      company: @company,
      user: @user,
      amount: 100.0,
      currency: "USD",
      adjustment_type: :deposit,
      date: Date.today,
      description: "Aporte para compras"
    )
    assert adj.valid?
  end

  test "should require amount greater than 0" do
    adj = CashAdjustment.new(
      company: @company,
      amount: 0,
      description: "Inválido",
      date: Date.today
    )
    assert_not adj.valid?
    assert adj.errors[:amount].present?
  end

  test "should require description and date" do
    adj = CashAdjustment.new(company: @company, amount: 50)
    assert_not adj.valid?
    assert adj.errors[:description].present?
    assert adj.errors[:date].present?
  end

  test "inflow? and outflow? methods work correctly" do
    deposit = cash_adjustments(:one)
    withdrawal = cash_adjustments(:two)

    assert deposit.inflow?
    assert_not deposit.outflow?
    assert_equal 250.0, deposit.signed_amount

    assert withdrawal.outflow?
    assert_not withdrawal.inflow?
    assert_equal(-50.0, withdrawal.signed_amount)
  end
end
