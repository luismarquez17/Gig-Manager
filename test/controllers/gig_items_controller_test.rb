require "test_helper"

class GigItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @gig = gigs(:one)
    @item = items(:one)
    # Ensure item has valid status
    @item.update!(status: "Excelente", quantity: 1)
    @gig_item = gig_items(:one)
  end

  test "should report damage successfully" do
    assert_difference "MaintenanceRecord.count", 1 do
      post report_damage_gig_item_url(@gig_item), params: { notes: "Broken screen" }, as: :json
    end
    assert_response :success
    
    # Check that the inventory item was put in maintenance status
    ii = @item.inventory_items.first
    assert_equal "damaged", ii.status
    
    # Check that the item status is now Dañado (since the only copy is damaged)
    @item.reload
    assert_equal "Dañado", @item.status
  end

  test "should fail to report damage with empty notes" do
    assert_no_difference "MaintenanceRecord.count" do
      post report_damage_gig_item_url(@gig_item), params: { notes: "" }, as: :json
    end
    assert_response :unprocessable_entity
  end
end

