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

  test "simulate_debt_distribution correctly cascades FIFO through unpaid gigs" do
    client = Client.create!(name: "Gero Venue", phone: "04141234567")
    gig1 = client.gigs.create!(amount: 150.0, date: Date.today - 14.days, location: "Gero Show 1")
    gig2 = client.gigs.create!(amount: 200.0, date: Date.today - 7.days, location: "Gero Show 2")
    gig3 = client.gigs.create!(amount: 150.0, date: Date.today, location: "Gero Show 3")

    assert_equal 500.0, client.total_debt

    # Simulamos un abono de 300
    sim = client.simulate_debt_distribution(300.0)
    assert_equal 300.0, sim[:total_allocated]
    assert_equal 0.0, sim[:remaining_unallocated]
    assert_equal 500.0, sim[:total_debt_before]
    assert_equal 200.0, sim[:total_debt_after]

    allocations = sim[:allocations]
    assert_equal 3, allocations.size

    # Gig 1 (el más antiguo): Se le asignan 150 y queda 100% saldado
    assert_equal gig1.id, allocations[0][:gig].id
    assert_equal 150.0, allocations[0][:allocated]
    assert_equal 0.0, allocations[0][:remaining_after]
    assert allocations[0][:fully_paid]

    # Gig 2: Se le asignan los 150 restantes del abono y queda debiendo 50
    assert_equal gig2.id, allocations[1][:gig].id
    assert_equal 150.0, allocations[1][:allocated]
    assert_equal 50.0, allocations[1][:remaining_after]
    assert_not allocations[1][:fully_paid]

    # Gig 3: No recibe nada, queda debiendo sus 150 completos
    assert_equal gig3.id, allocations[2][:gig].id
    assert_equal 0.0, allocations[2][:allocated]
    assert_equal 150.0, allocations[2][:remaining_after]
    assert_not allocations[2][:fully_paid]
  end

  test "apply_debt_payment! creates approved payments in FIFO order without errors or discrepancies" do
    client = Client.create!(name: "Gero Venue Real", phone: "04141234567")
    gig1 = client.gigs.create!(amount: 150.0, date: Date.today - 14.days, location: "Gero Show 1")
    gig2 = client.gigs.create!(amount: 200.0, date: Date.today - 7.days, location: "Gero Show 2")
    gig3 = client.gigs.create!(amount: 150.0, date: Date.today, location: "Gero Show 3")

    assert_equal 500.0, client.total_debt

    # Realizar abono agrupado de 300
    result = client.apply_debt_payment!(
      amount: 300.0,
      payment_method: 'zelle',
      date_paid: Date.today,
      reference_number: 'ZELLE-987654',
      notes: 'Abono semanal entregado por el dueño'
    )

    assert_equal 300.0, result[:total_applied]
    assert_equal 1, result[:settled_gigs].size
    assert_equal gig1.id, result[:settled_gigs].first.id
    assert_equal 1, result[:partial_gigs].size
    assert_equal gig2.id, result[:partial_gigs].first.id

    # Recargar gigs y verificar saldos
    assert_equal 0.0, gig1.reload.remaining_amount
    assert gig1.paid_in_full?
    assert_equal 1, gig1.gig_payments.count
    p1 = gig1.gig_payments.first
    assert_equal 150.0, p1.amount
    assert_equal 'approved', p1.status
    assert_equal 'zelle', p1.payment_method
    assert_equal 'ZELLE-987654', p1.reference_number
    assert_match /Abono semanal/, p1.notes
    assert_match /REC-/, p1.receipt_display_number

    assert_equal 50.0, gig2.reload.remaining_amount
    assert_not gig2.paid_in_full?
    assert_equal 1, gig2.gig_payments.count
    p2 = gig2.gig_payments.first
    assert_equal 150.0, p2.amount

    assert_equal 150.0, gig3.reload.remaining_amount
    assert_equal 0, gig3.gig_payments.count

    # Verificar nueva deuda total del cliente
    assert_equal 200.0, client.reload.total_debt
    assert_equal 2, client.unpaid_gigs.size
  end

  test "apply_debt_payment! rejects invalid amounts" do
    client = Client.create!(name: "Cliente Invalido", phone: "04141234567")
    client.gigs.create!(amount: 100.0, date: Date.today)

    assert_raises(ArgumentError, "El monto a abonar debe ser mayor a 0.") do
      client.apply_debt_payment!(amount: 0, payment_method: 'cash')
    end

    assert_raises(ArgumentError, "El monto a abonar debe ser mayor a 0.") do
      client.apply_debt_payment!(amount: -50, payment_method: 'cash')
    end

    assert_raises(ArgumentError) do
      # Deuda total es 100, intenta pagar 150
      client.apply_debt_payment!(amount: 150.0, payment_method: 'cash')
    end
  end
end
