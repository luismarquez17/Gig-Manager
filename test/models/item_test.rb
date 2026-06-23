require "test_helper"

class ItemTest < ActiveSupport::TestCase
  test "dynamic counts of inventory items" do
    item = Item.create!(name: "Test Cable", category: "Cables", status: "Excelente")
    
    # Check that creating item with default quantity (nil/0) doesn't create inventory items
    assert_equal 0, item.total_count

    # Update quantity to 5
    item.update!(quantity: 5)
    assert_equal 5, item.total_count
    assert_equal 5, item.available_count
    assert_equal "Excelente", item.status

    # Mark one copy as damaged
    item.inventory_items.first.update!(status: :damaged)
    assert_equal 4, item.available_count
    assert_equal 1, item.damaged_count
    assert_equal "Operativo", item.status

    # Decrease quantity to 3
    item.update!(quantity: 3)
    assert_equal 3, item.total_count
  end
end
