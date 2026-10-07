# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

class ExchangeRateService
  BCV_API_URL = "https://ve.dolarapi.com/v1/dolares/oficial"
  PARALELO_API_URL = "https://ve.dolarapi.com/v1/dolares/paralelo"
  DEFAULT_FALLBACK_RATE = 873.87
  CACHE_DURATION = 4.hours

  class << self
    def fetch_and_cache_today(force_refresh: false)
      today = Date.current
      existing = DailyExchangeRate.find_by(rate_date: today, currency_from: "USD", currency_to: "VES")

      if existing.present? && !force_refresh && existing.fetched_at > CACHE_DURATION.ago
        return existing
      end

      # Fetch live rates from official & paralelo APIs
      bcv_data = http_get_json(BCV_API_URL)
      paralelo_data = http_get_json(PARALELO_API_URL)

      bcv_rate = bcv_data&.dig("promedio")&.to_f
      paralelo_rate = paralelo_data&.dig("promedio")&.to_f

      # If BCV API succeeded and returned a valid rate
      if bcv_rate.present? && bcv_rate > 0
        record = existing || DailyExchangeRate.new(rate_date: today, currency_from: "USD", currency_to: "VES")
        record.bcv_rate = bcv_rate
        record.paralelo_rate = paralelo_rate if paralelo_rate.present? && paralelo_rate > 0
        record.source = "ve_dolarapi_bcv"
        record.fetched_at = Time.current
        record.save!
        return record
      end

      # Fallback to existing record or latest in DB
      existing || DailyExchangeRate.latest || fallback_record(today)
    rescue StandardError => e
      Rails.logger.warn("ExchangeRateService: Error fetching daily rate: #{e.message}")
      existing || DailyExchangeRate.latest || fallback_record(Date.current)
    end

    def today_rate_info(company = nil)
      record = fetch_and_cache_today(force_refresh: false)
      config = company_exchange_config(company)
      mode = config[:mode]
      custom_rate = config[:custom_rate]

      effective_rate = if mode == 'custom' && custom_rate.present? && custom_rate > 0
        custom_rate
      elsif mode == 'auto_paralelo' && record.paralelo_rate.present? && record.paralelo_rate > 0
        record.paralelo_rate
      else
        record.bcv_rate
      end

      {
        effective_rate: effective_rate.to_f,
        bcv_rate: record.bcv_rate.to_f,
        paralelo_rate: record.paralelo_rate&.to_f,
        mode: mode,
        source: mode == 'custom' ? 'manual_custom' : record.source,
        rate_date: record.rate_date,
        fetched_at: record.fetched_at,
        formatted_effective_rate: format_currency_ves(effective_rate),
        formatted_bcv: format_currency_ves(record.bcv_rate),
        formatted_paralelo: record.paralelo_rate ? format_currency_ves(record.paralelo_rate) : nil,
        updated_ago: time_ago_spanish(record.fetched_at)
      }
    end

    def current_rate(company = nil)
      today_rate_info(company)[:effective_rate]
    end

    def to_ves(amount_usd, company = nil)
      rate = current_rate(company)
      (amount_usd.to_f * rate).round(2)
    end

    def to_usd(amount_ves, company = nil)
      rate = current_rate(company)
      return 0.0 if rate <= 0
      (amount_ves.to_f / rate).round(2)
    end

    def format_currency_ves(amount)
      return "0,00" if amount.nil?
      ActionController::Base.helpers.number_with_precision(
        amount,
        precision: 2,
        delimiter: '.',
        separator: ','
      )
    end

    private

    def http_get_json(url_string)
      uri = URI.parse(url_string)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 3.0
      http.read_timeout = 3.0

      request = Net::HTTP::Get.new(uri.request_uri)
      request['Accept'] = 'application/json'
      request['User-Agent'] = 'GigManager/1.0'

      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue StandardError => e
      Rails.logger.warn("ExchangeRateService: HTTP request failed for #{url_string}: #{e.message}")
      nil
    end

    def fallback_record(date)
      DailyExchangeRate.new(
        rate_date: date,
        currency_from: "USD",
        currency_to: "VES",
        bcv_rate: DEFAULT_FALLBACK_RATE,
        paralelo_rate: DEFAULT_FALLBACK_RATE * 1.15,
        source: "default_fallback",
        fetched_at: Time.current
      )
    end

    def company_exchange_config(company)
      return { mode: 'auto_bcv', custom_rate: nil } unless company.present?
      pm = company.payment_methods rescue {}
      rate_cfg = pm["exchange_rate"] || {}

      mode = rate_cfg["mode"].presence || 'auto_bcv'
      custom_rate = rate_cfg["custom_rate"].to_s.tr(',', '.').to_f

      {
        mode: mode,
        custom_rate: (custom_rate > 0 ? custom_rate : nil)
      }
    end

    def time_ago_spanish(time)
      return "hoy" if time.blank?
      diff_minutes = ((Time.current - time) / 60).to_i
      if diff_minutes < 1
        "hace unos segundos"
      elsif diff_minutes < 60
        "hace #{diff_minutes} min"
      else
        hours = diff_minutes / 60
        "hace #{hours} h"
      end
    end
  end
end
