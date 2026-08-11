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
    assert_select "h3", "Resumen general de pagos y deudas"
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

  test "should fail if payment exceeds total universal payroll remaining when using payroll fund" do
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
          payment_method: "Efectivo",
          funding_source: "payroll_fund"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match "excede el saldo disponible en el fondo de Nómina", flash[:alert]
  end

  test "should create employee payment using external capital even when payroll fund is zero" do
    FundAllocation.where(fund_type: "payroll").destroy_all

    assert_difference("EmployeePayment.count", 1) do
      post employee_payments_url, params: {
        employee_payment: {
          user_id: @worker.id,
          gig_id: @gig.id,
          amount: 300.0,
          currency: "USD",
          date_paid: Date.today,
          payment_method: "Transferencia",
          funding_source: "external_capital",
          external_source_name: "Dinero personal del leader"
        }
      }
    end

    payment = EmployeePayment.last
    assert_equal 300.0, payment.amount.to_f
    assert payment.from_external_capital?
    assert_equal "Dinero personal del leader", payment.external_source_name
    assert_equal 0, payment.fund_expenses.count
    assert_redirected_to employee_payments_path(user_id: @worker.id)
  end

  test "should update employee payment when expected_amount is empty string" do
    FundAllocation.create!(
      gig: @gig,
      fund_type: "payroll",
      amount: 500.0,
      currency: "USD"
    )

    payment = EmployeePayment.create!(
      user: @worker,
      gig: @gig,
      amount: 100.0,
      expected_amount: 150.0,
      currency: "USD",
      date_paid: Date.today,
      payment_method: "Efectivo"
    )

    patch employee_payment_url(payment), params: {
      employee_payment: {
        amount: 120.0,
        expected_amount: "",
        currency: "USD",
        date_paid: Date.today
      }
    }

    assert_redirected_to employee_payments_path(user_id: @worker.id)
    payment.reload
    assert_equal 120.0, payment.amount.to_f
    assert_equal 0.0, payment.expected_amount.to_f
  end

  test "worker can access new_worker_report and submit payment report in pending_approval state" do
    sign_out @leader
    sign_in @worker

    get new_worker_report_employee_payments_url(gig_id: @gig.id)
    assert_response :success
    assert_match "Reportar Pago Recibido", response.body

    assert_difference("EmployeePayment.count", 1) do
      post create_worker_report_employee_payments_url, params: {
        employee_payment: {
          gig_id: @gig.id,
          amount: 120.0,
          currency: "USD",
          date_paid: Date.today,
          payment_method: "Pago Móvil",
          notes: "Transferencia recibida por Luis"
        }
      }
    end

    payment = EmployeePayment.last
    assert_equal @worker.id, payment.user_id
    assert_equal @gig.id, payment.gig_id
    assert_equal 120.0, payment.amount.to_f
    assert payment.pending_approval?
    assert payment.reported_by_worker?
    assert_redirected_to my_payments_path
  end

  test "leader can approve worker payment report and consume payroll funds" do
    FundAllocation.create!(
      gig: @gig,
      fund_type: "payroll",
      amount: 300.0,
      currency: "USD"
    )

    pending_payment = EmployeePayment.create!(
      company: @leader.company,
      user: @worker,
      gig: @gig,
      amount: 150.0,
      currency: "USD",
      date_paid: Date.today,
      payment_method: "Efectivo",
      status: "pending_approval",
      reported_by_worker: true
    )

    assert pending_payment.pending_approval?
    assert_equal 0, pending_payment.fund_expenses.count

    # Leader logs in and approves
    post approve_employee_payment_url(pending_payment)
    assert_redirected_to employee_payments_path

    pending_payment.reload
    assert pending_payment.approved?
    assert_not_nil pending_payment.approved_at
    assert_equal 1, pending_payment.fund_expenses.count
    assert_equal 150.0, pending_payment.fund_expenses.first.amount.to_f
  end

  test "leader can reject worker payment report" do
    pending_payment = EmployeePayment.create!(
      company: @leader.company,
      user: @worker,
      gig: @gig,
      amount: 100.0,
      currency: "USD",
      date_paid: Date.today,
      status: "pending_approval",
      reported_by_worker: true
    )

    post reject_employee_payment_url(pending_payment), params: { rejection_reason: "Monto incorrecto" }
    assert_redirected_to employee_payments_path

    pending_payment.reload
    assert pending_payment.rejected?
    assert_equal "Monto incorrecto", pending_payment.rejection_reason
    assert_equal 0, pending_payment.fund_expenses.count
  end

  test "worker cannot approve or reject payments" do
    pending_payment = EmployeePayment.create!(
      company: @leader.company,
      user: @worker,
      gig: @gig,
      amount: 100.0,
      currency: "USD",
      date_paid: Date.today,
      status: "pending_approval",
      reported_by_worker: true
    )

    sign_out @leader
    sign_in @worker

    post approve_employee_payment_url(pending_payment)
    assert_redirected_to root_path

    pending_payment.reload
    assert pending_payment.pending_approval?
  end
end
