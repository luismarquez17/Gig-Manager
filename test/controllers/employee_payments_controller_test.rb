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
    assert_match "Saldo pendiente", response.body
    assert_match @worker.email, response.body
  end
end
