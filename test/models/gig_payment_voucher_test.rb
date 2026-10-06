# frozen_string_literal: true

require "test_helper"

class GigPaymentVoucherTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Test Sound & Stage", slug: "sound-stage-#{SecureRandom.hex(4)}")
    ActsAsTenant.current_tenant = @company
    Current.company = @company

    @leader = User.create!(
      email: "leader-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: :leader,
      company: @company
    )
    Current.user = @leader

    @client = Client.create!(name: "Paco Festejo", phone: "+15559876543", company: @company)
    @client_user = User.create!(
      email: "paco-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: :client,
      client: @client,
      company: @company
    )

    @gig = Gig.create!(
      client: @client,
      date: Date.today + 3.days,
      amount: 1000.0,
      currency: "USD",
      company: @company
    )
  end

  test "client can report payment with pending_approval and voucher" do
    payment = @gig.gig_payments.create!(
      amount: 350.0,
      payment_method: 'zelle',
      date_paid: Date.today,
      reference_number: "ZELLE-CONF-88492",
      status: 'pending_approval',
      reported_by_client: true,
      payer_name: "Paco Festejo",
      notes: "Transferido desde mi cuenta Zelle"
    )

    assert payment.persisted?
    assert payment.pending_approval?
    assert_equal 350.0, payment.amount.to_f
    assert_equal 'ZELLE-CONF-88492', payment.reference_number
    # Unapproved payments should not count in total_received
    assert_equal 0.0, @gig.total_received
  end

  test "leader can approve client payment report and receipt is generated" do
    payment = @gig.gig_payments.create!(
      amount: 400.0,
      payment_method: 'bank_transfer',
      date_paid: Date.today,
      reference_number: "TRANSF-00129",
      status: 'pending_approval',
      reported_by_client: true,
      payer_name: "Paco Festejo"
    )

    assert_equal 0.0, @gig.total_received

    # Leader approves
    payment.status = 'approved'
    payment.approved_by = @leader
    payment.approved_at = Time.current
    payment.save!

    assert payment.approved?
    assert_match(/REC-\d{4}-\d{5}/, payment.receipt_number)
    assert_equal 400.0, @gig.total_received
  end

  test "leader can reject client payment report with reason" do
    payment = @gig.gig_payments.create!(
      amount: 500.0,
      payment_method: 'zelle',
      date_paid: Date.today,
      status: 'pending_approval',
      reported_by_client: true,
      payer_name: "Paco Festejo"
    )

    payment.status = 'rejected'
    payment.rejection_reason = "No se encontró el abono en la cuenta bancaria"
    payment.save!

    assert payment.rejected?
    assert_equal "No se encontró el abono en la cuenta bancaria", payment.rejection_reason
    assert_equal 0.0, @gig.total_received
  end
end
