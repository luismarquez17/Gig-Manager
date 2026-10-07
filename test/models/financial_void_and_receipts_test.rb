require "test_helper"

class FinancialVoidAndReceiptsTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Test Band Corp", slug: "test-band-corp-#{SecureRandom.hex(4)}")
    Current.company = @company

    @leader = User.create!(
      email: "leader-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: :leader,
      company: @company,
      name: "Band Leader"
    )

    @worker = User.create!(
      email: "worker-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: :musician,
      company: @company,
      name: "Guitarrista Pro",
      phone: "+584121234567"
    )

    @client = Client.create!(name: "Juan Cliente", phone: "+584141234567", email: "juan@example.com", company: @company)
    @gig = Gig.create!(amount: 1000.0, date: Date.today, client: @client, company: @company)
    @assignment = StaffAssignment.create!(gig: @gig, user: @worker, agreed_amount: 200.0)
  end

  test "GigPayment voiding updates status, logs to FinancialAuditLog and recalculates balances" do
    payment = @gig.gig_payments.create!(
      amount: 400.0,
      payment_method: 'zelle',
      date_paid: Date.today,
      status: 'approved'
    )

    assert payment.approved?
    assert_equal "approved", payment.status
    assert_equal 400.0, @gig.total_received

    # Perform void
    assert_difference("FinancialAuditLog.count", 1) do
      payment.void!("Error en el número de transferencia Zelle", @leader)
    end

    assert payment.voided?
    assert_equal "voided", payment.status
    assert_equal "Error en el número de transferencia Zelle", payment.void_reason
    assert_equal @leader.id, payment.voided_by_id

    # The gig's received total should now be 0.0
    @gig.reload
    assert_equal 0.0, @gig.total_received

    # Verify audit log
    audit_log = FinancialAuditLog.last
    assert_equal "voided", audit_log.action
    assert_equal "GigPayment", audit_log.auditable_type
    assert_equal payment.id, audit_log.auditable_id
  end

  test "EmployeePayment generates receipt number, supports voiding and WhatsApp text" do
    payment = @company.employee_payments.create!(
      user: @worker,
      gig: @gig,
      amount: 150.0,
      payment_method: 'Efectivo',
      date_paid: Date.today,
      status: 'approved',
      funding_source: 'payroll_fund'
    )

    assert payment.approved?
    assert payment.receipt_number.present?
    assert_match(/^EP-\d{4}-\d{5}$/, payment.receipt_number)

    # WhatsApp format verification
    wa_text = payment.whatsapp_receipt_text("https://example.com/receipt")
    assert_includes wa_text, "COMPROBANTE DE PAGO DE NÓMINA"
    assert_includes wa_text, @worker.display_name
    assert_includes wa_text, "$150.00 USD"
    assert_includes wa_text, "https://example.com/receipt"

    # Voiding
    payment.void!("Pago duplicado por error", @leader)
    assert payment.voided?
    assert_equal "voided", payment.status
    assert_equal "Pago duplicado por error", payment.void_reason
  end

  test "CashAdjustment supports voiding and affects inflow totals" do
    adj = @company.cash_adjustments.create!(
      user: @leader,
      amount: 500.0,
      currency: "USD",
      adjustment_type: :deposit,
      date: Date.today,
      description: "Aporte de capital inicial"
    )

    assert adj.approved?
    assert_equal 500.0, @company.cash_adjustments.inflows.sum(:amount)

    adj.void!("Cheque rebotado por el banco", @leader)
    assert adj.voided?
    assert_equal 0.0, @company.cash_adjustments.inflows.sum(:amount)
  end
end
