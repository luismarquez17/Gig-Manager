require "test_helper"

class ClientsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @client = clients(:one)
  end

  test "should get index" do
    get clients_url
    assert_response :success
  end

  test "should get new" do
    get new_client_url
    assert_response :success
  end

  test "should get show" do
    get client_url(@client)
    assert_response :success
  end

  test "should get debts with filters" do
    get debts_clients_url
    assert_response :success

    get debts_clients_url(query: @client.name, date_status: "expired")
    assert_response :success

    get debts_clients_url(date_status: "upcoming")
    assert_response :success
  end

  test "should get debt view for client" do
    get debt_client_url(@client)
    assert_response :success
  end

  test "should record debt payment and cascade FIFO" do
    client = @user.company.clients.create!(name: "Cliente Prueba FIFO", phone: "04149998877")
    gig1 = client.gigs.create!(company: @user.company, amount: 200.0, date: Date.today - 5.days, location: "Show 1")
    gig2 = client.gigs.create!(company: @user.company, amount: 150.0, date: Date.today, location: "Show 2")

    assert_difference('GigPayment.count', 2) do
      post record_debt_payment_client_url(client), params: {
        amount: "250.00",
        payment_method: "zelle",
        date_paid: Date.today.to_s,
        reference_number: "ZELLE-TEST-123",
        notes: "Abono general",
        redirect_to: "debt"
      }
    end

    assert_redirected_to debt_client_url(client)
    follow_redirect!
    assert_response :success

    assert_equal 0.0, gig1.reload.remaining_amount
    assert_equal 100.0, gig2.reload.remaining_amount
    assert_equal 100.0, client.reload.total_debt
  end
end
