class EmployeePaymentsController < ApplicationController
  before_action :require_leader!

  def index
    @payments = EmployeePayment.includes(:user, :gig).order(date_paid: :desc)

    if params[:user_id].present?
      @payments = @payments.where(user_id: params[:user_id])
      @selected_worker = User.find_by(id: params[:user_id])
    end

    # Calculamos métricas en bloque para evitar N+1
    payments = EmployeePayment.where(user_id: User.staff.select(:id))
    paid_sums = payments.group(:user_id).sum(:amount)
    expected_sums = payments.group(:user_id).sum(:expected_amount)
    counts = payments.group(:user_id).count

    @worker_metrics = User.staff.order(:email).map do |worker|
      paid_total = paid_sums[worker.id].to_f
      expected_total = expected_sums[worker.id].to_f

      {
        worker: worker,
        total_paid: paid_total,
        expected_amount: expected_total,
        balance_due: expected_total - paid_total,
        payment_count: counts[worker.id] || 0
      }
    end
  end

  def new
    @gig = Gig.find_by(id: params[:gig_id]) if params[:gig_id].present?
    @payment = EmployeePayment.new(
      gig_id: params[:gig_id],
      user_id: params[:user_id],
      currency: "USD"
    )
    @payroll_balance = @gig&.total_payroll_remaining.to_f
  end

  def create
    @payment = EmployeePayment.new(payment_params)
    payroll_gig = @payment.gig

    if payroll_gig.present?
      payroll_allocations = payroll_gig.payroll_allocations
      if payroll_allocations.empty?
        redirect_to new_employee_payment_path, alert: "Debe asignar primero un fondo de Nómina / Staff para este show antes de registrar el pago." and return
      end

      if @payment.amount.to_f > payroll_gig.total_payroll_remaining
        redirect_to new_employee_payment_path, alert: "El monto excede el saldo disponible en el fondo de Nómina / Staff." and return
      end
    end

    ActiveRecord::Base.transaction do
      @payment.save!
      if payroll_gig.present?
        consume_payroll_funds(payroll_gig, @payment.amount.to_f, @payment)
      end
    end

    redirect_to employee_payments_path(user_id: @payment.user_id), notice: "Pago a trabajador registrado."
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  private

  def consume_payroll_funds(gig, amount, payment)
    remaining_amount = amount.to_f
    gig.payroll_allocations.order(:created_at).each do |allocation|
      break if remaining_amount <= 0
      available = allocation.remaining.to_f
      next if available <= 0

      used = [available, remaining_amount].min
      allocation.fund_expenses.create!(amount: used, currency: allocation.currency, notes: "Pago a trabajador #{payment.user.email} (#{payment.date_paid})")
      remaining_amount -= used
    end

    if remaining_amount > 0
      raise ActiveRecord::RecordInvalid.new(payment)
    end
  end

  def payment_params
    params.require(:employee_payment).permit(:user_id, :gig_id, :amount, :currency, :date_paid, :payment_method, :notes, :expected_amount)
  end
end
