require "test_helper"

class PortalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @gig = gigs(:one)
  end

  test "should show public portal" do
    get public_portal_url(token: @gig.portal_token)
    assert_response :success
    assert_select "h1", text: /El Evento de/
  end

  test "should sign contract" do
    post sign_public_portal_contract_url(token: @gig.portal_token), params: { signature_name: "Luis Marquez" }, as: :json
    assert_response :success
    assert_equal true, JSON.parse(response.body)["success"]
    @gig.reload
    assert_equal true, @gig.contract_signed
    assert_equal "Luis Marquez", @gig.contract_signed_name
  end

  test "should not sign contract with empty name" do
    post sign_public_portal_contract_url(token: @gig.portal_token), params: { signature_name: "" }, as: :json
    assert_response :unprocessable_entity
    assert_equal false, JSON.parse(response.body)["success"]
  end

  test "should show worker profile when assigned to the gig" do
    get public_portal_worker_url(token: @gig.portal_token, worker_id: users(:one).id)
    assert_response :success
    assert_select "h1", text: users(:one).display_name
  end

  test "should not show worker profile when not assigned to the gig" do
    get public_portal_worker_url(token: @gig.portal_token, worker_id: users(:two).id)
    assert_response :not_found
  end
end
