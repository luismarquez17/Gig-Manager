require "test_helper"

class MaintenanceRecordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @item = items(:one)
    @item.update!(status: "Excelente", quantity: 2) # ensure 2 available units
  end

  test "should get new" do
    get new_maintenance_record_url
    assert_response :success
  end

  test "should report damage for a new product" do
    assert_difference "Item.count", 1 do
      assert_difference "MaintenanceRecord.count", 2 do
        post maintenance_records_url, params: {
          mode: "new",
          name: "Nuevo Cable XLR",
          category: "Cables",
          sub_category_cable: "Micrófono (XLR)",
          quantity: 2,
          initial_status: "pending",
          description: "Mal cortados"
        }
      end
    end
    assert_redirected_to maintenance_records_path
    
    new_item = Item.find_by(name: "Nuevo Cable XLR")
    assert_equal 2, new_item.quantity
    assert_equal "Dañado", new_item.status
    assert_equal 2, new_item.inventory_items.where(status: :damaged).count
  end

  test "should report loss for a new product immediately" do
    assert_difference "Item.count", 1 do
      assert_difference "MaintenanceRecord.count", 1 do
        post maintenance_records_url, params: {
          mode: "new",
          name: "Nuevo Cable HDMI",
          category: "Cables",
          sub_category_cable: "HDMI",
          quantity: 1,
          initial_status: "discarded",
          description: "Quemado en show"
        }
      end
    end
    assert_redirected_to maintenance_records_path
    
    new_item = Item.find_by(name: "Nuevo Cable HDMI")
    assert_equal 0, new_item.quantity
    assert_equal "Excelente", new_item.status # since 0 copies remain, falls back to Excelente
    assert_equal 0, new_item.inventory_items.count
  end

  test "should mark existing units as damaged" do
    assert_no_difference "Item.count" do
      assert_difference "MaintenanceRecord.count", 1 do
        post maintenance_records_url, params: {
          mode: "existing",
          item_id: @item.id,
          existing_action: "mark_damaged",
          quantity: 1,
          initial_status: "pending",
          description: "Roto"
        }
      end
    end
    assert_redirected_to maintenance_records_path
    @item.reload
    assert_equal 2, @item.quantity
    assert_equal 1, @item.inventory_items.where(status: :damaged).count
    assert_equal 1, @item.inventory_items.where(status: :available).count
  end

  test "should mark existing units as discarded" do
    assert_no_difference "Item.count" do
      assert_difference "MaintenanceRecord.count", 1 do
        post maintenance_records_url, params: {
          mode: "existing",
          item_id: @item.id,
          existing_action: "mark_damaged",
          quantity: 1,
          initial_status: "discarded",
          description: "Pérdida total"
        }
      end
    end
    assert_redirected_to maintenance_records_path
    @item.reload
    assert_equal 1, @item.quantity
    assert_equal 1, @item.inventory_items.count
  end

  test "should add extra damaged units of existing product" do
    assert_no_difference "Item.count" do
      assert_difference "MaintenanceRecord.count", 2 do
        post maintenance_records_url, params: {
          mode: "existing",
          item_id: @item.id,
          existing_action: "add_extra",
          quantity: 2,
          initial_status: "pending",
          description: "Adicionales defectuosos"
        }
      end
    end
    assert_redirected_to maintenance_records_path
    @item.reload
    assert_equal 4, @item.quantity
    assert_equal 2, @item.inventory_items.where(status: :damaged).count
    assert_equal 2, @item.inventory_items.where(status: :available).count
  end
end
