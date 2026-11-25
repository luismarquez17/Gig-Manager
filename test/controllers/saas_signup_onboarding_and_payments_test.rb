# frozen_string_literal: true

require "test_helper"

class SaasSignupOnboardingAndPaymentsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @superadmin = User.create!(
      email: "superadmin_flow_#{SecureRandom.hex(4)}@test.com",
      password: "password123",
      role: :superadmin,
      name: "Admin Principal"
    )
  end

  test "nuevo lider que se registra con combo elegido inicia trial de 30 dias y va al wizard de 5 pasos" do
    assert_difference ["User.count", "Company.count"], 1 do
      post user_registration_path, params: {
        plan: "productora",
        modules: "gigs,inventory,clients_crm,payroll,shopping_list",
        company_name: "Sonido Norte Pro",
        user: {
          name: "Luis Productor",
          email: "luis_prod_#{SecureRandom.hex(4)}@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_redirected_to welcome_onboarding_path

    user = User.order(:id).last
    company = user.company
    assert user.leader?
    assert_equal "Sonido Norte Pro", company.name
    assert_equal "productora", company.plan_tier
    assert_equal "production_company", company.business_type
    assert company.trial_active?
    assert_equal false, company.onboarding_completed
    assert company.onboarding_pending?

    # Mientras no complete las 5 preguntas, el dashboard redirige al wizard /welcome
    get dashboard_path
    assert_redirected_to welcome_onboarding_path

    # El wizard /welcome carga correctamente
    get welcome_onboarding_path
    assert_response :success
    assert_includes response.body, "Pregunta 1 de 5"
  end

  test "completar las 5 preguntas configura automaticamente la empresa, pagos y catalogo inicial" do
    user = User.create!(
      name: "Carlos Director",
      email: "director_wizard_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      selected_plan_input: "banda"
    )
    company = user.company
    assert company.onboarding_pending?

    sign_in user

    patch welcome_onboarding_path, params: {
      onboarding: {
        business_type: "music_band",
        company_name: "Orquesta Fuego Latino",
        tagline: "El mejor show bailable en vivo",
        leader_name: "Carlos Director",
        leader_specialty: "Director y Trompeta",
        whatsapp_number: "04241112233",
        instagram_url: "@fuego_latino",
        contact_email: "contrataciones@fuegolatino.com",
        pago_movil_bank: "Bancamiga",
        pago_movil_id_number: "V-12345678",
        pago_movil_phone: "04241112233",
        zelle_email: "pagos@fuegolatino.com",
        zelle_holder_name: "Carlos Director",
        exchange_rate_mode: "auto_bcv",
        plan_tier: "banda",
        seed_starter_data: "1"
      }
    }

    assert_redirected_to authenticated_root_path
    company.reload
    user.reload

    assert company.onboarding_completed?
    assert_not company.onboarding_pending?
    assert_equal "Orquesta Fuego Latino", company.name
    assert_equal "orquesta-fuego-latino", company.slug
    assert_equal "El mejor show bailable en vivo", company.tagline
    assert_equal "04241112233", company.whatsapp_number
    assert_equal "https://instagram.com/fuego_latino", company.instagram_url
    assert_equal "Director y Trompeta", user.specialty
    assert company.pago_movil_enabled?
    assert_equal "Bancamiga", company.pago_movil_info["bank"]
    assert company.zelle_enabled?
    assert_equal "pagos@fuegolatino.com", company.zelle_info["email"]
    assert company.preset_budgets.count >= 2
    assert company.standard_upsells.count >= 2

    # Ya puede entrar al dashboard sin redirecciones
    get dashboard_path
    assert_response :success
  end

  test "omitir el onboarding desbloquea el panel inmediatamente" do
    user = User.create!(
      name: "Ana Salon",
      email: "ana_skip_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      selected_plan_input: "salon"
    )
    sign_in user

    post skip_welcome_onboarding_path
    assert_redirected_to authenticated_root_path
    assert user.company.reload.onboarding_completed?
  end

  test "leader reporta pago con foto del comprobante y superadmin lo ve, aprueba o rechaza en un clic" do
    leader = User.create!(
      name: "Pedro Banda",
      email: "pedro_pay_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      selected_plan_input: "banda"
    )
    leader.company.update!(onboarding_completed: true, name: "Banda Sonora Test", whatsapp_number: "04149998877")

    sign_in leader

    dummy_file = Rack::Test::UploadedFile.new(
      StringIO.new("\xFF\xD8\xFF\xE0fake-jpeg-receipt-data"),
      "image/jpeg",
      true,
      original_filename: "comprobante_pago.jpg"
    )

    assert_difference -> { SubscriptionPayment.count } => 1 do
      post report_payment_subscriptions_path, params: {
        plan_tier: "banda",
        amount: "15.00",
        payment_method: "pago_movil",
        reference_number: "PM-778899",
        notes: "Enviado desde Bancamiga",
        receipt_image: dummy_file
      }
    end

    assert_redirected_to subscriptions_path
    payment = SubscriptionPayment.last
    assert payment.pending?
    assert payment.voucher_attached?
    assert payment.receipt_image_base64.present?
    assert payment.receipt_image_base64.start_with?("data:image/jpeg;base64,")

    # Leader no puede consultar el endpoint JSON del superadmin
    get pending_summary_superadmin_subscription_payments_path, as: :json
    assert_response :redirect

    sign_out leader
    sign_in @superadmin

    # Superadmin consulta pending_summary en vivo
    get pending_summary_superadmin_subscription_payments_path, as: :json
    assert_response :success
    summary = JSON.parse(response.body)
    assert summary["pending_count"] >= 1
    assert_equal payment.id, summary["latest_id"]
    assert_equal true, summary["has_voucher"]
    assert_equal "PM-778899", summary["latest_reference"]

    # Superadmin ve el dashboard y la lista de pagos pendientes con la foto
    get superadmin_dashboard_path
    assert_response :success
    assert_includes response.body, "Banda Sonora Test"

    get superadmin_subscription_payments_path
    assert_response :success
    assert_includes response.body, "Banda Sonora Test"
    assert_includes response.body, "PM-778899"
    assert_includes response.body, "VER FOTO"

    # Aprobar en 1 clic
    post approve_superadmin_subscription_payment_path(payment)
    assert_redirected_to superadmin_subscription_payments_path

    payment.reload
    assert payment.approved?
    assert_equal @superadmin.id, payment.approved_by_id
    leader.company.reload
    assert leader.company.active_subscription?
    assert_equal 15.0, leader.company.monthly_fee.to_f
    assert AppNotification.where(company: leader.company).where("title LIKE ?", "%Aprobado%").exists?

    # Probar rechazo con motivo en un segundo reporte
    second_payment = leader.company.subscription_payments.create!(
      user: leader,
      plan_tier: "banda",
      amount: 15.0,
      payment_method: "zelle",
      reference_number: "ZEL-FAIL-1"
    )
    post reject_superadmin_subscription_payment_path(second_payment), params: { reason: "Referencia ilegible" }
    assert_redirected_to superadmin_subscription_payments_path
    second_payment.reload
    assert second_payment.rejected?
    assert_equal "Referencia ilegible", second_payment.rejection_reason
    assert AppNotification.where(company: leader.company).where("title LIKE ?", "%No Verificado%").exists?
  end

  test "vistas de inicio de sesion y registro muestran seguridad y combo seleccionado" do
    get new_user_session_path
    assert_response :success
    assert_includes response.body, "Bienvenido de nuevo"
    assert_includes response.body, "Acceso Seguro y Encriptado"

    get new_user_registration_path, params: { plan: "salon" }
    assert_response :success
    assert_includes response.body, "Paquete Salones"
    assert_includes response.body, "30 Días Gratis"
  end

  test "User.from_omniauth preserva combo y crea empresa lista para onboarding" do
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-uid-#{SecureRandom.hex(4)}",
      info: {
        email: "google_salon_#{SecureRandom.hex(4)}@example.com",
        name: "María Salón"
      }
    )

    user = User.from_omniauth(auth, plan: "salon", modules: "gigs,clients_crm,finances,payroll")
    assert user.persisted?
    assert user.leader?
    assert_equal "salon", user.company.plan_tier
    assert_equal "venue_academy", user.company.business_type
    assert user.company.onboarding_pending?
  end

  test "User.from_omniauth vincula cuenta existente sin duplicar usuario ni empresa" do
    existing = User.create!(
      name: "Pedro Existente",
      email: "pedro_existente_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      selected_plan_input: "banda"
    )
    existing.company.update!(onboarding_completed: true)

    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-uid-link-#{SecureRandom.hex(4)}",
      info: {
        email: existing.email.upcase,
        name: "Pedro Google"
      }
    )

    assert_no_difference ["User.count", "Company.count"] do
      linked = User.from_omniauth(auth)
      assert_equal existing.id, linked.id
      assert_equal "google_oauth2", linked.provider
      assert_equal auth.uid, linked.uid
    end
  end

  test "flujo completo de callback Google OAuth2 autentica y desactiva Turbo en el formulario" do
    get new_user_session_path
    assert_response :success
    assert_includes response.body, user_google_oauth2_omniauth_authorize_path
    assert_includes response.body, 'data-turbo="false"'

    previous_test_mode = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-uid-e2e-#{SecureRandom.hex(4)}",
      info: {
        email: "google_e2e_#{SecureRandom.hex(4)}@example.com",
        name: "Elena Google"
      }
    )

    assert_difference ["User.count", "Company.count"], 1 do
      post user_google_oauth2_omniauth_authorize_path
      assert_response :redirect
      follow_redirect!
    end

    assert_redirected_to welcome_onboarding_path
  ensure
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = previous_test_mode
  end
end
