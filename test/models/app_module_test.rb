require "test_helper"

class AppModuleTest < ActiveSupport::TestCase
  test "retorna todos los modulos registrados" do
    assert_includes AppModule.keys, "gigs"
    assert_includes AppModule.keys, "inventory"
    assert_includes AppModule.keys, "finances"
    assert_includes AppModule.keys, "payroll"
    assert_includes AppModule.keys, "clients_crm"
    assert_includes AppModule.keys, "shopping_list"
    assert_includes AppModule.keys, "songs_repertoire"
  end

  test "encuentra modulo por clave" do
    mod = AppModule.find(:inventory)
    assert_not_nil mod
    assert_equal "Inventario, Kits & Taller QR", mod[:name]
    assert_equal "📦", mod[:icon]
    assert mod[:features].present?
  end

  test "devuelve nombre e icono por defecto para clave valida" do
    assert_equal "Eventos & Shows (Gigs)", AppModule.name_for("gigs")
    assert_equal "🎸", AppModule.icon_for("gigs")
  end

  test "obtiene configuraciones de paquetes preestablecidos" do
    assert_equal ["gigs", "payroll", "songs_repertoire", "finances"], AppModule.modules_for_package("banda")
    assert_equal ["gigs", "clients_crm", "finances", "payroll"], AppModule.modules_for_package("salon")
    assert_equal ["clients_crm", "finances", "payroll"], AppModule.modules_for_package("negocio")
    assert_equal 15.00, AppModule.package_info("banda")[:price]
    assert_equal 15.00, AppModule.package_info("salon")[:price]
    assert_equal 14.00, AppModule.package_info("negocio")[:price]
  end

  test "genera hash por defecto con todos los modulos habilitados" do
    default_hash = AppModule.default_hash
    AppModule.keys.each do |k|
      assert_equal true, default_hash[k]
    end
  end

  test "calcula precios base y modulos extra correctamente" do
    # Plan Banda ($15) con solo sus 4 modulos base
    banda_mods = ["gigs", "payroll", "songs_repertoire", "finances"]
    pricing_base = AppModule.calculate_pricing("banda", banda_mods)
    assert_equal 15.00, pricing_base[:base_price]
    assert_equal 0.0, pricing_base[:extra_cost]
    assert_equal 15.00, pricing_base[:total_price]
    assert_equal "Paquete Bandas & Orquestas", pricing_base[:custom_plan_name]
    assert_equal false, pricing_base[:has_extras]

    # Plan Banda con 1 modulo extra (ej. inventory -> + $3.00 USD)
    pricing_with_1_extra = AppModule.calculate_pricing("banda", banda_mods + ["inventory"])
    assert_equal 15.00, pricing_with_1_extra[:base_price]
    assert_equal 3.00, pricing_with_1_extra[:extra_cost]
    assert_equal 3.00, pricing_with_1_extra[:difference_amount]
    assert_equal 18.00, pricing_with_1_extra[:total_price]
    assert_includes pricing_with_1_extra[:custom_plan_name], "1 Adicional(es) (Personalizado)"
    assert_equal true, pricing_with_1_extra[:has_extras]

    # Plan Banda con 2 modulos extra (+ $6.00 USD) -> Sugiere Full Suite a $22
    pricing_with_2_extras = AppModule.calculate_pricing("banda", banda_mods + ["inventory", "clients_crm"])
    assert_equal 15.00, pricing_with_2_extras[:base_price]
    assert_equal 6.00, pricing_with_2_extras[:extra_cost]
    assert_equal 21.00, pricing_with_2_extras[:total_price]

    # Plan Banda con todos los 7 modulos (+ 3 extras = +$9) -> Topa en Full Suite $22.00
    pricing_with_3_extras = AppModule.calculate_pricing("banda", AppModule.keys)
    assert_equal 22.00, pricing_with_3_extras[:total_price]
    assert_equal true, pricing_with_3_extras[:suggests_full_suite]
  end
end
