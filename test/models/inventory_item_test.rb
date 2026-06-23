require "test_helper"

class InventoryItemTest < ActiveSupport::TestCase
  test "validates presence of status" do
    item = Item.create!(name: "Test Item", category: "Cables", status: "Excelente")
    inventory_item = InventoryItem.new(item: item)
    assert inventory_item.valid?
    assert_equal "available", inventory_item.status

    inventory_item.status = nil
    assert_not inventory_item.valid?
  end
end
