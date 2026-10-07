# frozen_string_literal: true

require "test_helper"

class ExchangeRatesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @company = companies(:one)
    @user = users(:one)
    @user.update!(role: :leader, company: @company)
  end

  test "public show returns json with exchange rate info" do
    get api_exchange_rate_url, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json["success"]
    assert json["data"]["effective_rate"] > 0
    assert_not_nil json["data"]["formatted_effective_rate"]
  end

  test "show with amount_usd calculates converted_ves" do
    get api_exchange_rate_url(amount_usd: 100), as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json["success"]
    assert json["data"]["converted_ves"] > 0
    assert_not_nil json["data"]["formatted_converted_ves"]
  end

  test "refresh endpoint updates daily rate for authenticated leader" do
    sign_in @user
    post api_refresh_exchange_rate_url, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal "Tasa del día actualizada correctamente con la fuente oficial.", json["message"]
  end

  test "refresh requires authentication" do
    post api_refresh_exchange_rate_url, as: :json
    assert_response :unauthorized
  end
end
