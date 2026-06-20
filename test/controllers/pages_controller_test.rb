require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "should get dashboard" do
    get root_url
    assert_response :success
  end
end
