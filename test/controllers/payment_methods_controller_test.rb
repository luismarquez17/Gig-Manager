# frozen_string_literal: true

require "test_helper"

class PaymentMethodsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @company = companies(:one)
    @user = users(:one)
    @user.update!(role: :leader, company: @company)
    sign_in @user
  end

  test "should get edit" do
    get payment_methods_settings_url
    assert_response :success
    assert_select "h1", text: /Métodos de Pago/
    assert_select "h3", text: /Tasa de Cambio Diaria/
  end

  test "should update payment methods with exchange rate config" do
    patch payment_methods_settings_url, params: {
      payment_methods: {
        zelle: {
          enabled: "1",
          email: "test@zelle.com",
          holder_name: "Test Holder"
        },
        pago_movil: {
          enabled: "1",
          phone: "04141234567",
          id_number: "V-12345678"
        },
        exchange_rate: {
          mode: "custom",
          custom_rate: "895.50",
          show_in_portals: "1"
        },
        general_instructions: "Instrucciones de prueba"
      }
    }

    assert_redirected_to payment_methods_settings_url
    @company.reload
    assert @company.zelle_enabled?
    assert @company.pago_movil_enabled?
    assert_equal "custom", @company.exchange_rate_config["mode"]
    assert_equal 895.50, @company.exchange_rate_config["custom_rate"]
    assert_equal true, @company.exchange_rate_config["show_in_portals"]
  end
end
