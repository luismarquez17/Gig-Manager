# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ExchangeRateServiceTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    DailyExchangeRate.delete_all
  end

  test "fetch_and_cache_today creates or returns a daily exchange rate" do
    rate_record = ExchangeRateService.fetch_and_cache_today
    assert_not_nil rate_record
    assert rate_record.bcv_rate > 0
    assert_equal Date.current, rate_record.rate_date
    assert_equal "USD", rate_record.currency_from
    assert_equal "VES", rate_record.currency_to
  end

  test "to_ves and to_usd convert accurately" do
    # Create fixed test rate record
    DailyExchangeRate.create!(
      rate_date: Date.current,
      currency_from: "USD",
      currency_to: "VES",
      bcv_rate: 800.0,
      paralelo_rate: 900.0,
      source: "test",
      fetched_at: Time.current
    )

    ves = ExchangeRateService.to_ves(100.0, @company)
    assert_equal 80000.0, ves

    usd = ExchangeRateService.to_usd(40000.0, @company)
    assert_equal 50.0, usd
  end

  test "uses custom company exchange rate when configured" do
    DailyExchangeRate.create!(
      rate_date: Date.current,
      currency_from: "USD",
      currency_to: "VES",
      bcv_rate: 800.0,
      paralelo_rate: 900.0,
      source: "test",
      fetched_at: Time.current
    )

    @company.update!(payment_methods_config: {
      "exchange_rate" => {
        "mode" => "custom",
        "custom_rate" => 850.0
      }
    })

    rate_info = ExchangeRateService.today_rate_info(@company)
    assert_equal 850.0, rate_info[:effective_rate]
    assert_equal "custom", rate_info[:mode]

    ves = ExchangeRateService.to_ves(10.0, @company)
    assert_equal 8500.0, ves
  end

  test "uses auto_paralelo when configured in company" do
    DailyExchangeRate.create!(
      rate_date: Date.current,
      currency_from: "USD",
      currency_to: "VES",
      bcv_rate: 800.0,
      paralelo_rate: 950.0,
      source: "test",
      fetched_at: Time.current
    )

    @company.update!(payment_methods_config: {
      "exchange_rate" => {
        "mode" => "auto_paralelo"
      }
    })

    rate_info = ExchangeRateService.today_rate_info(@company)
    assert_equal 950.0, rate_info[:effective_rate]
    assert_equal "auto_paralelo", rate_info[:mode]
  end

  test "gracefully falls back when API or network fails" do
    # When no records exist and network fails, fallback record is used
    ExchangeRateService.stub(:http_get_json, nil) do
      rate_info = ExchangeRateService.today_rate_info
      assert rate_info[:effective_rate] > 0
      assert_equal Date.current, rate_info[:rate_date]
    end
  end
end
