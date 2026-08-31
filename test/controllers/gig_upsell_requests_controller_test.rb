require "test_helper"

class GigUpsellRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @gig = gigs(:one)
    @company = @gig.company
    @upsell_request = @gig.gig_upsell_requests.create!(
      upsell_key: "smoke_machine",
      title: "Máquina de Humo",
      emoji: "💨",
      price: 35.0,
      currency: "USD",
      status: "pending"
    )
  end

  test "should approve upsell request in 1 click and update gig amount" do
    initial_amount = @gig.amount.to_f
    post approve_gig_upsell_request_url(@upsell_request)
    assert_redirected_to gig_url(@gig)
    assert_equal "Adicional 'Máquina de Humo' aprobado con éxito (+ $35.00 USD). El precio acordado del evento se actualizó automáticamente.", flash[:notice]

    @upsell_request.reload
    @gig.reload

    assert_equal "approved", @upsell_request.status
    assert_equal initial_amount + 35.0, @gig.amount.to_f
    assert_includes @gig.details, "Máquina de Humo"
  end

  test "should reject upsell request in 1 click without modifying gig amount" do
    initial_amount = @gig.amount.to_f
    initial_details = @gig.details

    post reject_gig_upsell_request_url(@upsell_request)
    assert_redirected_to gig_url(@gig)
    assert_equal "Solicitud de adicional 'Máquina de Humo' rechazada. El precio acordado del evento no fue modificado.", flash[:notice]

    @upsell_request.reload
    @gig.reload

    assert_equal "rejected", @upsell_request.status
    assert_equal initial_amount, @gig.amount.to_f
    assert_equal initial_details, @gig.details
  end
end
