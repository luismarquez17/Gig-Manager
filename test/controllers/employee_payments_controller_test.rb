require "test_helper"

class EmployeePaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @leader = users(:one)
    sign_in @leader
    @worker = users(:two)
    @gig = gigs(:one)
  end

  test "should get index with worker metrics" do
    EmployeePayment.create!(
      user: @worker,
      gig: @gig,
      amount: 150.0,
      expected_amount: 300.0,
      currency: "USD",
      date_paid: Date.today,
      payment_method: "Transferencia",
      notes: "Pago de prueba"
    )

    get employee_payments_url

    assert_response :success
    assert_select "h3", "Métricas de pagos a trabajadores"
    assert_match "Pendiente por pagar", response.body
    assert_match @worker.email, response.body
  end

  test "should create employee payment using universal payroll when gig has no direct payroll allocation" do
    gig_with_payroll = gigs(:one)
    gig_without_payroll = gigs(:two) rescue Gig.create!(amount: 500, currency: "USD", date: Date.today, client_email: "test@example.com")

    FundAllocation.create!(
      gig: gig_with_payroll,
      fund_type: "payroll",
      amount: 300.0,
      currency: "USD"
    )

    assert_difference("EmployeePayment.count", 1) do
      post employee_payments_url, params: {
        employee_payment: {
          user_id: @worker.id,
          gig_id: gig_without_payroll.id,
          amount: 200.0,
          currency: "USD",
          date_paid: Date.today,
          payment_method: "Efectivo"
        }
      }
    end

    payment = EmployeePayment.last
    assert_equal 200.0, payment.amount.to_f
    assert_equal 1, payment.fund_expenses.count
    assert_equal 200.0, payment.fund_expenses.first.amount.to_f
    assert_equal 100.0, FundAllocation.total_payroll_remaining
  end

  test "should create employee payment without gig using universal payroll" do
    FundAllocation.create!(
      gig: @gig,
      fund_type: "payroll",
      amount: 500.0,
      currency: "USD"
    )

    assert_difference("EmployeePayment.count", 1) do
      post employee_payments_url, params: {
        employee_payment: {
          user_id: @worker.id,
          gig_id: nil,
          amount: 150.0,
          currency: "USD",
          date_paid: Date.today,
          payment_method: "Transferencia"
        }
      }
    end

    payment = EmployeePayment.last
    assert_nil payment.gig_id
    assert_equal 150.0, payment.amount.to_f
    assert_equal 350.0, FundAllocation.total_payroll_remaining
  end

  test "should fail if payment exceeds total universal payroll remaining" do
    FundAllocation.create!(
      gig: @gig,
      fund_type: "payroll",
      amount: 100.0,
      currency: "USD"
    )

    assert_no_difference("EmployeePayment.count") do
      post employee_payments_url, params: {
        employee_payment: {
          user_id: @worker.id,
          gig_id: @gig.id,
          amount: 250.0,
          currency: "USD",
          date_paid: Date.today,
          payment_method: "Efectivo"
        }
      }
    end

    assert_redirected_to new_employee_payment_path(gig_id: @gig.id, user_id: @worker.id)
    follow_redirect!
    assert_match "excede el saldo disponible en el fondo universal de Nómina", flash[:alert]
  end
end
