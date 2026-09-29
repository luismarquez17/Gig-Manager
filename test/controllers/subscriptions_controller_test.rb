require "test_helper"

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @company = Company.create!(
      name: "Banda Test Leader",
      monthly_fee: 0.0,
      subscription_status: "trialing",
      trial_started_at: Time.current,
      trial_ends_at: 30.days.from_now
    )
    @leader = User.create!(
      email: "leader_sub_test@test.com",
      password: "password123",
      role: :leader,
      company: @company
    )
  end

  test "leader puede ver la vista de suscripciones" do
    sign_in @leader
    get subscriptions_path
    assert_response :success
  end

  test "leader al acceder a modules es redirigido a suscripciones unificadas" do
    sign_in @leader
    get company_modules_path
    assert_redirected_to subscriptions_path(anchor: 'gigmanager-modules-section')
    follow_redirect!
    assert_response :success
  end

  test "leader puede actualizar las preferencias de modulos" do
    sign_in @leader
    patch update_company_modules_path, params: {
      modules: {
        gigs: "1",
        inventory: "0",
        finances: "1",
        payroll: "0",
        clients_crm: "1"
      }
    }

    assert_redirected_to subscriptions_path(anchor: 'gigmanager-modules-section')
    follow_redirect!
    assert_response :success

    @company.reload
    assert @company.module_enabled?(:gigs)
    assert_not @company.module_enabled?(:inventory)
    assert @company.module_enabled?(:finances)
    assert_not @company.module_enabled?(:payroll)
  end

  test "redirecciona al dashboard cuando se intenta acceder por URL a un modulo desactivado" do
    sign_in @leader
    # Desactivamos el módulo de inventario
    @company.disable_module!(:inventory)

    get items_path
    assert_redirected_to root_path
    follow_redirect!
    assert_select "div, script", text: /no está activo en el plan/
  end

  test "leader puede reportar pago de paquete empresa y superadmin puede aprobarlo" do
    sign_in @leader
    assert_difference -> { SubscriptionPayment.count } => 1 do
      post report_payment_subscriptions_path, params: {
        plan_tier: "negocio",
        payment_method: "pago_movil",
        reference_number: "BCV-123456",
        notes: "Pago móvil Bancamiga tasa BCV"
      }
    end

    assert_redirected_to subscriptions_path
    follow_redirect!
    assert_response :success

    payment = SubscriptionPayment.last
    assert_equal "negocio", payment.plan_tier
    assert_equal 14.00, payment.amount
    assert_equal "BCV-123456", payment.reference_number
    assert_equal "pago_movil", payment.payment_method
    assert payment.pending?

    # Simular aprobación por Superadmin
    payment.approve!
    assert payment.approved?
    @company.reload
    assert_equal "negocio", @company.plan_tier
    assert @company.active_subscription?
    assert @company.module_enabled?(:clients_crm)
    assert @company.module_enabled?(:finances)
    assert @company.module_enabled?(:payroll)
  end

  test "leader puede reportar pago de plan personalizado conservando modulos especificos" do
    sign_in @leader
    # Configurar modulos custom (gigs, finances, inventory)
    @company.update_modules!(gigs: true, finances: true, inventory: true, payroll: false, clients_crm: false, shopping_list: false, songs_repertoire: false)

    assert_difference -> { SubscriptionPayment.count } => 1 do
      post report_payment_subscriptions_path, params: {
        plan_tier: "personalizado",
        amount: "13.00",
        payment_method: "zelle",
        reference_number: "ZEL-998877",
        notes: "Suscripción mensual: Plan Personalizado (3 módulos)"
      }
    end

    assert_redirected_to subscriptions_path
    follow_redirect!
    assert_response :success

    payment = SubscriptionPayment.last
    assert_equal "personalizado", payment.plan_tier
    assert_equal 13.00, payment.amount
    assert_equal "ZEL-998877", payment.reference_number
    assert payment.pending?

    payment.approve!
    assert payment.approved?
    @company.reload
    assert_equal "personalizado", @company.plan_tier
    assert_equal "Plan Personalizado (3 Módulos)", @company.plan_tier_name
    assert @company.active_subscription?
    assert @company.module_enabled?(:gigs)
    assert @company.module_enabled?(:finances)
    assert @company.module_enabled?(:inventory)
    assert_not @company.module_enabled?(:payroll)
  end
end
