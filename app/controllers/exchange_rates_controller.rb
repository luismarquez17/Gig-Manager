# frozen_string_literal: true

class ExchangeRatesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show]
  before_action :authenticate_user!, only: [:refresh]

  def show
    target_company = current_company || set_company_from_token
    rate_info = ExchangeRateService.today_rate_info(target_company)

    # Calculate conversions if amount query parameters provided
    if params[:amount_usd].present?
      rate_info[:converted_ves] = ExchangeRateService.to_ves(params[:amount_usd], target_company)
      rate_info[:formatted_converted_ves] = ExchangeRateService.format_currency_ves(rate_info[:converted_ves])
    end

    if params[:amount_ves].present?
      rate_info[:converted_usd] = ExchangeRateService.to_usd(params[:amount_ves].to_s.tr(',', '.'), target_company)
      rate_info[:formatted_converted_usd] = sprintf('%.2f', rate_info[:converted_usd])
    end

    render json: {
      success: true,
      data: rate_info
    }
  end

  def refresh
    target_company = current_company
    record = ExchangeRateService.fetch_and_cache_today(force_refresh: true)
    rate_info = ExchangeRateService.today_rate_info(target_company)

    render json: {
      success: true,
      message: "Tasa del día actualizada correctamente con la fuente oficial.",
      data: rate_info
    }
  rescue StandardError => e
    render json: {
      success: false,
      error: "No se pudo sincronizar en vivo: #{e.message}"
    }, status: :unprocessable_entity
  end

  private

  def set_company_from_token
    if params[:portal_token].present?
      Gig.find_by(portal_token: params[:portal_token])&.company
    elsif params[:quote_token].present?
      ClientQuote.find_by(public_token: params[:quote_token])&.company
    end
  end
end
