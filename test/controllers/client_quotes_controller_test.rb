require "test_helper"

class ClientQuotesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @company = companies(:one)
    @user = users(:one)
    @quote = ClientQuote.create!(
      company: @company,
      client_name: "Cliente Prueba",
      client_phone: "04141234567",
      amount: 150.0,
      currency: "USD",
      status: "pending"
    )
  end

  test "should get public_show" do
    get public_client_quote_url(token: @quote.public_token)
    assert_response :success
    assert_select "h1", text: /Formulario de Presupuesto/
  end

  test "should submit public quote successfully without CSRF token" do
    post submit_public_client_quote_url(token: @quote.public_token), params: {
      client_name: "Juan Perez",
      client_phone: "04129876543",
      client_email: "juan@example.com",
      event_type: "Boda",
      event_date: Date.today.to_s,
      event_location: "Salon Cristal",
      amount: "250,50",
      advance_amount: "50",
      currency: "USD",
      details: "Musica variada"
    }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]

    @quote.reload
    assert_equal "accepted", @quote.status
    assert_equal "Juan Perez", @quote.client_name
    assert_equal "04129876543", @quote.client_phone
    assert_equal 250.50, @quote.amount.to_f
    assert_equal 50.0, @quote.advance_amount.to_f
    assert_not_nil @quote.client_id
  end

  test "should render secure access page when unauthenticated" do
    get access_public_client_quote_url(token: @quote.public_token)
    assert_response :success
    assert_select "h2", text: /Acceso Seguro al Perfil de Cliente/
  end

  test "should setup password securely and sign in" do
    post setup_password_public_client_quote_url(token: @quote.public_token), params: {
      phone: @quote.client_phone,
      password: "password123",
      password_confirmation: "password123"
    }
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
  end

  test "should get index when authenticated as leader" do
    sign_in @user
    get client_quotes_url
    assert_response :success
  end

  test "should create client quote when authenticated" do
    sign_in @user
    assert_difference -> { ClientQuote.count }, 1 do
      post client_quotes_url, params: {
        client_quote: {
          client_name: "Nuevo Cliente",
          client_phone: "04241112233",
          amount: "300",
          currency: "USD"
        }
      }
    end
    assert_redirected_to client_quotes_url
  end
end
