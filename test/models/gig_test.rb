require "test_helper"

class GigTest < ActiveSupport::TestCase
  test "available_upsells returns all 4 upgrades when nothing is contracted" do
    gig = Gig.new(amount: 500, client_email: "test@example.com")
    upsells = gig.available_upsells
    assert_equal 4, upsells.size
    assert_equal [:smoke_machine, :sparkulars, :subwoofer, :extra_time], upsells.map { |u| u[:id] }
  end

  test "available_upsells excludes smoke machine if details contains humo" do
    gig = Gig.new(amount: 500, client_email: "test@example.com", details: "El paquete incluye luces y máquina de humo")
    upsells = gig.available_upsells
    refute_includes upsells.map { |u| u[:id] }, :smoke_machine
  end

  test "available_upsells excludes sparkulars if details contains spark" do
    gig = Gig.new(amount: 500, client_email: "test@example.com", details: "Incluye sparkulares de fuego frío")
    upsells = gig.available_upsells
    refute_includes upsells.map { |u| u[:id] }, :sparkulars
  end

  test "available_upsells excludes subwoofer if an item is a subwoofer" do
    gig = Gig.create!(amount: 500, client_email: "test@example.com")
    item = Item.create!(name: "Subwoofer activo 18 pulgadas", category: "sonido", status: "Excelente")
    gig.gig_items.create!(item: item, quantity: 1)

    upsells = gig.available_upsells
    refute_includes upsells.map { |u| u[:id] }, :subwoofer
  end

  test "available_upsells excludes extra time if details contains hora extra" do
    gig = Gig.new(amount: 500, client_email: "test@example.com", details: "Con 2 horas extra de música")
    upsells = gig.available_upsells
    refute_includes upsells.map { |u| u[:id] }, :extra_time
  end

  test "available_upsells returns empty when everything is contracted" do
    gig = Gig.create!(amount: 500, client_email: "test@example.com", details: "Luces con humo, chispas de spark, hora extra de show")
    sub_item = Item.create!(name: "Bajo activo", category: "sonido", status: "Excelente")
    gig.gig_items.create!(item: sub_item, quantity: 1)

    assert_empty gig.available_upsells
  end

  test "available_upsells respects custom upsells overridden by leader" do
    gig = Gig.new(amount: 500, client_email: "test@example.com", custom_upsells: {
      "sparkulars" => { "price" => "55.0", "description" => "Custom sparkulars description", "title" => "Sparkulas Increíbles" },
      "smoke_machine" => { "disabled" => "1" }
    })
    upsells = gig.available_upsells
    
    # Verify smoke_machine is excluded/disabled
    refute_includes upsells.map { |u| u[:id] }, :smoke_machine

    sparkulars_upsell = upsells.find { |u| u[:id] == :sparkulars }
    assert_equal "Sparkulas Increíbles", sparkulars_upsell[:title]
    assert_equal 55.0, sparkulars_upsell[:price]
    assert_equal "Custom sparkulars description", sparkulars_upsell[:description]
    assert_includes sparkulars_upsell[:whatsapp_message], "por $55 USD adicionales"
  end
end
