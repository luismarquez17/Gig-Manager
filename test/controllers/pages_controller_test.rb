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

  test "should get availability dashboard" do
    get availability_dashboard_url
    assert_response :success
  end

  test "should get availability dashboard with conflicts" do
    item = items(:one)
    item.update!(status: "Excelente", quantity: 1)
    item.inventory_items.update_all(status: :damaged)
    
    gig = gigs(:one)
    gig.update!(date: Date.today)
    
    # Create gig_item requesting 2 copies, but 0 are available
    gig.gig_items.destroy_all
    gig.gig_items.create!(item: item, quantity: 2)
    
    get availability_dashboard_url
    assert_response :success
    assert_select "h4", "Conflictos detectados en el calendario"
  end
end
