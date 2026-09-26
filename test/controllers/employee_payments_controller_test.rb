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
    assert_select "h3", text: /Resumen general/
    assert_match "Deuda (shows asignados)", response.body
    assert_match @worker.email, response.body
  end

  test "should create employee payment using universal company fund when gig has no direct payroll allocation" do
    gig_with_payroll = gigs(:one)
    gig_without_payroll = gigs(:two) rescue Gig.create!(company: @leader.company, amount: 500, currency: "USD", date: Date.today, client_email: "test@example.com")

    assert_difference("EmployeePayment.count", 1) do
      post employee_payments_url, params: {
        employee_payment: {
          user_id: @worker.id,
          gig_id: gig_without_payroll.id,
          amount: 200.0,
          currency: "USD",
          date_paid: Date.today,
          payment_method: "Efectivo",
          funding_source: "payroll_fund"
        }
      }
    end

    payment = EmployeePayment.last
    assert_equal 200.0, payment.amount.to_f
    assert payment.from_payroll_fund?
    assert payment.approved?
  end

  test "should create employee payment without gig using universal company fund" do
    assert_difference("EmployeePayment.count", 1) do
      post employee_payments_url, params: {
        employee_payment: {
          user_id: @worker.id,
          gig_id: nil,
          amount: 150.0,
          currency: "USD",
          date_paid: Date.today,
          payment_method: "Transferencia",
          funding_source: "payroll_fund"
        }
      }
    end

    payment = EmployeePayment.last
    assert_nil payment.gig_id
    assert_equal 150.0, payment.amount.to_f
    assert payment.from_payroll_fund?
  end

  test "should create employee payment using external capital" do
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
    StaffAssignment.create!(gig: @gig, user: @worker, agreed_amount: 150.0)
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

  test "leader can approve worker payment report" do
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

    # Leader logs in and approves
    assert_difference -> { AppNotification.count }, 1 do
      post approve_employee_payment_url(pending_payment)
    end
    assert_redirected_to employee_payments_path

    pending_payment.reload
    assert pending_payment.approved?
    assert_not_nil pending_payment.approved_at

    notif = AppNotification.find_by(recipient: @worker, notification_type: 'payment_alert')
    assert_not_nil notif
    assert_includes @worker.app_notifications, notif
    assert_not_includes users(:musician).app_notifications, notif
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

    assert_difference -> { AppNotification.count }, 1 do
      post reject_employee_payment_url(pending_payment), params: { rejection_reason: "Monto incorrecto" }
    end
    assert_redirected_to employee_payments_path

    pending_payment.reload
    assert pending_payment.rejected?
    assert_equal "Monto incorrecto", pending_payment.rejection_reason
    assert_equal 0, pending_payment.fund_expenses.count

    notif = AppNotification.find_by(recipient: @worker, notification_type: 'urgent')
    assert_not_nil notif
    assert_includes @worker.app_notifications, notif
    assert_not_includes users(:musician).app_notifications, notif
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

  test "worker cannot report payment for gig they are not assigned to" do
    unassigned_gig = Gig.create!(company: @leader.company, amount: 500, date: Date.today, client_email: "unassigned@example.com")
    sign_out @leader
    sign_in @worker

    assert_no_difference("EmployeePayment.count") do
      post create_worker_report_employee_payments_url, params: {
        employee_payment: {
          gig_id: unassigned_gig.id,
          amount: 100.0,
          currency: "USD",
          date_paid: Date.today
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match "no estás asignado a este evento", response.body
  end

  test "worker cannot report amount greater than agreed amount for assigned gig" do
    StaffAssignment.create!(gig: @gig, user: @worker, agreed_amount: 100.0)
    sign_out @leader
    sign_in @worker

    assert_no_difference("EmployeePayment.count") do
      post create_worker_report_employee_payments_url, params: {
        employee_payment: {
          gig_id: @gig.id,
          amount: 500.0,
          currency: "USD",
          date_paid: Date.today
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match "no puede exceder el monto acordado", response.body
  end

  test "worker cannot submit duplicate report for gig that already has pending approval report" do
    StaffAssignment.create!(gig: @gig, user: @worker, agreed_amount: 150.0)
    EmployeePayment.create!(
      company: @leader.company,
      user: @worker,
      gig: @gig,
      amount: 100.0,
      status: "pending_approval",
      reported_by_worker: true
    )

    sign_out @leader
    sign_in @worker

    assert_no_difference("EmployeePayment.count") do
      post create_worker_report_employee_payments_url, params: {
        employee_payment: {
          gig_id: @gig.id,
          amount: 50.0,
          currency: "USD",
          date_paid: Date.today
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match "Ya tienes un reporte de pago en revisión", response.body
  end

  test "leader approval approves payment with payroll_fund successfully" do
    pending_payment = EmployeePayment.create!(
      company: @leader.company,
      user: @worker,
      gig: @gig,
      amount: 200.0,
      currency: "USD",
      date_paid: Date.today,
      status: "pending_approval",
      reported_by_worker: true,
      funding_source: "payroll_fund"
    )

    # Leader approves
    post approve_employee_payment_url(pending_payment)
    assert_redirected_to employee_payments_path

    pending_payment.reload
    assert pending_payment.approved?
    assert pending_payment.from_payroll_fund?
  end

  test "leader creating payment automatically succeeds and reduces worker debt" do
    past_gig = Gig.create!(company: @leader.company, amount: 500, date: 2.days.ago, client_email: "past@example.com")
    StaffAssignment.create!(gig: past_gig, user: @worker, agreed_amount: 100.0)

    # Deuda inicial antes del pago
    metrics_before = WorkerBalanceService.build_metrics_for_company(@leader.company)
    worker_metric_before = metrics_before.find { |m| m[:worker].id == @worker.id }
    assert_equal 100.0, worker_metric_before[:past_balance]

    # Crear pago de 60
    assert_difference("EmployeePayment.count", 1) do
      post employee_payments_url, params: {
        employee_payment: {
          user_id: @worker.id,
          gig_id: past_gig.id,
          amount: "60,00",
          currency: "USD",
          date_paid: Date.today,
          payment_method: "Efectivo",
          funding_source: "payroll_fund"
        }
      }
    end

    assert_redirected_to employee_payments_path(user_id: @worker.id)
    payment = EmployeePayment.last
    assert_equal 60.0, payment.amount.to_f
    assert payment.approved?
    assert payment.from_payroll_fund?

    # Verificar que la deuda del trabajador disminuyó a 40.00
    metrics_after = WorkerBalanceService.build_metrics_for_company(@leader.company)
    worker_metric_after = metrics_after.find { |m| m[:worker].id == @worker.id }
    assert_equal 40.0, worker_metric_after[:past_balance]
  end

  test "reset_balance can adjust company debt down to zero" do
    past_gig = Gig.create!(company: @leader.company, amount: 500, date: 2.days.ago, client_email: "past@example.com")
    StaffAssignment.create!(gig: past_gig, user: @worker, agreed_amount: 150.0)

    post reset_balance_employee_payments_url, params: {
      user_id: @worker.id,
      adjustment_mode: "company_debt",
      company_debt: "0.00"
    }

    assert_redirected_to employee_payments_path(user_id: @worker.id)
    metrics = WorkerBalanceService.build_metrics_for_company(@leader.company)
    worker_metric = metrics.find { |m| m[:worker].id == @worker.id }
    assert_equal 0.0, worker_metric[:past_balance]
    assert_equal 0.0, worker_metric[:overpaid]
  end

  test "reset_balance can adjust what worker owes" do
    # Worker starts at 0 balance
    post reset_balance_employee_payments_url, params: {
      user_id: @worker.id,
      adjustment_mode: "worker_owes",
      worker_owes: "75.00"
    }

    assert_redirected_to employee_payments_path(user_id: @worker.id)
    metrics = WorkerBalanceService.build_metrics_for_company(@leader.company)
    worker_metric = metrics.find { |m| m[:worker].id == @worker.id }
    assert_equal 0.0, worker_metric[:past_balance]
    assert_equal 75.0, worker_metric[:overpaid]

    # Now forgive / reset what worker owes to 0
    post reset_balance_employee_payments_url, params: {
      user_id: @worker.id,
      adjustment_mode: "worker_owes",
      worker_owes: "0.00"
    }

    assert_redirected_to employee_payments_path(user_id: @worker.id)
    metrics_after = WorkerBalanceService.build_metrics_for_company(@leader.company)
    worker_metric_after = metrics_after.find { |m| m[:worker].id == @worker.id }
    assert_equal 0.0, worker_metric_after[:past_balance]
    assert_equal 0.0, worker_metric_after[:overpaid]
  end

  test "reset_balance with settle_all leaves worker completely settled" do
    past_gig = Gig.create!(company: @leader.company, amount: 500, date: 2.days.ago, client_email: "past@example.com")
    StaffAssignment.create!(gig: past_gig, user: @worker, agreed_amount: 80.0)

    post reset_balance_employee_payments_url, params: {
      user_id: @worker.id,
      adjustment_mode: "settle_all"
    }

    assert_redirected_to employee_payments_path(user_id: @worker.id)
    metrics = WorkerBalanceService.build_metrics_for_company(@leader.company)
    worker_metric = metrics.find { |m| m[:worker].id == @worker.id }
    assert_equal 0.0, worker_metric[:past_balance]
    assert_equal 0.0, worker_metric[:overpaid]
  end
end
