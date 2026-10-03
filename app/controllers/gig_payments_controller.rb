# frozen_string_literal: true

class GigPaymentsController < ApplicationController
  before_action :require_leader!
  before_action -> { require_module!(:gigs) }
  before_action :set_gig, if: -> { params[:gig_id].present? }
  before_action :set_payment, only: [:edit, :update, :destroy, :receipt]

  def index
    if defined?(@gig) && @gig.present?
      @payments = @gig.gig_payments.order(date_paid: :desc)
      @payment_status = @gig.payment_status
      @remaining_amount = @gig.remaining_amount
    else
      @payments = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id }).includes(gig: :client).order(date_paid: :desc)
      received_by_gig = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id }).group(:gig_id).sum(:amount)
      @unpaid_gigs = current_company.gigs.includes(:client, :gig_payments).select { |g| (received_by_gig[g.id] || 0).to_f < g.amount.to_f }

      @payment_status_counts = { paid: 0, partial: 0, unpaid: 0 }
      current_company.gigs.find_each do |gig|
        status = if (received_by_gig[gig.id] || 0).to_f.zero?
                   :unpaid
                 elsif (gig.amount.to_f - (received_by_gig[gig.id] || 0).to_f).positive?
                   :partial
                 else
                   :paid
                 end
        @payment_status_counts[status] += 1
      end
    end
  end

  def new
    @payment = @gig.gig_payments.new(
      date_paid: Date.today,
      currency: @gig.currency.presence || 'USD',
      payment_method: 'cash'
    )
  end

  def create
    @payment = @gig.gig_payments.new(payment_params)
    @payment.audit_reason = params.dig(:gig_payment, :audit_reason).presence || "Registro de abono inicial"

    if @payment.save
      redirect_to gig_path(@gig), notice: "✅ Pago registrado con éxito. Folio generado: #{@payment.receipt_display_number}."
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[GigPaymentsController#create] RecordNotFound: #{e.message}"
    redirect_to gig_payments_path, alert: "No se encontró el show para registrar el pago."
  rescue StandardError => e
    Rails.logger.error "[GigPaymentsController#create] Exception: #{e.class} - #{e.message}\n#{e.backtrace[0..5].join("\n")}" 
    redirect_to gig_payments_path, alert: "Ocurrió un error al registrar el pago."
  end

  def edit
  end

  def update
    @payment.audit_reason = params.dig(:gig_payment, :audit_reason).presence || "Modificación de pago"
    if @payment.update(payment_params)
      redirect_to gig_path(@payment.gig), notice: "✅ Pago actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    gig = @payment.gig
    @payment.audit_reason = params[:audit_reason].presence || "Eliminación de pago por el usuario"
    @payment.destroy
    redirect_to gig_path(gig), notice: "🗑️ Pago eliminado correctamente del sistema y registrado en auditoría."
  end

  def receipt
    @gig = @payment.gig
    @company = @gig.company || current_company
    @client = @gig.client
    render layout: false
  end

  private

  def set_gig
    @gig = current_company.gigs.includes(:client).find(params[:gig_id])
  end

  def set_payment
    @payment = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id }).find(params[:id])
  end

  def payment_params
    params.require(:gig_payment).permit(
      :amount, :currency, :date_paid, :is_advance, :payer_name,
      :for_date, :category, :notes, :payment_method, :receipt_number, :audit_reason
    )
  end
end
