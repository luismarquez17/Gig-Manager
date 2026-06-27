class GigPaymentsController < ApplicationController
  before_action :require_leader!
  before_action :set_gig, if: -> { params[:gig_id].present? }

  def index
    if defined?(@gig) && @gig.present?
      @payments = @gig.gig_payments.order(date_paid: :desc)
      @payment_status = @gig.payment_status
      @remaining_amount = @gig.remaining_amount
    else
      @payments = GigPayment.includes(:gig).order(date_paid: :desc)
      received_by_gig = GigPayment.group(:gig_id).sum(:amount)
      @unpaid_gigs = Gig.all.select { |g| (received_by_gig[g.id] || 0).to_f < g.amount.to_f }

      @payment_status_counts = { paid: 0, partial: 0, unpaid: 0 }
      Gig.find_each do |gig|
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
    @payment = @gig.gig_payments.new
  end

  def create
    Rails.logger.debug "[GigPaymentsController#create] current_user=#{current_user&.id}-#{current_user&.role.inspect} params=#{params.inspect}"
    @payment = @gig.gig_payments.new(payment_params)
    if @payment.save
      Rails.logger.debug "[GigPaymentsController#create] saved gig_payment id=#{@payment.id}"
      redirect_to gig_path(@gig), notice: "Pago registrado con éxito."
    else
      Rails.logger.debug "[GigPaymentsController#create] validation errors=#{@payment.errors.full_messages}"
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[GigPaymentsController#create] RecordNotFound: #{e.message}"
    redirect_to gig_payments_path, alert: "No se encontró el show para registrar el pago."
  rescue => e
    Rails.logger.error "[GigPaymentsController#create] Exception: #{e.class} - #{e.message}\n#{e.backtrace[0..5].join("\n")}" 
    redirect_to gig_payments_path, alert: "Ocurrió un error al registrar el pago. Revisa la consola del servidor."
  end

  private

  def set_gig
    @gig = Gig.find(params[:gig_id])
  end

  def payment_params
    params.require(:gig_payment).permit(:amount, :currency, :date_paid, :is_advance, :payer_name, :for_date, :category, :notes)
  end
end
