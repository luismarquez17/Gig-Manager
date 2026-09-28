require "test_helper"

class CompanyTest < ActiveSupport::TestCase
  test "crea empresa con slug y token generados automáticamente" do
    company = Company.create!(name: "Mariachi Sol de México", monthly_fee: 60.0)

    assert_not_nil company.slug
    assert_equal "mariachi-sol-de-mexico", company.slug
    assert_not_nil company.invitation_token
    assert company.active?
  end

  test "garantiza unicidad de slug" do
    Company.create!(name: "Empresa Test", slug: "empresa-test", monthly_fee: 0)
    duplicate = Company.new(name: "Empresa Test 2", slug: "empresa-test", monthly_fee: 0)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "recalcula token de invitación al solicitarlo" do
    company = Company.create!(name: "Empresa Token", monthly_fee: 0)
    old_token = company.invitation_token
    company.regenerate_token!

    assert_not_equal old_token, company.invitation_token
  end

  test "asigna 30 dias de prueba gratuita por defecto al crearse" do
    company = Company.create!(name: "Orquesta Nueva Era", monthly_fee: 0)

    assert_equal "trialing", company.subscription_status
    assert_not_nil company.trial_started_at
    assert_not_nil company.trial_ends_at
    assert company.trial_ends_at > 28.days.from_now
    assert company.trial_active?
    assert_not company.trial_expired?
    assert_equal 30, company.days_left_in_trial
    assert company.access_granted?
  end

  test "maneja expiracion de periodo de prueba correctamente" do
    company = Company.create!(
      name: "Banda Expirada",
      subscription_status: "trialing",
      trial_started_at: 35.days.ago,
      trial_ends_at: 5.days.ago,
      monthly_fee: 0
    )

    assert_not company.trial_active?
    assert company.trial_expired?
    assert_equal 0, company.days_left_in_trial
    assert_not company.access_granted?
  end

  test "concede acceso con suscripcion activa aunque el trial haya expirado" do
    company = Company.create!(
      name: "Banda Pagada",
      subscription_status: "active",
      trial_started_at: 40.days.ago,
      trial_ends_at: 10.days.ago,
      monthly_fee: 50.0
    )

    assert company.active_subscription?
    assert company.access_granted?
  end

  test "restringe acceso si la empresa esta suspendida" do
    company = Company.create!(
      name: "Banda Suspendida",
      status: :suspended,
      subscription_status: "active",
      monthly_fee: 50.0
    )

    assert_not company.access_granted?
  end

  test "gestiona modulos habilitados y deshabilitados correctamente" do
    company = Company.create!(name: "Grupo Modular", monthly_fee: 0)

    # Por defecto todos los modulos estan habilitados
    assert company.module_enabled?(:gigs)
    assert company.module_enabled?(:inventory)
    assert company.module_enabled?(:finances)
    assert company.module_enabled?(:payroll)
    assert company.module_enabled?(:clients_crm)

    # Deshabilitar modulo de inventario
    company.disable_module!(:inventory)
    assert_not company.module_enabled?(:inventory)
    assert company.module_enabled?(:gigs)

    # Habilitar nuevamente
    company.enable_module!(:inventory)
    assert company.module_enabled?(:inventory)

    # Actualizacion masiva de modulos
    company.update_modules!({
      "gigs" => true,
      "inventory" => false,
      "finances" => false,
      "payroll" => true,
      "clients_crm" => true
    })

    assert company.module_enabled?(:gigs)
    assert_not company.module_enabled?(:inventory)
    assert_not company.module_enabled?(:finances)
    assert company.module_enabled?(:payroll)
    assert company.module_enabled?(:clients_crm)
  end

  test "calcula pricing_breakdown y extra_modules correctamente para una empresa" do
    company = Company.create!(name: "Orquesta Latina", plan_tier: "banda", monthly_fee: 15.0)

    # Solo modulos de banda
    company.update_modules!({
      "gigs" => true,
      "payroll" => true,
      "songs_repertoire" => true,
      "finances" => true,
      "inventory" => false,
      "clients_crm" => false,
      "shopping_list" => false
    })

    assert_equal "banda", company.effective_plan_tier
    assert_equal 15.00, company.calculated_monthly_fee
    assert_equal false, company.has_extra_modules?

    # Agregar modulo extra (CRM + $3 USD)
    company.enable_module!(:clients_crm)
    assert_equal 18.00, company.calculated_monthly_fee
    assert_equal true, company.has_extra_modules?
    assert_equal 1, company.extra_modules.count
    assert_equal "clients_crm", company.extra_modules.first[:key]
  end
end
