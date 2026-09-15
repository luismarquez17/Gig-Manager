# frozen_string_literal: true

class PaymentMethodsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_leader!
  before_action :set_company

  def edit
    @payment_methods = @company.payment_methods
  end

  def update
    cleaned_config = {
      "zelle" => {
        "enabled" => params.dig(:payment_methods, :zelle, :enabled) == "1",
        "email" => params.dig(:payment_methods, :zelle, :email).to_s.strip,
        "holder_name" => params.dig(:payment_methods, :zelle, :holder_name).to_s.strip,
        "bank" => params.dig(:payment_methods, :zelle, :bank).to_s.strip,
        "notes" => params.dig(:payment_methods, :zelle, :notes).to_s.strip
      },
      "binance" => {
        "enabled" => params.dig(:payment_methods, :binance, :enabled) == "1",
        "pay_id" => params.dig(:payment_methods, :binance, :pay_id).to_s.strip,
        "email" => params.dig(:payment_methods, :binance, :email).to_s.strip,
        "network" => params.dig(:payment_methods, :binance, :network).to_s.strip.presence || "USDT (TRC20 / BEP20)",
        "nickname" => params.dig(:payment_methods, :binance, :nickname).to_s.strip,
        "notes" => params.dig(:payment_methods, :binance, :notes).to_s.strip
      },
      "pago_movil" => {
        "enabled" => params.dig(:payment_methods, :pago_movil, :enabled) == "1",
        "bank" => params.dig(:payment_methods, :pago_movil, :bank).to_s.strip,
        "id_number" => params.dig(:payment_methods, :pago_movil, :id_number).to_s.strip,
        "phone" => params.dig(:payment_methods, :pago_movil, :phone).to_s.strip,
        "holder_name" => params.dig(:payment_methods, :pago_movil, :holder_name).to_s.strip,
        "notes" => params.dig(:payment_methods, :pago_movil, :notes).to_s.strip
      },
      "bank_transfer" => {
        "enabled" => params.dig(:payment_methods, :bank_transfer, :enabled) == "1",
        "bank" => params.dig(:payment_methods, :bank_transfer, :bank).to_s.strip,
        "account_number" => params.dig(:payment_methods, :bank_transfer, :account_number).to_s.strip,
        "account_type" => params.dig(:payment_methods, :bank_transfer, :account_type).to_s.strip.presence || "Corriente",
        "id_number" => params.dig(:payment_methods, :bank_transfer, :id_number).to_s.strip,
        "holder_name" => params.dig(:payment_methods, :bank_transfer, :holder_name).to_s.strip,
        "notes" => params.dig(:payment_methods, :bank_transfer, :notes).to_s.strip
      },
      "general_instructions" => params.dig(:payment_methods, :general_instructions).to_s.strip
    }

    if @company.update(payment_methods_config: cleaned_config)
      redirect_to payment_methods_settings_path, notice: "💳 ¡Configuración de Métodos de Pago actualizada con éxito!"
    else
      @payment_methods = cleaned_config
      flash.now[:alert] = "Error al guardar la configuración: #{@company.errors.full_messages.join(', ')}"
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_company
    @company = current_company
  end
end
