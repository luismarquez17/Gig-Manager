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
end
