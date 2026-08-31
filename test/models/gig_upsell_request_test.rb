require "test_helper"

class GigUpsellRequestTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Test Sound Company", slug: "test-sound-#{SecureRandom.hex(4)}")
    @gig = Gig.create!(
      amount: 400.0,
      client_email: "client@example.com",
      company: @company,
      start_time: Time.zone.parse("2026-09-01 20:00:00"),
      end_time: Time.zone.parse("2026-09-01 23:00:00")
    )
  end

  test "validates required fields" do
    req = GigUpsellRequest.new
    assert_not req.valid?
    assert_includes req.errors[:upsell_key], "can't be blank"
    assert_includes req.errors[:title], "can't be blank"
    assert_includes req.errors[:gig], "must exist"
  end

  test "creates pending request and sets company from gig" do
    req = @gig.gig_upsell_requests.create!(
      upsell_key: "smoke_machine",
      title: "Máquina de Humo",
      emoji: "💨",
      price: 30.0,
      currency: "USD"
    )

    assert_equal "pending", req.status
    assert_equal @company.id, req.company_id
    assert req.requested_at.present?
    assert req.pending?
  end

  test "approve! updates gig amount, details, and request status" do
    req = @gig.gig_upsell_requests.create!(
      upsell_key: "smoke_machine",
      title: "Máquina de Humo",
      emoji: "💨",
      price: 35.0,
      currency: "USD"
    )

    initial_amount = @gig.amount.to_f
    assert req.approve!

    req.reload
    @gig.reload

    assert_equal "approved", req.status
    assert req.processed_at.present?
    assert_equal initial_amount + 35.0, @gig.amount.to_f
    assert_includes @gig.details, "Adicional añadido"
    assert_includes @gig.details, "Máquina de Humo (+$35.00 USD)"
  end

  test "approve! extends end_time when upsell is extra_time" do
    req = @gig.gig_upsell_requests.create!(
      upsell_key: "extra_time",
      title: "1 Hora Extra de Música",
      emoji: "⏳",
      price: 60.0,
      currency: "USD"
    )

    assert req.approve!

    @gig.reload
    assert_equal "00:00", @gig.end_time.strftime("%H:%M")
    assert_equal 460.0, @gig.amount.to_f
  end

  test "reject! marks request as rejected without modifying gig amount or details" do
    req = @gig.gig_upsell_requests.create!(
      upsell_key: "sparkulars",
      title: "Sparkulars",
      emoji: "✨",
      price: 50.0,
      currency: "USD"
    )

    initial_amount = @gig.amount.to_f
    initial_details = @gig.details

    assert req.reject!
    req.reload
    @gig.reload

    assert_equal "rejected", req.status
    assert req.processed_at.present?
    assert_equal initial_amount, @gig.amount.to_f
    assert_equal initial_details, @gig.details
  end

  test "available_upsells reports request status" do
    req = @gig.gig_upsell_requests.create!(
      upsell_key: "smoke_machine",
      title: "Máquina de Humo",
      emoji: "💨",
      price: 30.0,
      currency: "USD"
    )

    upsells = @gig.available_upsells
    smoke = upsells.find { |u| u[:key] == "smoke_machine" }
    assert_not_nil smoke
    assert_equal "pending", smoke[:request_status]
    assert_equal req.id, smoke[:request_id]
  end
end
