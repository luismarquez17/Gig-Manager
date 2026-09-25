require "test_helper"

class ClientQuoteTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
  end

  test "dynamic open link sequential numbering" do
    # Clear any existing unnamed quotes for this company
    ClientQuote.where(company: @company, client_name: [nil, '']).destroy_all

    # 1. Crear primer enlace abierto
    quote1 = ClientQuote.create!(company: @company, amount: 0.0, currency: "USD", created_at: 10.minutes.ago)
    assert_equal 1, quote1.open_link_number
    assert_equal "Enlace Abierto #1", quote1.display_client_name

    # 2. Crear segundo enlace abierto
    quote2 = ClientQuote.create!(company: @company, amount: 0.0, currency: "USD", created_at: 5.minutes.ago)
    assert_equal 1, quote1.reload.open_link_number
    assert_equal 2, quote2.reload.open_link_number
    assert_equal "Enlace Abierto #1", quote1.display_client_name
    assert_equal "Enlace Abierto #2", quote2.display_client_name

    # 3. Eliminar el primer enlace abierto
    quote1.destroy
    assert_equal 1, quote2.reload.open_link_number
    assert_equal "Enlace Abierto #1", quote2.display_client_name

    # 4. Crear un nuevo enlace abierto posterior
    quote3 = ClientQuote.create!(company: @company, amount: 0.0, currency: "USD", created_at: Time.current)
    assert_equal 1, quote2.reload.open_link_number
    assert_equal 2, quote3.reload.open_link_number
    assert_equal "Enlace Abierto #1", quote2.display_client_name
    assert_equal "Enlace Abierto #2", quote3.display_client_name

    # 5. Si se le asigna nombre al cliente, display_client_name muestra el nombre
    quote3.update!(client_name: "Carlos Sanchez", client_phone: "04141234567")
    assert_equal "Carlos Sanchez", quote3.display_client_name
  end
end
