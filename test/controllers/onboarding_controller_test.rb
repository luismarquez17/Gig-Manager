require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(name: "Grupo Vallenato Sol", monthly_fee: 40.0, slug: "vallenato-sol")
  end

  test "muestra formulario de registro si el token es válido" do
    get join_company_path(slug: @company.slug, token: @company.invitation_token)

    assert_response :success
    assert_select "h1", "Únete a #{@company.name}"
  end

  test "redirecciona si el token es inválido" do
    get join_company_path(slug: @company.slug, token: "token_invalido")

    assert_redirected_to root_path
    assert_equal "El enlace de invitación es inválido o ha caducado.", flash[:alert]
  end



  test "registra al primer usuario como Leader de la empresa" do
    assert_difference("User.count", 1) do
      post process_join_company_path(slug: @company.slug, token: @company.invitation_token), params: {
        user: {
          name: "Jefe Vallenato",
          email: "jefe_vallenato@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    new_user = User.find_by(email: "jefe_vallenato@example.com")
    assert_not_nil new_user
    assert_equal @company, new_user.company
    assert new_user.leader?
    assert_redirected_to root_path
  end
end
