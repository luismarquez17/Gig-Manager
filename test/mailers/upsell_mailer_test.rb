require "test_helper"

class UpsellMailerTest < ActionMailer::TestCase
  setup do
    @company = companies(:one)
    @leader = users(:one)
    @client = clients(:one)
    @gig = gigs(:one)
    @gig.update!(client: @client, company: @company)
    @upsell_request = @gig.gig_upsell_requests.create!(
      upsell_key: "smoke_machine",
      title: "Máquina de Humo",
      emoji: "💨",
      price: 35.0,
      currency: "USD",
      status: "pending"
    )
  end

  test "new_upsell_request email" do
    email = UpsellMailer.new_upsell_request(@upsell_request)
    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@leader.email], email.to
    assert_includes email.subject, "Solicitud de adicional"
    assert_includes email.subject, "Máquina de Humo"
  end

  test "upsell_approved email" do
    email = UpsellMailer.upsell_approved(@upsell_request)
    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@client.email], email.to
    assert_includes email.subject, "confirmado"
    assert_includes email.subject, "Máquina de Humo"
  end

  test "upsell_rejected email" do
    email = UpsellMailer.upsell_rejected(@upsell_request)
    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@client.email], email.to
    assert_includes email.subject, "no disponible"
    assert_includes email.subject, "Máquina de Humo"
  end
end
