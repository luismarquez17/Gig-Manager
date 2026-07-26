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

  test "total_debt and unpaid_gigs calculation" do
    client = Client.create!(name: "Cliente Deudor", phone: "04141234567")
    gig1 = client.gigs.create!(amount: 500.0, date: Date.today)
    gig2 = client.gigs.create!(amount: 300.0, date: Date.today + 1.day)
    
    # Registrar pago parcial de 200 en gig1
    gig1.gig_payments.create!(amount: 200.0)

    assert_equal 600.0, client.total_debt
    assert_equal 2, client.unpaid_gigs.size
    assert client.has_debt?
    assert_includes CGI.unescape(client.debt_whatsapp_url), "Deuda Total Pendiente: $600.00"
  end
end
