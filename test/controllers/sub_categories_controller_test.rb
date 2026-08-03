require "test_helper"

class SubCategoriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @leader = users(:one)
    @leader.update!(role: :leader)
    sign_in @leader
  end

  test "leader can create sub_category via HTML" do
    assert_difference("SubCategory.count", 1) do
      post sub_categories_path, params: { sub_category: { name: "PowerCON", category: "Cables" } }
    end
    assert_response :redirect
  end

  test "leader can create sub_category via JSON" do
    assert_difference("SubCategory.count", 1) do
      post sub_categories_path, params: { sub_category: { name: "EtherCON", category: "Cables" } }, as: :json
    end
    assert_response :success
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal "EtherCON", json["sub_category"]["name"]
  end
end
