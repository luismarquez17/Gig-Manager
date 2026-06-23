class GigPaymentsController < ApplicationController
  before_action :require_leader!
  before_action :set_gig, if: -> { params[:gig_id].present? }

  def index
    if defined?(@gig) && @gig.present?
      @payments = @gig.gig_payments.order(date_paid: :desc)
    else
      @payments = GigPayment.includes(:gig).order(date_paid: :desc)
      # Shows (gigs) that still have outstanding amount to be paid
      @unpaid_gigs = Gig.all.select do |g|
        received = g.gig_payments.sum(:amount).to_f
        g.amount.to_f > received
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
