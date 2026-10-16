require "test_helper"

class ClientQuotesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @company = companies(:one)
    @user = users(:one)
    @preset = @company.preset_budgets.create!(
      title: "Paquete Boda VIP",
      description: "Sonido profesional y 2 horas de show",
      price: 500.0,
      currency: "USD"
    )
    @other_preset = @company.preset_budgets.create!(
      title: "Paquete Acústico",
      description: "Show acústico íntimo",
      price: 250.0,
      currency: "USD"
    )
    @open_quote = ClientQuote.create!(
      company: @company,
      amount: 0.0,
      currency: "USD",
      status: "pending"
    )
    @custom_quote = ClientQuote.create!(
      company: @company,
      preset_budget: @preset,
      package_name: @preset.title,
      client_name: "Cliente Prueba",
      client_phone: "04141234567",
      amount: 500.0,
      currency: "USD",
      details: "Incluye sonido profesional y 2 horas de show",
      status: "pending"
    )
  end

  test "public_show for uncustomized quote shows all preset packages and allows selection from scratch" do
    get public_client_quote_url(token: @open_quote.public_token)
    assert_response :success
    assert_select "h1", text: /Formulario de Presupuesto/
    # Shows the preset grid with all packages
    assert_select ".preset-grid", count: 1
    assert_select ".preset-card", minimum: 2
    # Amount is editable
    assert_select "input[type='number'][name='amount']", count: 1
  end

  test "public_show for customized quote shows ONLY the assigned package and hides other packages" do
    get public_client_quote_url(token: @custom_quote.public_token)
    assert_response :success
    assert_select "h1", text: /Presupuesto Personalizado/
    # Does NOT show the preset selection grid with multiple packages
    assert_select ".preset-grid", count: 0
    # Shows only the customized package card
    assert_select ".preset-card.selected", count: 1
    assert_select ".preset-card", count: 1
    assert_includes response.body, "Paquete Boda VIP"
    assert_not_includes response.body, "Paquete Acústico"
    # Amount is locked / hidden, not editable number input
    assert_select "input[type='hidden'][name='amount']", count: 1
    assert_select "input[type='number'][name='amount']", count: 0
    assert_includes response.body, "Monto Fijado"
  end

  test "should submit public quote successfully without CSRF token" do
    post submit_public_client_quote_url(token: @open_quote.public_token), params: {
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

    @open_quote.reload
    assert_equal "accepted", @open_quote.status
    assert_equal "Juan Perez", @open_quote.client_name
    assert_equal "04129876543", @open_quote.client_phone
    assert_equal 250.50, @open_quote.amount.to_f
    assert_equal 50.0, @open_quote.advance_amount.to_f
    assert_not_nil @open_quote.client_id
  end

  test "submitting customized quote preserves leader details and appends client notes" do
    post submit_public_client_quote_url(token: @custom_quote.public_token), params: {
      client_name: "Cliente Prueba",
      client_phone: "04141234567",
      client_notes: "Queremos vals tradicional y salsa al inicio"
    }

    assert_response :success
    @custom_quote.reload
    assert_equal "accepted", @custom_quote.status
    assert_equal 500.0, @custom_quote.amount.to_f
    assert_includes @custom_quote.details, "Incluye sonido profesional y 2 horas de show"
    assert_includes @custom_quote.details, "[Notas del Cliente]: Queremos vals tradicional y salsa al inicio"
  end

  test "should render secure access page when unauthenticated" do
    get access_public_client_quote_url(token: @custom_quote.public_token)
    assert_response :success
    assert_select "h2", text: /Acceso Seguro al Perfil de Cliente/
  end

  test "should setup password securely and sign in" do
    post setup_password_public_client_quote_url(token: @custom_quote.public_token), params: {
      phone: @custom_quote.client_phone,
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
    assert_select "h1", text: /Presupuestos de Clientes/
  end

  test "should get edit when authenticated as leader" do
    sign_in @user
    get edit_client_quote_url(@custom_quote)
    assert_response :success
    assert_select "h1", text: /Editar Presupuesto de Cliente/
  end

  test "should update client quote when authenticated as leader" do
    sign_in @user
    patch client_quote_url(@custom_quote), params: {
      client_quote: {
        amount: "650.00",
        details: "Show extendido a 3 horas",
        client_name: "Cliente VIP Actualizado"
      }
    }
    assert_redirected_to client_quotes_url
    @custom_quote.reload
    assert_equal 650.0, @custom_quote.amount.to_f
    assert_equal "Show extendido a 3 horas", @custom_quote.details
    assert_equal "Cliente VIP Actualizado", @custom_quote.client_name
    assert_equal true, @custom_quote.customized?
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
    created = ClientQuote.order(:created_at).last
    assert_equal true, created.customized?
  end

  test "should create client quote with custom service without foreign key violation" do
    sign_in @user
    assert_difference -> { ClientQuote.count }, 1 do
      post client_quotes_url, params: {
        client_quote: {
          preset_budget_id: "custom",
          package_name: "Servicio Personalizado",
          client_name: "Cliente Custom",
          client_phone: "04249998877",
          amount: "400",
          currency: "USD",
          details: "Detalles personalizados",
          customized: "1"
        }
      }
    end
    assert_redirected_to client_quotes_url
    created = ClientQuote.order(:created_at).last
    assert_nil created.preset_budget_id
    assert_equal "Servicio Personalizado", created.package_name
    assert_equal 400.0, created.amount.to_f
    assert_equal true, created.customized?
  end

  test "should create client quote with blank or zero preset_budget_id safely" do
    sign_in @user
    assert_difference -> { ClientQuote.count }, 1 do
      post client_quotes_url, params: {
        client_quote: {
          preset_budget_id: "0",
          client_name: "Cliente General",
          client_phone: "04249998877",
          amount: "0",
          currency: "USD",
          customized: "0"
        }
      }
    end
    assert_redirected_to client_quotes_url
    created = ClientQuote.order(:created_at).last
    assert_nil created.preset_budget_id
  end

  test "public_show should hide preset packages when clients_crm module is disabled and quote is not customized" do
    @company.disable_module!(:clients_crm)
    get public_client_quote_url(token: @open_quote.public_token)
    assert_response :success
    assert_select ".preset-card", count: 0
  end
end
