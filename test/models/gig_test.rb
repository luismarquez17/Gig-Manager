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

  test "disabling an upsell on a gig removes it from available_upsells for that gig" do
    gig = Gig.create!(amount: 500, client_email: "test@example.com", custom_upsells: { "smoke_machine" => { "disabled" => "1" } })
    upsells = gig.available_upsells
    refute_includes upsells.map { |u| u[:id] }, :smoke_machine
    assert_equal 3, upsells.size
  end

  test "adding a new global StandardUpsell automatically adds it to all gigs" do
    StandardUpsell.create!(key: "projector", title: "Proyector & Pantalla", emoji: "🎬", price: 50.0, active: true)

    gig = Gig.create!(amount: 500, client_email: "test@example.com")
    upsells = gig.available_upsells
    
    projector_upsell = upsells.find { |u| u[:id] == :projector }
    assert projector_upsell.present?
    assert_equal "Proyector & Pantalla", projector_upsell[:title]
    assert_equal 50.0, projector_upsell[:price]
    assert_equal "🎬", projector_upsell[:emoji]
  end

  test "payment_percentage and paid_in_full? calculation for unpaid, partial and full payments" do
    gig = Gig.create!(amount: 200, client_email: "client@example.com")
    
    # 1. Unpaid state
    assert_equal 0.0, gig.payment_percentage
    assert_not gig.paid_in_full?
    assert_equal :unpaid, gig.payment_status

    # 2. Partial payment
    gig.gig_payments.create!(amount: 100, date_paid: Date.today)
    gig.reload
    assert_equal 50.0, gig.payment_percentage
    assert_not gig.paid_in_full?
    assert_equal :partial, gig.payment_status

    # 3. Fully paid state
    gig.gig_payments.create!(amount: 100, date_paid: Date.today)
    gig.reload
    assert_equal 100.0, gig.payment_percentage
    assert gig.paid_in_full?
    assert_equal :paid, gig.payment_status
  end

  test "fund allocation scopes correctly filter unallocated vs fully allocated gigs" do
    company = companies(:one)
    
    # Gig 1: Has payments of $300, but no fund allocations at all
    gig1 = Gig.create!(company: company, amount: 500, client_email: "g1@example.com")
    gig1.gig_payments.create!(amount: 300, date_paid: Date.today)

    # Gig 2: Has payments of $400, and $200 allocated (partial allocation, $200 remaining unallocated)
    gig2 = Gig.create!(company: company, amount: 600, client_email: "g2@example.com")
    gig2.gig_payments.create!(amount: 400, date_paid: Date.today)
    gig2.fund_allocations.create!(fund_type: "payroll", amount: 200)

    # Gig 3: Has payments of $200, and $200 allocated (100% allocated)
    gig3 = Gig.create!(company: company, amount: 400, client_email: "g3@example.com")
    gig3.gig_payments.create!(amount: 200, date_paid: Date.today)
    gig3.fund_allocations.create!(fund_type: "payroll", amount: 200)

    # Gig 4: Has 0 payments
    gig4 = Gig.create!(company: company, amount: 300, client_email: "g4@example.com")

    # Scopes check:
    unallocated_gigs = Gig.with_unallocated_funds
    assert_includes unallocated_gigs, gig1
    assert_includes unallocated_gigs, gig2
    assert_not_includes unallocated_gigs, gig3
    assert_not_includes unallocated_gigs, gig4

    no_allocations_gigs = Gig.without_any_fund_allocations
    assert_includes no_allocations_gigs, gig1
    assert_not_includes no_allocations_gigs, gig2
    assert_not_includes no_allocations_gigs, gig3

    fully_allocated_gigs = Gig.fully_allocated_funds
    assert_includes fully_allocated_gigs, gig3
    assert_not_includes fully_allocated_gigs, gig1
    assert_not_includes fully_allocated_gigs, gig2
  end
end
