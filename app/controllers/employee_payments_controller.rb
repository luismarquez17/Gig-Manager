class EmployeePaymentsController < ApplicationController
  before_action :require_leader!
  before_action :set_payment, only: [:edit, :update, :destroy]

  def index
    @payments = current_company.employee_payments.includes(:user, :gig).order(date_paid: :desc)

    if params[:user_id].present?
      @payments = @payments.where(user_id: params[:user_id])
      @selected_worker = current_company.users.find_by(id: params[:user_id])
    end

    workers = current_company.users.workers.order(:email)
    worker_ids = workers.pluck(:id)

    staff_agreed_sums = StaffAssignment.where(user_id: worker_ids).group(:user_id).sum(:agreed_amount)
    paid_sums = current_company.employee_payments.where(user_id: worker_ids).group(:user_id).sum(:amount)
    counts = current_company.employee_payments.where(user_id: worker_ids).group(:user_id).count

    @worker_metrics = workers.map do |worker|
      agreed_total = staff_agreed_sums[worker.id].to_f
      paid_total = paid_sums[worker.id].to_f
      balance = agreed_total - paid_total

      {
        worker: worker,
        total_paid: paid_total,
        agreed_amount: agreed_total,
        balance: balance,
        payment_count: counts[worker.id] || 0
      }
    end
  end


  def new
    @gig = Gig.find_by(id: params[:gig_id]) if params[:gig_id].present?
    default_amount = nil
    if @gig.present? && params[:user_id].present?
      assignment = @gig.staff_assignments.find_by(user_id: params[:user_id])
      if assignment.present?
        default_amount = assignment.pending_balance.positive? ? assignment.pending_balance : assignment.agreed_amount.to_f
      end
    end

    @payment = EmployeePayment.new(
      gig_id: params[:gig_id],
      user_id: params[:user_id],
      amount: default_amount,
      currency: @gig&.currency.presence || "USD",
      date_paid: Date.today
    )
    @payroll_balance = FundAllocation.total_payroll_remaining
    @gig_payroll_balance = @gig&.total_payroll_remaining.to_f
  end

  def create
    @payment = current_company.employee_payments.build(payment_params)
    payroll_gig = @payment.gig

    if @payment.from_payroll_fund?
      total_payroll_available = FundAllocation.total_payroll_remaining

      if @payment.amount.to_f > total_payroll_available
        formatted_avail = view_context.number_to_currency(total_payroll_available, unit: 'USD')
        @payroll_balance = total_payroll_available
        @gig_payroll_balance = @payment.gig&.total_payroll_remaining.to_f
        flash.now[:alert] = "El monto excede el saldo disponible en el fondo de Nómina (#{formatted_avail}). Puedes cambiar el origen a 'Capital Externo (Dinero personal del leader)' para proceder."
        render :new, status: :unprocessable_entity and return
      end
    end

    ActiveRecord::Base.transaction do
      @payment.save!
      consume_payroll_funds(payroll_gig, @payment.amount.to_f, @payment) if @payment.from_payroll_fund?
    end

    notice_msg = @payment.from_external_capital? ? 
      "Pago a trabajador registrado con capital externo (#{@payment.funding_source_label})." : 
      "Pago a trabajador registrado descontado de fondos de nómina."

    redirect_to employee_payments_path(user_id: @payment.user_id), notice: notice_msg
  rescue ActiveRecord::RecordInvalid
    @payroll_balance = FundAllocation.total_payroll_remaining
    @gig_payroll_balance = @payment.gig&.total_payroll_remaining.to_f
    render :new, status: :unprocessable_entity
  end

  def edit
    @payroll_balance = FundAllocation.total_payroll_remaining
    @gig_payroll_balance = @payment.gig&.total_payroll_remaining.to_f
  end

  def update
    ActiveRecord::Base.transaction do
      # Revertir los gastos de nómina anteriores asociados a este pago
      @payment.fund_expenses.destroy_all

      @payment.assign_attributes(payment_params)

      if @payment.from_payroll_fund?
        total_payroll_available = FundAllocation.total_payroll_remaining

        if @payment.amount.to_f > total_payroll_available
          formatted_avail = view_context.number_to_currency(total_payroll_available, unit: 'USD')
          @payment.errors.add(:amount, "excede el saldo disponible en el fondo de Nómina (#{formatted_avail}). Puedes cambiar el origen a 'Capital Externo'.")
          raise ActiveRecord::RecordInvalid.new(@payment)
        end
      end

      @payment.save!
      consume_payroll_funds(@payment.gig, @payment.amount.to_f, @payment) if @payment.from_payroll_fund?
    end

    redirect_to employee_payments_path(user_id: @payment.user_id), notice: "Pago a trabajador actualizado correctamente."
  rescue ActiveRecord::RecordInvalid
    @payroll_balance = FundAllocation.total_payroll_remaining
    @gig_payroll_balance = @payment.gig&.total_payroll_remaining.to_f
    render :edit, status: :unprocessable_entity
  end

  def destroy
    user_id = @payment.user_id
    @payment.destroy
    redirect_to employee_payments_path(user_id: user_id), notice: "Pago eliminado correctamente."
  end

  private

  def set_payment
    @payment = current_company.employee_payments.find(params[:id])
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
    p_params = params.require(:employee_payment).permit(
      :user_id, :gig_id, :amount, :currency, :date_paid, 
      :payment_method, :notes, :expected_amount, 
      :funding_source, :external_source_name
    )
    p_params[:expected_amount] = 0.0 if p_params[:expected_amount].blank?
    p_params
  end
end
