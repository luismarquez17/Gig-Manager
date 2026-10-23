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

  test "cliente con suscripcion pagada que cambia de plan recibe notificacion y se programa para el proximo mes" do
    # Simular empresa con suscripción activa y pagada en paquete full ($22/mes)
    @company.update!(
      subscription_status: "active",
      plan_tier: "full",
      trial_ends_at: 25.days.from_now
    )
    @company.update_modules!(AppModule.build_modules_hash(AppModule.modules_for_package('full')))
    assert @company.subscription_paid_and_active?

    sign_in @leader

    # Cliente cambia a paquete "banda" (más barato, $15/mes)
    post change_plan_subscriptions_path, params: {
      plan_tier: "banda",
      timing: "next_cycle",
      modules: {
        gigs: "1",
        payroll: "1",
        songs_repertoire: "1",
        finances: "1",
        inventory: "0",
        clients_crm: "0",
        shopping_list: "0"
      }
    }

    assert_redirected_to subscriptions_path(anchor: 'gigmanager-modules-section')
    follow_redirect!
    assert_response :success

    # Verificar mensaje exacto solicitado por el usuario
    assert_match(/Su plan ha sido cambiado exitosamente los cambios se aplicaran a partir del pr.+ximo mes disfrute de gig manager/i, flash[:notice])

    @company.reload
    # El cambio está programado para el próximo mes
    assert @company.has_scheduled_plan_change?
    assert_equal "banda", @company.scheduled_plan_tier
    assert_equal 15.00, @company.scheduled_monthly_fee

    # Su plan y acceso actual siguen intactos para el mes en curso
    assert_equal "full", @company.plan_tier
    assert @company.module_enabled?(:inventory)
    assert @company.module_enabled?(:clients_crm)
  end

  test "cliente en prueba antes de pagar puede cambiar de plan inmediatamente" do
    # Empresa en trialing sin pagar todavía
    @company.update!(
      subscription_status: "trialing",
      plan_tier: "banda"
    )

    sign_in @leader

    post change_plan_subscriptions_path, params: {
      plan_tier: "salon",
      timing: "immediate",
      modules: {
        gigs: "1",
        clients_crm: "1",
        finances: "1",
        payroll: "1"
      }
    }

    assert_redirected_to subscriptions_path(anchor: 'gigmanager-modules-section')
    follow_redirect!
    assert_response :success

    @company.reload
    assert_equal "salon", @company.effective_plan_tier
    assert_not @company.has_scheduled_plan_change?
  end

  test "cliente puede cancelar un cambio de plan programado" do
    @company.update!(
      subscription_status: "active",
      plan_tier: "banda",
      trial_ends_at: 20.days.from_now
    )
    @company.schedule_plan_change!("full", {}, @company.trial_ends_at)
    assert @company.has_scheduled_plan_change?

    sign_in @leader

    post cancel_scheduled_plan_subscriptions_path
    assert_redirected_to subscriptions_path(anchor: 'gigmanager-modules-section')
    follow_redirect!
    assert_response :success

    @company.reload
    assert_not @company.has_scheduled_plan_change?
    assert_match(/cancelado/i, flash[:notice])
  end

  test "al reportar y aprobar pago con cambio programado, se activa el nuevo plan y se limpia la programacion" do
    @company.update!(
      subscription_status: "active",
      plan_tier: "banda",
      trial_ends_at: 1.day.from_now
    )
    # Programa cambio a salón ($15/mes)
    @company.schedule_plan_change!("salon", {}, @company.trial_ends_at)
    assert @company.has_scheduled_plan_change?

    sign_in @leader

    # Reportar pago de renovación usando los datos del plan programado
    post report_payment_subscriptions_path, params: {
      plan_tier: "salon",
      payment_method: "zelle",
      reference_number: "ZEL-RENEW-111",
      notes: "Renovación mensual con cambio de plan a Salón"
    }

    assert_redirected_to subscriptions_path
    payment = SubscriptionPayment.last
    assert_equal "salon", payment.plan_tier
    assert_equal 15.00, payment.amount

    # Aprobación por Superadmin
    payment.approve!
    @company.reload

    # Se ha aplicado el nuevo plan y se ha limpiado la programación
    assert_equal "salon", @company.plan_tier
    assert_not @company.has_scheduled_plan_change?
    assert @company.module_enabled?(:clients_crm)
    assert @company.module_enabled?(:finances)
    assert @company.module_enabled?(:payroll)
  end
end
