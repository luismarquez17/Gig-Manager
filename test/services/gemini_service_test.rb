# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class GeminiServiceTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    @leader = users(:one)
    @service = GeminiService.new(company: @company, user: @leader)
    Current.company = @company
    Current.user = @leader
  end

  test "run_diagnostic returns status and cash balance" do
    diagnostic = @service.run_diagnostic
    assert diagnostic.key?(:cash_balance)
    assert diagnostic.key?(:diagnostic_items)
    assert_includes [true, false], diagnostic[:healthy]
  end

  test "record_cash_adjustment tool creates withdrawal and updates balance" do
    initial_balance = @service.send(:calculate_current_cash_balance)

    result = @service.send(
      :tool_record_cash_adjustment,
      {
        'adjustment_type' => 'withdrawal',
        'amount' => 45.0,
        'description' => 'Compra de cables XLR y agua'
      }
    )

    assert result[:success]
    assert_equal (initial_balance - 45.0).round(2), result[:new_balance]
    assert @company.cash_adjustments.where(description: 'Compra de cables XLR y agua').exists?
  end

  test "create_gig tool creates client, gig, advance payment and staff assignment" do
    result = @service.send(
      :tool_create_gig,
      {
        'client_name' => 'Alejandro Sanz Producciones',
        'date' => Date.tomorrow.to_s,
        'amount' => 1200.0,
        'advance_amount' => 300.0,
        'advance_payment_method' => 'cash',
        'location' => 'Hotel Eurobuilding',
        'staff_names' => ['Pepito Musico'],
        'notes' => 'Sonido acústico para cóctel'
      }
    )

    assert result[:success]
    gig = Gig.find(result[:gig_id])
    assert_equal 1200.0, gig.amount.to_f
    assert_equal 300.0, gig.total_received
    assert_equal 900.0, gig.remaining_amount
    assert_equal 1, gig.staff_assignments.count
  end

  test "get_worker_balances tool returns musicians with pending balances" do
    result = @service.send(:tool_get_worker_balances, {})
    assert result[:success]
    assert result.key?(:total_owed)
    assert result.key?(:card)
  end

  test "record_employee_payment tool creates payment and discounts from cash balance" do
    initial_balance = @service.send(:calculate_current_cash_balance)
    musician = users(:musician)

    result = @service.send(
      :tool_record_employee_payment,
      {
        'worker_name' => musician.name,
        'amount' => 50.0,
        'payment_method' => 'cash',
        'notes' => 'Pago por show de jazz'
      }
    )

    assert result[:success]
    assert_equal (initial_balance - 50.0).round(2), result[:new_balance]
    assert @company.employee_payments.where(user: musician, amount: 50.0).exists?
  end

  test "recent_post_gig_audits detects recently completed gigs with pending actions" do
    client = @company.clients.create!(name: 'Cliente Show Ayer', phone: '0000000000')
    gig = @company.gigs.create!(client: client, date: Date.yesterday, amount: 500.0, currency: 'USD')
    gig.staff_assignments.create!(user: users(:musician), agreed_amount: 100.0)

    audits = @service.recent_post_gig_audits
    assert audits.any?
    found = audits.find { |a| a[:gig_id] == gig.id }
    assert found.present?
    assert_equal 500.0, found[:client_remaining]
    assert found[:unpaid_staff].any?
  end

  test "chat returns graceful fallback response when API key is missing" do
    # Forzar que no haya API key
    GeminiService.stub :api_key_configured?, false do
      response = @service.chat("Hola, ¿cuánto dinero tengo en caja?")
      assert response[:reply].include?("Gig IA Copilot")
      assert response[:reply].include?("Saldo actual en Caja")
    end
  end

  test "chat handles 503 and transient errors gracefully without crashing" do
    @service.stub :execute_conversation, ->(_msg, _hist) { raise "Google Gemini API Error (503): High demand" } do
      response = @service.chat("Hola")
      assert_includes response[:reply], "saturación temporal"
      assert_includes response[:reply], "Saldo actual en Caja"
    end
  end

  test "tool_get_pending_approvals returns pending employee payments" do
    musician = users(:musician)
    pending_ep = @company.employee_payments.create!(
      user: musician,
      amount: 120.0,
      payment_method: 'Efectivo',
      status: 'pending_approval',
      date_paid: Date.current
    )

    result = @service.send(:tool_get_pending_approvals, {})
    assert result[:success]
    assert result[:pending_count] >= 1
    assert result[:message].include?(musician.name)
  end

  test "tool_approve_payment approves pending employee payment and creates confirmation notification" do
    musician = users(:musician)
    pending_ep = @company.employee_payments.create!(
      user: musician,
      amount: 80.0,
      payment_method: 'Efectivo',
      status: 'pending_approval',
      date_paid: Date.current
    )

    result = @service.send(:tool_approve_payment, { 'worker_or_client_name' => musician.name })
    assert result[:success]
    assert_equal 'approved', pending_ep.reload.status
    assert_includes result[:message], "Pago autorizado con éxito"
    assert AppNotification.where(recipient: musician, title: "✅ Pago Confirmado").exists?
  end

  test "tool_reject_payment rejects pending payment with custom reason" do
    musician = users(:musician)
    pending_ep = @company.employee_payments.create!(
      user: musician,
      amount: 60.0,
      payment_method: 'Zelle',
      status: 'pending_approval',
      date_paid: Date.current
    )

    result = @service.send(:tool_reject_payment, { 'worker_or_client_name' => musician.name, 'reason' => 'No asistió al evento' })
    assert result[:success]
    assert_equal 'rejected', pending_ep.reload.status
    assert_equal 'No asistió al evento', pending_ep.rejection_reason
    assert_includes result[:message], "fue rechazado"
  end
end
