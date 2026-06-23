class EmployeePaymentsController < ApplicationController
  before_action :require_leader!

  def index
    @payments = EmployeePayment.includes(:user, :gig).order(date_paid: :desc)
  end

  def new
    @payment = EmployeePayment.new
  end

  def create
    @payment = EmployeePayment.new(payment_params)
    if @payment.save
      redirect_to employee_payments_path, notice: "Pago a empleado registrado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def payment_params
    params.require(:employee_payment).permit(:user_id, :gig_id, :amount, :currency, :date_paid, :payment_method, :notes)
  end
end
