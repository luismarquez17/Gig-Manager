class EmployeePaymentsController < ApplicationController
  before_action :require_leader!
  before_action :set_payment, only: [:edit, :update, :destroy]

  def index
    @payments = EmployeePayment.includes(:user, :gig).order(date_paid: :desc)

    if params[:user_id].present?
      @payments = @payments.where(user_id: params[:user_id])
      @selected_worker = User.find_by(id: params[:user_id])
    end

    # Calculamos métricas en bloque para evitar N+1
    payments = EmployeePayment.where(user_id: User.workers.select(:id))
    paid_sums = payments.group(:user_id).sum(:amount)
    expected_sums = payments.group(:user_id).sum(:expected_amount)
    counts = payments.group(:user_id).count

    @worker_metrics = User.workers.order(:email).map do |worker|
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
    expected = 0.0
    if @gig.present? && params[:user_id].present?
      assignment = @gig.staff_assignments.find_by(user_id: params[:user_id])
      expected = assignment&.agreed_amount.to_f if assignment.present?
    end

    @payment = EmployeePayment.new(
      gig_id: params[:gig_id],
      user_id: params[:user_id],
      currency: "USD",
      expected_amount: expected
    )
    @payroll_balance = FundAllocation.total_payroll_remaining
    @gig_payroll_balance = @gig&.total_payroll_remaining.to_f
  end

  def create
    @payment = EmployeePayment.new(payment_params)
    payroll_gig = @payment.gig

    total_payroll_available = FundAllocation.total_payroll_remaining

    if @payment.amount.to_f > total_payroll_available
      formatted_avail = view_context.number_to_currency(total_payroll_available, unit: 'USD')
      redirect_to new_employee_payment_path(gig_id: @payment.gig_id, user_id: @payment.user_id),
                  alert: "El monto excede el saldo disponible en el fondo universal de Nómina / Agrupación (#{formatted_avail})." and return
    end

    ActiveRecord::Base.transaction do
      @payment.save!
      consume_payroll_funds(payroll_gig, @payment.amount.to_f, @payment)
    end

    redirect_to employee_payments_path(user_id: @payment.user_id), notice: "Pago a trabajador registrado."
  rescue ActiveRecord::RecordInvalid
    @payroll_balance = FundAllocation.total_payroll_remaining
    @gig_payroll_balance = @payment.gig&.total_payroll_remaining.to_f
    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    ActiveRecord::Base.transaction do
      # Revertir los gastos de nómina anteriores asociados a este pago
      @payment.fund_expenses.destroy_all

      @payment.assign_attributes(payment_params)

      total_payroll_available = FundAllocation.total_payroll_remaining

      if @payment.amount.to_f > total_payroll_available
        formatted_avail = view_context.number_to_currency(total_payroll_available, unit: 'USD')
        @payment.errors.add(:amount, "excede el saldo disponible en el fondo universal de Nómina / Agrupación (#{formatted_avail})")
        raise ActiveRecord::RecordInvalid.new(@payment)
      end

      @payment.save!
      consume_payroll_funds(@payment.gig, @payment.amount.to_f, @payment)
    end

    redirect_to employee_payments_path(user_id: @payment.user_id), notice: "Pago a trabajador actualizado correctamente."
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  def destroy
    user_id = @payment.user_id
    @payment.destroy
    redirect_to employee_payments_path(user_id: user_id), notice: "Pago eliminado correctamente."
  end

  private

  def set_payment
    @payment = EmployeePayment.find(params[:id])
  end

  def consume_payroll_funds(gig, amount, payment)
    remaining_amount = amount.to_f
    return if remaining_amount <= 0

    primary_allocations = gig.present? ? gig.payroll_allocations.order(:created_at).to_a : []
    primary_ids = primary_allocations.map(&:id)

    secondary_allocations = FundAllocation.where(fund_type: 'payroll')
                                          .where.not(id: primary_ids)
                                          .order(:created_at).to_a

    allocations = primary_allocations + secondary_allocations

    allocations.each do |allocation|
      break if remaining_amount <= 0
      available = allocation.remaining.to_f
      next if available <= 0

      used = [available, remaining_amount].min
      allocation.fund_expenses.create!(
        amount: used,
        currency: allocation.currency,
        notes: "Pago a trabajador #{payment.user.display_name rescue payment.user.email} (#{payment.date_paid})",
        employee_payment_id: payment.id
      )
      remaining_amount -= used
    end

    if remaining_amount > 0
      payment.errors.add(:amount, "excede el saldo disponible en el fondo universal de Nómina.")
      raise ActiveRecord::RecordInvalid.new(payment)
    end
  end

  def payment_params
    params.require(:employee_payment).permit(:user_id, :gig_id, :amount, :currency, :date_paid, :payment_method, :notes, :expected_amount)
  end
end
