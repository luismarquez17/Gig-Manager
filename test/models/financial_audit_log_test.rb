# frozen_string_literal: true

require "test_helper"

class FinancialAuditLogTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Test Audio & Show Co", slug: "test-audio-#{SecureRandom.hex(4)}")
    ActsAsTenant.current_tenant = @company
    Current.company = @company

    @user = User.create!(
      email: "leader-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: :leader,
      company: @company
    )
    Current.user = @user

    @client = Client.create!(name: "Boda Martinez", phone: "+15551234567", company: @company)
    @gig = Gig.create!(
      client: @client,
      date: Date.today + 5.days,
      amount: 1500.0,
      currency: "USD",
      company: @company
    )
  end

  test "auto generates sequential receipt number for gig payments" do
    payment1 = @gig.gig_payments.create!(
      amount: 500.0,
      date_paid: Date.today,
      payment_method: 'zelle'
    )
    assert_match(/REC-\d{4}-\d{5}/, payment1.receipt_number)

    payment2 = @gig.gig_payments.create!(
      amount: 300.0,
      date_paid: Date.today,
      payment_method: 'cash'
    )
    assert_match(/REC-\d{4}-\d{5}/, payment2.receipt_number)
    assert_not_equal payment1.receipt_number, payment2.receipt_number
  end

  test "financial audit log records creation of gig payment" do
    assert_difference -> { @company.financial_audit_logs.count }, 1 do
      @gig.gig_payments.create!(
        amount: 400.0,
        date_paid: Date.today,
        payment_method: 'bank_transfer'
      )
    end

    log = @company.financial_audit_logs.last
    assert_equal 'created', log.action
    assert_equal 'GigPayment', log.auditable_type
    assert_equal 400.0, log.amount_after.to_f
    assert_equal 0.0, log.amount_before.to_f
    assert_equal @user.id, log.user_id
  end

  test "financial audit log records update of gig payment amount" do
    payment = @gig.gig_payments.create!(
      amount: 400.0,
      date_paid: Date.today,
      payment_method: 'cash'
    )

    assert_difference -> { @company.financial_audit_logs.count }, 1 do
      payment.audit_reason = "Cliente pagó $100 adicionales en mano"
      payment.update!(amount: 500.0)
    end

    log = @company.financial_audit_logs.last
    assert_equal 'updated', log.action
    assert_equal 400.0, log.amount_before.to_f
    assert_equal 500.0, log.amount_after.to_f
    assert_includes log.reason, "Cliente pagó $100 adicionales en mano"
  end

  test "financial audit log records deletion of gig payment" do
    payment = @gig.gig_payments.create!(
      amount: 300.0,
      date_paid: Date.today,
      payment_method: 'cash'
    )

    assert_difference -> { @company.financial_audit_logs.count }, 1 do
      payment.audit_reason = "Eliminado por duplicación"
      payment.destroy
    end

    log = @company.financial_audit_logs.last
    assert_equal 'deleted', log.action
    assert_equal 300.0, log.amount_before.to_f
    assert_equal 0.0, log.amount_after.to_f
  end

  test "financial audit log records cash adjustments" do
    assert_difference -> { @company.financial_audit_logs.count }, 1 do
      @company.cash_adjustments.create!(
        amount: 250.0,
        adjustment_type: :deposit,
        date: Date.today,
        description: "Aporte de capital inicial del líder"
      )
    end

    log = @company.financial_audit_logs.last
    assert_equal 'created', log.action
    assert_equal 'CashAdjustment', log.auditable_type
    assert_equal 250.0, log.amount_after.to_f
  end

  test "humanized_changes formats friendly labels and values" do
    log = FinancialAuditLog.new(
      action: 'updated',
      details: {
        'changes' => {
          'status' => ['pending_approval', 'approved'],
          'receipt_number' => [nil, 'REC-2026-00014'],
          'payment_method' => ['cash', 'zelle'],
          'reported_by_client' => [false, true],
          'updated_at' => ['2026-10-06T19:00:00Z', '2026-10-06T19:35:18Z']
        }
      }
    )

    changes = log.humanized_changes
    # updated_at should be ignored
    assert_equal 4, changes.size

    status_change = changes.find { |c| c[:field] == 'Estado' }
    assert_not_nil status_change
    assert_equal '⏳ En Revisión', status_change[:before]
    assert_equal '✅ Aprobado', status_change[:after]

    receipt_change = changes.find { |c| c[:field] == 'Nº de Recibo / Folio' }
    assert_not_nil receipt_change
    assert_equal '—', receipt_change[:before]
    assert_equal 'REC-2026-00014', receipt_change[:after]

    pm_change = changes.find { |c| c[:field] == 'Método de Pago' }
    assert_not_nil pm_change
    assert_includes pm_change[:before], 'Efectivo'
    assert_includes pm_change[:after], 'Zelle'
  end
end
