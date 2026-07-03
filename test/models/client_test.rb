require "test_helper"

class ClientTest < ActiveSupport::TestCase
  test "valid phone formats should be accepted" do
    valid_phones = ["04141234567", "0424-1234567", "+58 412 (123) 4567", "4141234567", "0000000000"]
    valid_phones.each do |phone|
      client = Client.new(name: "Test Client", phone: phone)
      assert client.valid?, "Phone '#{phone}' should be valid"
    end
  end

  test "invalid phone formats should be rejected" do
    invalid_phones = ["123", "0414-abc-123", "1234567890123456", "123456789", "phone123456"]
    invalid_phones.each do |phone|
      client = Client.new(name: "Test Client", phone: phone)
      assert_not client.valid?, "Phone '#{phone}' should be invalid"
      assert_includes client.errors[:phone], "debe tener entre 10 y 15 dígitos numéricos" || "no puede contener letras"
    end
  end

  test "phone cannot contain letters" do
    client = Client.new(name: "Test Client", phone: "0414-123-abc")
    assert_not client.valid?
    assert_includes client.errors[:phone], "no puede contener letras"
  end
end
