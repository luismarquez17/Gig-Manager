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
end
