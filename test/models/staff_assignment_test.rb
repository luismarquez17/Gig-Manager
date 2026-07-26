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
end

