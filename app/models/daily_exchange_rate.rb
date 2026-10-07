# frozen_string_literal: true

class DailyExchangeRate < ApplicationRecord
  validates :rate_date, presence: true
  validates :currency_from, presence: true
  validates :currency_to, presence: true
  validates :bcv_rate, presence: true, numericality: { greater_than: 0 }
  validates :rate_date, uniqueness: { scope: [:currency_from, :currency_to], message: "ya tiene una tasa registrada para este par de monedas" }

  class << self
    def latest
      order(rate_date: :desc).first
    end

    def for_today
      find_by(rate_date: Date.current, currency_from: "USD", currency_to: "VES")
    end
  end

  def effective_rate(mode = 'auto_bcv')
    case mode.to_s
    when 'auto_paralelo'
      paralelo_rate.present? && paralelo_rate > 0 ? paralelo_rate : bcv_rate
    else
      bcv_rate
    end
  end

  def formatted_bcv
    ActionController::Base.helpers.number_with_precision(bcv_rate, precision: 2, delimiter: '.', separator: ',')
  end

  def formatted_paralelo
    return nil unless paralelo_rate.present? && paralelo_rate > 0
    ActionController::Base.helpers.number_with_precision(paralelo_rate, precision: 2, delimiter: '.', separator: ',')
  end
end
