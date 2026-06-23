require "test_helper"

class MaintenanceRecordTest < ActiveSupport::TestCase
  test "lifecycle of maintenance record updates inventory items" do
    item = Item.create!(name: "Pro Bass Guitar", category: "Bajos", status: "Excelente", quantity: 3)
    
    assert_equal 3, item.inventory_items.count
    assert_equal 3, item.available_count

    # Create a pending maintenance record
    mr = MaintenanceRecord.create!(item: item, description: "Broken string", status: :pending)

    assert_not_nil mr.inventory_item
    assert_equal "maintenance", mr.inventory_item.status
    assert_equal 2, item.available_count
    assert_equal "Operativo", item.status

    # Mark as fixed
    mr.update!(status: :fixed)
    assert_equal "available", mr.inventory_item.reload.status
    assert_equal 3, item.available_count
    assert_equal "Excelente", item.status

    # Create another one and discard it
    mr2 = MaintenanceRecord.create!(item: item, description: "Smashed neck", status: :pending)
    mr2.update!(status: :discarded)

    assert_equal 2, item.reload.quantity
    assert_equal 2, item.inventory_items.count
    assert_equal "Excelente", item.status
  end
end
