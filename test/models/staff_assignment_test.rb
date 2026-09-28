require "test_helper"

class StaffAssignmentTest < ActiveSupport::TestCase
  test "assigning staff with agreed amount updates user agreed total and pending balance" do
    worker = users(:two)
    client = clients(:one)
    gig = Gig.create!(date: Date.today, amount: 100.0, client: client, currency: 'USD')

    assert_equal 0.0, worker.total_agreed_amount
    assert_equal 0.0, worker.pending_balance

    StaffAssignment.create!(user: worker, gig: gig, agreed_amount: 20.0)

    assert_equal 20.0, worker.total_agreed_amount
    assert_equal 20.0, worker.pending_balance

    EmployeePayment.create!(user: worker, gig: gig, amount: 10.0, expected_amount: 20.0, currency: 'USD', date_paid: Date.today)

    assert_equal 20.0, worker.total_agreed_amount
    assert_equal 10.0, worker.total_paid_amount
    assert_equal 10.0, worker.pending_balance
  end

  test "general payments without gig_id apply to assigned gigs balance" do
    worker = users(:two)
    client = clients(:one)
    gig = Gig.create!(date: Date.today, amount: 200.0, client: client, currency: 'USD')

    assignment = StaffAssignment.create!(user: worker, gig: gig, agreed_amount: 20.0)
    assert_equal 0.0, assignment.total_paid
    assert_equal 20.0, assignment.pending_balance

    # Make a general payment (gig_id: nil) of $15
    EmployeePayment.create!(
      user: worker,
      gig: nil,
      amount: 15.0,
      expected_amount: 0.0,
      currency: 'USD',
      date_paid: Date.today,
      status: 'approved'
    )

    assignment.clear_cached_breakdown!
    assert_equal 15.0, assignment.total_paid
    assert_equal 15.0, assignment.general_credit_applied
    assert_equal 5.0, assignment.pending_balance
    assert_equal 5.0, assignment.balance
  end
end

