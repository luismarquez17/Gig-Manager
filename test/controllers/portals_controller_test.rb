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

  test "should report payment from public portal" do
    assert_difference -> { @gig.gig_payments.count }, 1 do
      post report_public_portal_payment_url(token: @gig.portal_token), params: {
        amount: "200.00",
        payment_method: "pago_movil",
        date_paid: Date.today,
        reference_number: "PM-12345",
        payer_name: "Cliente Invitado",
        notes: "Pago de apartado"
      }
    end

    assert_redirected_to public_portal_url(token: @gig.portal_token)
    assert_equal "✅ ¡Comprobante de abono enviado con éxito! El equipo organizador lo revisará y confirmará tu saldo a la brevedad.", flash[:notice]

    payment = @gig.gig_payments.last
    assert_equal 200.0, payment.amount
    assert_equal "pending_approval", payment.status
    assert_equal true, payment.reported_by_client
    assert_equal "PM-12345", payment.reference_number
    assert_equal "Cliente Invitado", payment.payer_name
  end

  test "should render portal with login and control call to action" do
    get public_portal_url(token: @gig.portal_token)
    assert_response :success
    assert_includes response.body, "Toma el Control Total de tu Evento"
    assert_includes response.body, "Iniciar Sesión / Controlar Evento"
  end

  test "should render portal access page" do
    get access_public_portal_url(token: @gig.portal_token)
    assert_response :success
    assert_select "h2", text: /Control Total de tu Evento/
  end

  test "should login existing client user from portal" do
    client_user = users(:client_user)
    post login_public_portal_url(token: @gig.portal_token), params: {
      email: client_user.email,
      password: "password123"
    }
    assert_redirected_to client_gig_path(@gig)
  end

  test "should reject invalid credentials from portal" do
    client_user = users(:client_user)
    post login_public_portal_url(token: @gig.portal_token), params: {
      email: client_user.email,
      password: "wrongpassword"
    }
    assert_redirected_to access_public_portal_url(token: @gig.portal_token)
    assert_equal "❌ Correo o contraseña incorrectos. Si aún no tienes contraseña, activa tu cuenta abajo.", flash[:alert]
  end

  test "should setup password and activate account for new client user" do
    new_email = "cliente_nuevo_portal@test.com"
    post setup_password_public_portal_url(token: @gig.portal_token), params: {
      email: new_email,
      password: "passwordSegura123",
      password_confirmation: "passwordSegura123"
    }
    assert_redirected_to client_gig_path(@gig)
    created_user = User.find_by(email: new_email)
    assert_not_nil created_user
    assert_equal "client", created_user.role
  end

  test "should reject setup password if passwords do not match" do
    post setup_password_public_portal_url(token: @gig.portal_token), params: {
      email: "cliente_fail@test.com",
      password: "password123",
      password_confirmation: "mismatched123"
    }
    assert_redirected_to access_public_portal_url(token: @gig.portal_token)
    assert_equal "❌ Las contraseñas no coinciden.", flash[:alert]
  end

  test "should redirect to client gig when client is already logged in and visits access" do
    sign_in users(:client_user)
    get access_public_portal_url(token: @gig.portal_token)
    assert_redirected_to client_gig_path(@gig)
  end
end

