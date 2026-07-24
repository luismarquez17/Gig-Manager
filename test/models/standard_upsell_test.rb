require "test_helper"

class StandardUpsellTest < ActiveSupport::TestCase
  test "all_with_defaults seeds 4 default upsells if catalog is empty" do
    StandardUpsell.destroy_all
    catalog = StandardUpsell.all_with_defaults
    assert_equal 4, catalog.size
    assert_equal ["smoke_machine", "sparkulars", "subwoofer", "extra_time"], catalog.pluck(:key)
  end

  test "creating a new standard upsell auto-generates key if not provided" do
    upsell = StandardUpsell.create!(title: "Proyector & Pantalla Gigante", price: 60.0)
    assert_equal "proyector_pantalla_gigante", upsell.key
  end
end
