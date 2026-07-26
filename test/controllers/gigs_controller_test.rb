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

  test "should add extra time upsell and extend end_time and increase gig amount" do
    initial_amount = @gig.amount.to_f
    @gig.update!(start_time: Time.zone.parse("20:00"), end_time: Time.zone.parse("23:00"))

    post add_upsell_gig_url(@gig), params: { upsell_key: 'extra_time', price: 40.0 }
    assert_redirected_to gig_url(@gig)

    @gig.reload
    assert_equal initial_amount + 40.0, @gig.amount.to_f
    assert_equal "00:00", @gig.end_time.strftime("%H:%M") # 23:00 + 1 hr = 00:00 midnight
    assert_includes @gig.details, "Adicional añadido"
  end
end
