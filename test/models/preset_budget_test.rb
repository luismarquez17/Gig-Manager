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

  test "sync_image_to_base64 automatically converts attached ActiveStorage image to base64 on save" do
    company = companies(:one)
    preset = company.preset_budgets.build(
      title: "Combo Luces",
      description: "Puente de luces y cabezas móviles",
      price: 250.0,
      currency: "USD"
    )

    dummy_image = StringIO.new("fake-image-bytes-123")
    preset.image.attach(io: dummy_image, filename: "test_flyer.jpg", content_type: "image/jpeg")
    preset.save!

    assert preset.image_base64.present?
    assert preset.image_base64.start_with?("data:image/jpeg;base64,")
    assert preset.image_attached?
    assert_equal preset.image_base64, preset.image_url_or_data
  end

  test "safe blob checking handles missing physical storage file without crashing" do
    company = companies(:one)
    preset = company.preset_budgets.create!(
      title: "Combo Sin Base64",
      description: "Sin imagen base64",
      price: 100.0,
      currency: "USD"
    )

    # Attach an image then clear base64 and delete physical blob file
    dummy_image = StringIO.new("temp-bytes")
    preset.image.attach(io: dummy_image, filename: "deleted.jpg", content_type: "image/jpeg")
    preset.save!
    preset.update_column(:image_base64, nil)

    # Delete the physical file from disk to simulate ephemeral container wipe
    blob = preset.image.blob
    blob.service.delete(blob.key) if blob.service.exist?(blob.key)

    # image_attached? should safely return false and image_url_or_data return nil without crashing
    assert_not preset.image_attached?
    assert_nil preset.image_url_or_data
  end
end
