require "test_helper"

class PortalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @gig = gigs(:one)
  end

  test "should show public portal" do
    get public_portal_url(token: @gig.portal_token)
    assert_response :success
    assert_select "h1", text: /El (Evento|Show) de/
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

  test "should request upsell from public portal" do
    assert_difference -> { @gig.gig_upsell_requests.count }, 1 do
      post request_public_portal_upsell_url(token: @gig.portal_token), params: {
        upsell_key: "smoke_machine",
        title: "Máquina de Humo",
        emoji: "💨",
        price: 30.0,
        currency: "USD"
      }, as: :json
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal "smoke_machine", json["request"]["key"]
    assert_equal "pending", json["request"]["status"]
  end

  test "should block worker profile when payroll module is disabled" do
    @gig.company.disable_module!(:payroll)
    get public_portal_worker_url(token: @gig.portal_token, worker_id: users(:one).id)
    assert_response :not_found
  end

  test "should block upsell request when clients_crm module is disabled" do
    @gig.company.disable_module!(:clients_crm)
    assert_no_difference -> { @gig.gig_upsell_requests.count } do
      post request_public_portal_upsell_url(token: @gig.portal_token), params: {
        upsell_key: "smoke_machine",
        title: "Máquina de Humo",
        emoji: "💨",
        price: 30.0,
        currency: "USD"
      }, as: :json
    end
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
  end

  test "should hide payroll/staff section in portal when payroll module is disabled" do
    @gig.company.disable_module!(:payroll)
    get public_portal_url(token: @gig.portal_token)
    assert_response :success
    assert_select "h2", text: /Tu (Músicos|Equipo de Trabajo)/, count: 0
  end

  test "should hide finances breakdown when finances module is disabled" do
    @gig.company.disable_module!(:finances)
    get public_portal_url(token: @gig.portal_token)
    assert_response :success
    assert_select ".finance-grid", count: 0
    assert_select ".progress-track", count: 0
  end

  test "should hide timeline section when gigs module is disabled" do
    @gig.company.disable_module!(:gigs)
    get public_portal_url(token: @gig.portal_token)
    assert_response :success
    assert_select "h2", text: /Cronograma y Agenda del Evento/, count: 0
  end

  test "should hide upsells section when clients_crm module is disabled" do
    @gig.company.disable_module!(:clients_crm)
    get public_portal_url(token: @gig.portal_token)
    assert_response :success
    assert_select "h2", text: /¿Quieres potenciar tu evento\?/, count: 0
  end
end
