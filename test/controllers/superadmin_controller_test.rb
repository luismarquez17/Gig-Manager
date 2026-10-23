require "test_helper"

class SuperadminControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(name: "Empresa Test", monthly_fee: 50.0)
    @superadmin = User.create!(
      email: "superadmin_test@example.com",
      password: "password123",
      role: :superadmin
    )
    @leader = User.create!(
      email: "leader_test@example.com",
      password: "password123",
      role: :leader,
      company: @company
    )
  end

  test "bloquea acceso a usuarios no superadmin" do
    sign_in @leader
    get superadmin_dashboard_path

    assert_redirected_to root_path
    assert_equal "Acceso denegado: Se requieren permisos de Superadmin.", flash[:alert]
  end



  test "permite acceso al superadmin" do
    sign_in @superadmin
    get superadmin_dashboard_path

    assert_response :success
    assert_select "h1", "Panel Superadmin"
  end

  test "superadmin puede acceder a la vista de nueva empresa" do
    sign_in @superadmin
    get new_superadmin_company_path
    assert_response :success
    assert_select "h1", /Registrar Nueva Empresa con Plan & Módulos/
  end

  test "superadmin puede acceder a la vista de editar empresa" do
    sign_in @superadmin
    get edit_superadmin_company_path(@company)
    assert_response :success
    assert_select "h1", /Editar Ajustes & Plan de/
  end

  test "superadmin puede crear una nueva empresa con plan preestablecido y modulos adicionales" do
    sign_in @superadmin
    assert_difference("Company.count", 1) do
      post superadmin_companies_path, params: {
        company: {
          name: "Mariachi Azteca VIP",
          plan_tier: "productora",
          monthly_fee: 18.0,
          currency: "USD",
          status: "active",
          subscription_status: "active",
          contact_email: "contacto@azteca.com",
          enabled_modules: {
            gigs: "1",
            inventory: "1",
            clients_crm: "1",
            payroll: "1",
            shopping_list: "1",
            finances: "1", # Módulo extra
            songs_repertoire: "0"
          }
        },
        leader_email: "jefe_azteca@example.com",
        leader_password: "password123",
        leader_name: "Jefe Azteca"
      }
    end

    new_company = Company.find_by(name: "Mariachi Azteca VIP")
    assert_not_nil new_company
    assert_equal "productora", new_company.effective_plan_tier
    assert_equal 18.0, new_company.monthly_fee.to_f
    assert new_company.module_enabled?(:gigs)
    assert new_company.module_enabled?(:inventory)
    assert new_company.module_enabled?(:finances) # Extra activado
    assert_not new_company.module_enabled?(:songs_repertoire)
    assert_equal "active", new_company.subscription_status
    assert_equal "jefe_azteca@example.com", new_company.primary_leader.email
  end

  test "superadmin ve metricas de clientes en dashboard" do
    # Crear cliente con usuario
    client_with_user = Client.create!(name: "Cliente Con Cuenta", phone: "04141112233", company: @company)
    User.create!(
      email: "cliente_activo@example.com",
      password: "password123",
      role: :client,
      client: client_with_user,
      company: @company
    )

    # Crear cliente sin usuario
    Client.create!(name: "Cliente Sin Cuenta", phone: "04149998877", company: @company)

    sign_in @superadmin
    get superadmin_dashboard_path

    assert_response :success
    assert_includes response.body, "Clientes en el Universo"
    assert_includes response.body, "con usuario"
  end

  test "superadmin puede acceder a la vista global de clientes y filtrar" do
    client_with_user = Client.create!(name: "Carlos Con Cuenta", phone: "04141112233", company: @company)
    User.create!(
      email: "carlos_cuenta@example.com",
      password: "password123",
      role: :client,
      client: client_with_user,
      company: @company
    )
    Client.create!(name: "Pedro Sin Cuenta", phone: "04149998877", company: @company)

    sign_in @superadmin
    get superadmin_clients_path
    assert_response :success
    assert_select "h1", /Clientes & Usuarios en Gig/
    assert_includes response.body, "Carlos Con Cuenta"
    assert_includes response.body, "Pedro Sin Cuenta"

    # Filtrar solo con usuario
    get superadmin_clients_path, params: { status: "with_user" }
    assert_response :success
    assert_includes response.body, "Carlos Con Cuenta"
    assert_not_includes response.body, "Pedro Sin Cuenta"

    # Filtrar solo sin usuario
    get superadmin_clients_path, params: { status: "without_user" }
    assert_response :success
    assert_not_includes response.body, "Carlos Con Cuenta"
    assert_includes response.body, "Pedro Sin Cuenta"
  end

  test "superadmin ve seccion de clientes en detalle de empresa" do
    client = Client.create!(name: "Ana Lopez", email: "ana@example.com", phone: "04145556677", company: @company)
    User.create!(
      email: "ana@example.com",
      password: "password123",
      role: :client,
      client: client,
      company: @company
    )

    sign_in @superadmin
    get superadmin_company_path(@company)

    assert_response :success
    assert_includes response.body, "Clientes & Cuentas de Usuario en Gig"
    assert_includes response.body, "Ana Lopez"
    assert_includes response.body, "Usuario Creado"
  end

  test "bloquea acceso a clientes del universo a usuarios no superadmin" do
    sign_in @leader
    get superadmin_clients_path

    assert_redirected_to root_path
    assert_equal "Acceso denegado: Se requieren permisos de Superadmin.", flash[:alert]
  end
end
