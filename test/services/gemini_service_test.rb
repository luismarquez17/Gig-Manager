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

  test "tool_get_inventory_status returns inventory items, counts and card" do
    item = @company.items.create!(
      name: "Corneta JBL PRX815",
      category: "Cornetas",
      status: "Excelente",
      quantity: 2
    )

    result = @service.send(:tool_get_inventory_status, { 'search_query' => 'JBL' })
    assert result[:success]
    assert result[:total_listed] >= 1
    assert_includes result[:message], "Corneta JBL PRX815"
    assert_equal 'inventory_status', result[:card][:type]
  end

  test "tool_get_workshop_status and tool_record_maintenance_entry" do
    item = @company.items.create!(
      name: "Micrófono Shure SM58",
      category: "Microfonos",
      status: "Excelente",
      quantity: 1
    )

    # 1. Registrar ingreso a taller
    record_result = @service.send(
      :tool_record_maintenance_entry,
      {
        'item_name' => item.name,
        'description' => 'Malla abollada y cable interno desoldado',
        'cost' => 35.0,
        'status' => 'in_repair'
      }
    )

    assert record_result[:success]
    assert_includes record_result[:message], "Micrófono Shure SM58"
    assert_equal 'workshop_status', record_result[:card][:type]

    # 2. Consultar taller
    status_result = @service.send(:tool_get_workshop_status, { 'status_filter' => 'active' })
    assert status_result[:success]
    assert status_result[:active_repairs_count] >= 1
    assert_includes status_result[:message], "Malla abollada"
  end

  test "tool_get_packages_and_upsells returns standard upsells, preset budgets and kits" do
    StandardUpsell.seed_defaults!
    @company.preset_budgets.create!(
      title: "Show Acústico Íntimo",
      description: "Dúo acústico con guitarra y voz",
      price: 350.0,
      currency: "USD"
    )

    result = @service.send(:tool_get_packages_and_upsells, { 'filter' => 'all' })
    assert result[:success]
    assert result[:upsells_count] >= 1
    assert result[:packages_count] >= 1
    assert_includes result[:message], "Máquina de Humo"
    assert_includes result[:message], "Show Acústico Íntimo"
    assert_equal 'packages_upsells', result[:card][:type]
  end

  test "tool_get_monthly_comparative_report calculates exact revenue, expenses, payroll and deltas" do
    # Mes actual (target)
    client = @company.clients.create!(name: "Cliente Reporte", phone: "1111111111")
    gig_this_month = @company.gigs.create!(
      client: client,
      date: Date.current,
      amount: 1000.0,
      currency: "USD"
    )
    gig_this_month.gig_payments.create!(
      amount: 600.0,
      currency: "USD",
      date_paid: Date.current,
      status: "approved"
    )
    @company.employee_payments.create!(
      user: users(:musician),
      amount: 200.0,
      currency: "USD",
      date_paid: Date.current,
      status: "approved"
    )
    @company.cash_adjustments.create!(
      user: @leader,
      amount: 50.0,
      adjustment_type: :withdrawal,
      description: "Gasto de transporte actual",
      date: Date.current,
      status: "approved"
    )

    # Mes anterior (compare)
    prev_date = Date.current.prev_month
    gig_last_month = @company.gigs.create!(
      client: client,
      date: prev_date,
      amount: 800.0,
      currency: "USD"
    )
    gig_last_month.gig_payments.create!(
      amount: 400.0,
      currency: "USD",
      date_paid: prev_date,
      status: "approved"
    )
    @company.employee_payments.create!(
      user: users(:musician),
      amount: 150.0,
      currency: "USD",
      date_paid: prev_date,
      status: "approved"
    )

    result = @service.send(
      :tool_get_monthly_comparative_report,
      {
        'target_month' => Date.current.strftime('%Y-%m'),
        'compare_month' => prev_date.strftime('%Y-%m')
      }
    )

    assert result[:success]
    assert_equal 'comparative_report', result[:card][:type]
    metrics = result[:metrics]
    assert metrics[:target][:total_collected] >= 600.0
    assert metrics[:compare][:total_collected] >= 400.0
    assert metrics[:deltas][:revenue] > 0
    assert_includes result[:message], "Reporte Comparativo"
    assert_includes result[:message], "Recaudado en Shows"
    assert_includes result[:message], "Nómina pagada a Músicos"
  end

  test "tool_get_company_area_overview returns goals, shopping and quotes" do
    @company.reinvestment_goals.create!(
      title: "Nueva Consola Digital",
      target_amount: 1500.0,
      saved_amount: 500.0,
      status: "active"
    )
    @company.shopping_items.create!(
      name: "Cables Neutrik XLR 6m",
      priority: :high,
      quantity: 4,
      unit_price: 15.0,
      status: :pending
    )

    result = @service.send(:tool_get_company_area_overview, { 'area' => 'all' })
    assert result[:success]
    assert_includes result[:message], "Nueva Consola Digital"
    assert_includes result[:message], "Cables Neutrik XLR 6m"
  end
end
