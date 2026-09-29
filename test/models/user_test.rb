require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "avatar_attached? and avatar_url_or_data return avatar_base64 when present" do
    company = companies(:one)
    user = User.create!(
      email: "musician_test@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Músico Base64",
      role: :musician,
      company: company,
      avatar_base64: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    )

    assert user.avatar_attached?
    assert_equal "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==", user.avatar_url_or_data
  end

  test "sync_avatar_to_base64 automatically converts attached ActiveStorage avatar to base64 on save" do
    company = companies(:one)
    user = User.new(
      email: "new_avatar_user@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Nuevo Avatar",
      role: :musician,
      company: company
    )

    dummy_avatar = StringIO.new("fake-avatar-bytes-456")
    user.avatar.attach(io: dummy_avatar, filename: "avatar.jpg", content_type: "image/jpeg")
    user.save!

    assert user.avatar_base64.present?
    assert user.avatar_base64.start_with?("data:image/jpeg;base64,")
    assert user.avatar_attached?
    assert_equal user.avatar_base64, user.avatar_url_or_data
  end

  test "safe blob checking handles missing physical avatar file without crashing" do
    company = companies(:one)
    user = User.create!(
      email: "missing_file_user@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "Missing File User",
      role: :staff,
      company: company
    )

    dummy_avatar = StringIO.new("temp-avatar")
    user.avatar.attach(io: dummy_avatar, filename: "temp.jpg", content_type: "image/jpeg")
    user.save!
    user.update_column(:avatar_base64, nil)

    # Delete the physical file from disk to simulate ephemeral container wipe
    blob = user.avatar.blob
    blob.service.delete(blob.key) if blob.service.exist?(blob.key)

    # avatar_attached? should safely return false and avatar_url_or_data return nil without crashing
    assert_not user.avatar_attached?
    assert_nil user.avatar_url_or_data
  end
end
