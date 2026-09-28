require "test_helper"

class LandingControllerTest < ActionDispatch::IntegrationTest
  test "should get landing page when unauthenticated" do
    get public_landing_url
    assert_response :success
    assert_select "h1", /El control total de tus/
    assert_select "#modulos"
    assert_select "#calculadora"
    assert_select "#faq"
  end

  test "root url should render landing page when not logged in" do
    get root_url
    assert_response :success
    assert_select "h1", /El control total de tus/
  end

  test "should redirect to dashboard when authenticated user visits landing" do
    sign_in users(:one)
    get public_landing_url
    assert_redirected_to authenticated_root_url
  end

  test "should get sign up page from landing" do
    get new_user_registration_url(modules: "gigs,inventory,finances")
    assert_response :success
    assert_select "h2", "Crea tu Agrupación"
    assert_select "input[name='modules'][value='gigs,inventory,finances']"
  end

  test "should register new user and company with 30-day trial and custom modules" do
    assert_difference -> { User.count } => 1, -> { Company.count } => 1 do
      post user_registration_url, params: {
        user: {
          name: "Nuevo Director",
          email: "nuevo_director_#{SecureRandom.hex(4)}@test.com",
          password: "password123",
          password_confirmation: "password123",
          company_name_input: "Orquesta Sinfonía Nueva",
          selected_modules_input: "gigs,finances,payroll"
        }
      }
    end

    assert_redirected_to root_url
    created_user = User.find_by(email: session_user_email || User.last.email)
    assert_not_nil created_user
    assert_equal "Orquesta Sinfonía Nueva", created_user.company.name
    assert created_user.company.trial_active?
    assert created_user.company.module_enabled?(:gigs)
    assert created_user.company.module_enabled?(:finances)
    assert created_user.company.module_enabled?(:payroll)
    assert_not created_user.company.module_enabled?(:inventory)
  end

  private

  def session_user_email
    User.last.email
  end
end
