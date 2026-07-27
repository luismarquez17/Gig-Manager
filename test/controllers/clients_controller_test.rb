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
end
