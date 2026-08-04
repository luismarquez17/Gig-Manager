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

  test "superadmin puede crear una nueva empresa" do
    sign_in @superadmin
    assert_difference("Company.count", 1) do
      post superadmin_companies_path, params: {
        company: {
          name: "Mariachi Azteca",
          monthly_fee: 75.0,
          currency: "USD",
          status: "active"
        },
        leader_email: "jefe_azteca@example.com",
        leader_password: "password123",
        leader_name: "Jefe Azteca"
      }
    end

    new_company = Company.find_by(name: "Mariachi Azteca")
    assert_not_nil new_company
    assert_equal 75.0, new_company.monthly_fee.to_f
    assert_equal "jefe_azteca@example.com", new_company.primary_leader.email
  end
end
