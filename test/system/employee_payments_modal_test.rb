require "application_system_test_case"

class EmployeePaymentsModalTest < ApplicationSystemTestCase
  setup do
    @leader = users(:one) # Superadmin / Leader
    @worker = users(:two)
    @gig = gigs(:one)
    
    # Create past assignment so worker has past balance
    @gig.update!(date: 2.days.ago)
    StaffAssignment.create!(gig: @gig, user: @worker, agreed_amount: 150.0)
  end

  test "superadmin can click Editar deuda button, open modal and settle debt completely" do
    sign_in @leader
    visit employee_payments_path

    assert_text "Estado por trabajador"
    assert_text "✏️ Editar deuda"

    # Find the button for worker with debt and click it
    btn = find("button[data-worker-id='#{@worker.id}']")
    btn.click
    
    # Check browser logs have 0 errors
    logs = page.driver.browser.logs.get(:browser)
    assert_empty logs.select { |l| l.level == "SEVERE" }

    # Assert modal is visible
    assert_selector "#reset-balance-modal", visible: true
    assert_selector "#reset-balance-modal h2", text: "Editar deudas y saldos"
    assert_text "Trabajador: #{@worker.display_name}"

    # Select tab 'Dejar al día'
    click_button "✅ Dejar al día"

    # Save adjustment
    click_button "✅ Guardar ajuste"

    # Assert redirected and notice shown
    assert_text(/saldado completamente/i)
  end

  test "can adjust company debt to a specific custom amount" do
    sign_in @leader
    visit employee_payments_path

    btn = find("button[data-worker-id='#{@worker.id}']")
    btn.click

    assert_selector "#reset-balance-modal", visible: true
    click_button "⏳ Le debemos"

    fill_in "reset-company-debt-input", with: "50.00"
    click_button "✅ Guardar ajuste"

    assert_text(/Deuda empresa ajustada/i)
  end

  test "can adjust worker owes to a specific custom amount" do
    sign_in @leader
    visit employee_payments_path

    btn = find("button[data-worker-id='#{@worker.id}']")
    btn.click

    assert_selector "#reset-balance-modal", visible: true
    click_button "⚠️ Nos debe"

    fill_in "reset-worker-owes-input", with: "35.00"
    click_button "✅ Guardar ajuste"

    assert_text(/Nos debe/i)
  end

  test "can open and close modal using cancel button" do
    sign_in @leader
    visit employee_payments_path

    btn = find("button[data-worker-id='#{@worker.id}']")
    btn.click

    assert_selector "#reset-balance-modal", visible: true
    click_button "Cancelar"

    assert_no_selector "#reset-balance-modal.is-active"
  end
end
