require "test_helper"

class SubCategoryTest < ActiveSupport::TestCase
  test "validates presence of name and category" do
    sc = SubCategory.new
    assert_not sc.valid?
    assert_includes sc.errors[:name], "can't be blank"

    sc.name = "Speakon"
    sc.category = "Cables"
    assert sc.valid?
  end

  test "validates uniqueness of name scoped to category" do
    SubCategory.create!(name: "Speakon", category: "Cables")
    duplicate = SubCategory.new(name: "speakon", category: "Cables")
    assert_not duplicate.valid?
  end

  test "Item.sub_categories_for includes custom sub_category for any category" do
    SubCategory.create!(name: "Sparkulas", category: "Dispositivos DJ")
    assert_includes Item.sub_categories_for("Dispositivos DJ"), "Sparkulas"
  end
end
