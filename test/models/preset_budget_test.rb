require "test_helper"

class PresetBudgetTest < ActiveSupport::TestCase
  test "image_attached? and image_url_or_data return image_base64 when present" do
    company = companies(:one)
    preset = company.preset_budgets.create!(
      title: "Combo Básico",
      description: "2 cornetas y consola",
      price: 150.0,
      currency: "USD",
      image_base64: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    )

    assert preset.image_attached?
    assert_equal "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==", preset.image_url_or_data
  end
end
