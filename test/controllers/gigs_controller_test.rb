require "test_helper"

class GigsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @gig = gigs(:one)
  end

  test "should get index" do
    get gigs_url
    assert_response :success
  end

  test "should get new" do
    get new_gig_url
    assert_response :success
  end

  test "should get show" do
    get gig_url(@gig)
    assert_response :success
  end

  test "should assign staff with agreed amount" do
    worker = users(:two)
    post assign_staff_gig_url(@gig), params: { staff_id: worker.id, agreed_amount: 150.0 }
    assert_redirected_to gig_url(@gig)

    assignment = @gig.staff_assignments.find_by(user_id: worker.id)
    assert_not_nil assignment
    assert_equal 150.0, assignment.agreed_amount.to_f
    assert_equal 150.0, assignment.pending_balance
  end

  test "should remove staff from gig" do
    worker = users(:two)
    @gig.staff_assignments.create!(user: worker, agreed_amount: 100.0)

    delete remove_staff_gig_url(@gig), params: { staff_id: worker.id }
    assert_redirected_to gig_url(@gig)

    assert_nil @gig.staff_assignments.find_by(user_id: worker.id)
  end
end
