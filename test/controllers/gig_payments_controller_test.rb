require "test_helper"

class GigPaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @leader = users(:one)
    @leader.update!(role: :leader)
    @company = @leader.company || companies(:one)
    @gig = gigs(:one)
    @gig.update!(company: @company, amount: 1000.0)
    sign_in @leader
  end

  test "should approve pending client payment" do
    payment = @gig.gig_payments.create!(
      amount: 100.0,
      payment_method: 'zelle',
      date_paid: Date.today,
      status: 'pending_approval',
      reported_by_client: true,
      reference_number: 'REF-12345'
    )

    assert_equal 'pending_approval', payment.status
    assert_nil payment.receipt_number

    post approve_gig_payment_url(payment)

    assert_redirected_to gig_url(@gig)
    assert_includes flash[:notice], "Abono aprobado exitosamente"

    payment.reload
    assert_equal 'approved', payment.status
    assert_equal @leader.id, payment.approved_by_id
    assert_not_nil payment.approved_at
    assert_match(/^REC-\d{4}-\d{5}$/, payment.receipt_number)
  end

  test "should reject pending client payment" do
    payment = @gig.gig_payments.create!(
      amount: 50.0,
      payment_method: 'bank_transfer',
      date_paid: Date.today,
      status: 'pending_approval',
      reported_by_client: true
    )

    post reject_gig_payment_url(payment), params: { rejection_reason: "Comprobante no coincide con el banco" }

    assert_redirected_to gig_url(@gig)
    assert_includes flash[:notice], "Abono rechazado correctamente"

    payment.reload
    assert_equal 'rejected', payment.status
    assert_equal "Comprobante no coincide con el banco", payment.rejection_reason
  end

  test "should get receipt for approved payment" do
    payment = @gig.gig_payments.create!(
      amount: 100.0,
      payment_method: 'cash',
      date_paid: Date.today,
      status: 'approved'
    )

    get receipt_gig_payment_url(payment)
    assert_response :success
  end

  test "client user should view official receipt for own gig payment" do
    client_user = users(:two)
    client_user.update!(role: :client, client_id: @gig.client_id)
    sign_in client_user

    payment = @gig.gig_payments.create!(
      amount: 120.0,
      payment_method: 'zelle',
      date_paid: Date.today,
      status: 'approved'
    )

    get receipt_gig_payment_url(payment)
    assert_response :success
    assert_includes response.body, "Comprobante Oficial de Pago"
  end

  test "client user cannot edit or delete payments" do
    client_user = users(:two)
    client_user.update!(role: :client, client_id: @gig.client_id)
    sign_in client_user

    payment = @gig.gig_payments.create!(
      amount: 120.0,
      payment_method: 'zelle',
      date_paid: Date.today,
      status: 'approved'
    )

    get edit_gig_payment_url(payment)
    assert_redirected_to root_url
    assert_equal "No tienes permiso para acceder a esta sección.", flash[:alert]
  end
end
