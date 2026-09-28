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
    assert_equal ["clients_crm", "finances", "payroll"], AppModule.modules_for_package("negocio")
    assert_equal 15.00, AppModule.package_info("banda")[:price]
    assert_equal 14.00, AppModule.package_info("negocio")[:price]
  end

  test "genera hash por defecto con todos los modulos habilitados" do
    default_hash = AppModule.default_hash
    AppModule.keys.each do |k|
      assert_equal true, default_hash[k]
    end
  end
end
