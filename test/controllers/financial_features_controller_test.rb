require "test_helper"

class FinancialFeaturesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @company = Company.create!(name: "Test Band Live", slug: "test-band-live-#{SecureRandom.hex(4)}")
    Current.company = @company

    @leader = User.create!(
      email: "leader-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: :leader,
      company: @company,
      name: "El Líder"
    )

    @musician = User.create!(
      email: "musician-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: :musician,
      company: @company,
      name: "Baterista"
    )

    @client = Client.create!(name: "Cliente Boda", phone: "+584149876543", email: "boda@example.com", company: @company)
    @gig = Gig.create!(amount: 800.0, date: Date.today, client: @client, company: @company)
    @assignment = StaffAssignment.create!(gig: @gig, user: @musician, agreed_amount: 150.0)

    sign_in @leader
  end

  test "GET closeout loads the event closeout wizard" do
    get closeout_gig_path(@gig)
    assert_response :success
    assert_includes response.body, "Cierre Rápido del Evento"
    assert_includes response.body, "Baterista"
    assert_includes response.body, "800.00"
  end

  test "POST process_closeout atomically liquidates client balance, musician pay, and fund deposit" do
    assert_difference -> { @gig.gig_payments.count } => 1,
                      -> { @company.employee_payments.count } => 1,
                      -> { @company.cash_adjustments.count } => 1 do
      post process_closeout_gig_path(@gig), params: {
        client_collected_amount: "800.00",
        client_payment_method: "cash",
        client_reference_number: "Efectivo al terminar show",
        worker_payments: {
          @musician.id.to_s => {
            pay: "1",
            amount: "150.00",
            payment_method: "Efectivo",
            notes: "Pago en mano en tarima"
          }
        },
        deposit_to_fund: "1",
        fund_amount: "650.00",
        fund_notes: "Remanente neto del show de Boda"
      }
    end

    assert_redirected_to gig_path(@gig)

    @gig.reload
    assert @gig.paid_in_full?
    assert_equal 800.0, @gig.total_received

    musician_payment = @company.employee_payments.last
    assert_equal @musician.id, musician_payment.user_id
    assert_equal 150.0, musician_payment.amount
    assert_equal "approved", musician_payment.status

    cash_adj = @company.cash_adjustments.last
    assert_equal 650.0, cash_adj.amount
    assert cash_adj.deposit?
  end

  test "POST void on gig payment revokes payment and leaves audit trace" do
    payment = @gig.gig_payments.create!(
      amount: 300.0,
      payment_method: "zelle",
      date_paid: Date.today,
      status: "approved"
    )

    post void_gig_payment_path(payment), params: { void_reason: "Comprobante falso o duplicado" }
    assert_response :redirect

    payment.reload
    assert payment.voided?
    assert_equal "Comprobante falso o duplicado", payment.void_reason
  end

  test "POST void on employee payment revokes payout" do
    payment = @company.employee_payments.create!(
      user: @musician,
      gig: @gig,
      amount: 100.0,
      payment_method: "Efectivo",
      date_paid: Date.today,
      status: "approved"
    )

    post void_employee_payment_path(payment), params: { void_reason: "Pago cancelado por inasistencia" }
    assert_response :redirect

    payment.reload
    assert payment.voided?
  end

  test "POST create_split records multiple payment methods" do
    assert_difference -> { @gig.gig_payments.count }, 2 do
      post create_split_gig_payments_path, params: {
        gig_id: @gig.id,
        date_paid: Date.today.to_s,
        split_payments: [
          { payment_method: "zelle", amount: "200.00", reference_number: "ZELLE-981" },
          { payment_method: "cash", amount: "100.00", reference_number: "Efectivo" }
        ]
      }
    end

    assert_redirected_to gig_path(@gig)
    @gig.reload
    assert_equal 300.0, @gig.total_received
  end

  test "GET receipt on employee payment renders official printable receipt" do
    payment = @company.employee_payments.create!(
      user: @musician,
      gig: @gig,
      amount: 150.0,
      payment_method: "Efectivo",
      date_paid: Date.today,
      status: "approved"
    )

    get receipt_employee_payment_path(payment)
    assert_response :success
    assert_includes response.body, "Comprobante de Nómina"
    assert_includes response.body, @musician.display_name
    assert_includes response.body, "150.00"
    assert_includes response.body, payment.receipt_display_number
  end
end
