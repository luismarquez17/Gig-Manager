class EmployeePaymentsController < ApplicationController
  before_action :require_leader!, except: [:new_worker_report, :create_worker_report]
  before_action :set_payment, only: [:edit, :update, :destroy, :approve, :reject]

  def index
    @payments = current_company.employee_payments.includes(:user, :gig).order(date_paid: :desc, created_at: :desc)
    @pending_approvals = current_company.employee_payments.pending_approval.includes(:user, :gig).order(created_at: :desc)

    if params[:user_id].present?
      @payments = @payments.where(user_id: params[:user_id])
      @selected_worker = current_company.users.find_by(id: params[:user_id])
    end

    if params[:status].present?
      @payments = @payments.where(status: params[:status])
    end

    workers = current_company.users.workers.order(:email)
    worker_ids = workers.pluck(:id)

    staff_agreed_sums = StaffAssignment.where(user_id: worker_ids).group(:user_id).sum(:agreed_amount)
    paid_sums = current_company.employee_payments.approved.where(user_id: worker_ids).group(:user_id).sum(:amount)
    counts = current_company.employee_payments.approved.where(user_id: worker_ids).group(:user_id).count

    # Preload assignments with gig + client for breakdown
    assignments_by_worker = StaffAssignment
      .where(user_id: worker_ids)
      .includes(gig: :client)
      .group_by(&:user_id)

    # Preload approved payments per worker keyed by gig_id (nil = standalone)
    all_approved_payments = current_company.employee_payments.approved.where(user_id: worker_ids).includes(:gig)
    payments_by_worker = all_approved_payments.group_by(&:user_id)

    @worker_metrics = workers.map do |worker|
      agreed_total = staff_agreed_sums[worker.id].to_f
      paid_total   = paid_sums[worker.id].to_f
      balance      = agreed_total - paid_total  # total: past + future

      worker_payments = payments_by_worker[worker.id] || []
      paid_by_gig     = worker_payments.group_by(&:gig_id).transform_values { |ps| ps.sum { |p| p.amount.to_f } }

      worker_assignments = assignments_by_worker[worker.id] || []

      today = Date.today

      # Past balance: only gigs that have already occurred
      past_balance = worker_assignments.sum do |sa|
        next 0 unless sa.gig.present? && sa.gig.date.present? && sa.gig.date <= today
        sa.agreed_amount.to_f - paid_by_gig[sa.gig_id].to_f
      end

      # Debt breakdown: one entry per past gig with a pending balance
      gig_debts = worker_assignments.filter_map do |sa|
        next if sa.gig.blank? || sa.gig.date.blank? || sa.gig.date > today

        paid_for_gig   = paid_by_gig[sa.gig_id].to_f
        pending        = sa.agreed_amount.to_f - paid_for_gig
        next if pending <= 0

        {
          gig:            sa.gig,
          agreed_amount:  sa.agreed_amount.to_f,
          paid_amount:    paid_for_gig,
          pending_amount: pending,
          type:           :assignment
        }
      end

      # Standalone payments where expected_amount > paid amount (e.g. adjustment debts)
      assigned_gig_ids = worker_assignments.map(&:gig_id)
      standalone_payments = worker_payments.reject { |p| assigned_gig_ids.include?(p.gig_id) }
      standalone_by_gig   = standalone_payments.group_by(&:gig_id)
      standalone_by_gig.each do |gig_id, ps|
        paid_for_gig   = ps.sum { |p| p.amount.to_f }
        expected       = ps.map { |p| p.expected_amount.to_f }.max || 0.0
        pending        = expected - paid_for_gig
        next if pending <= 0

        gig_debts << {
          gig:            ps.first.gig,
          agreed_amount:  expected,
          paid_amount:    paid_for_gig,
          pending_amount: pending,
          type:           :standalone
        }
      end

      gig_debts.sort_by! { |d| d[:gig]&.date || Date.today }.reverse!

      {
        worker:        worker,
        total_paid:    paid_total,
        agreed_amount: agreed_total,
        balance:       balance,
        past_balance:  past_balance,
        payment_count: counts[worker.id] || 0,
        gig_debts:     gig_debts
      }
    end
  end

  def new_worker_report
    @assigned_gigs = current_user.assigned_gigs.includes(:client).order(date: :desc)
    @gig = current_company.gigs.find_by(id: params[:gig_id]) if params[:gig_id].present?
    
    default_amount = nil
    if @gig.present?
      assignment = @gig.staff_assignments.find_by(user_id: current_user.id)
      if assignment.present?
        agreed = assignment.agreed_amount.to_f
        paid = current_user.employee_payments.approved.where(gig_id: @gig.id).sum(:amount).to_f
        pending_gig_bal = agreed - paid
        default_amount = pending_gig_bal.positive? ? pending_gig_bal : agreed
      end
    end

    @payment = EmployeePayment.new(
      user: current_user,
      gig_id: @gig&.id,
      amount: default_amount,
      currency: @gig&.currency.presence || "USD",
      date_paid: Date.today,
      status: 'pending_approval',
      reported_by_worker: true
    )
  end

  def create_worker_report
    report_params = worker_report_params
    amount = report_params[:amount].to_f

    # 1. Validación de monto positivo
    if amount <= 0
      @payment = current_company.employee_payments.build(report_params)
      @payment.user = current_user
      @payment.errors.add(:amount, "debe ser mayor a 0")
      @assigned_gigs = current_user.assigned_gigs.includes(:client).order(date: :desc)
      @gig = current_company.gigs.find_by(id: report_params[:gig_id]) if report_params[:gig_id].present?
      render :new_worker_report, status: :unprocessable_entity and return
    end

    # 2. Validación de asignación y límite del show (Anti-trampa / Hermético)
    gig = nil
    if report_params[:gig_id].present?
      gig = current_company.gigs.find_by(id: report_params[:gig_id])
      assignment = gig&.staff_assignments&.find_by(user_id: current_user.id)

      if assignment.nil?
        @payment = current_company.employee_payments.build(report_params)
        @payment.user = current_user
        @payment.errors.add(:gig_id, "no estás asignado a este evento.")
        @assigned_gigs = current_user.assigned_gigs.includes(:client).order(date: :desc)
        render :new_worker_report, status: :unprocessable_entity and return
      end

      # No permitir reportar más de lo acordado para ese show
      agreed = assignment.agreed_amount.to_f
      already_paid = current_user.employee_payments.approved.where(gig_id: gig.id).sum(:amount).to_f
      max_pending = [agreed - already_paid, agreed].max

      if amount > max_pending && max_pending > 0
        @payment = current_company.employee_payments.build(report_params)
        @payment.user = current_user
        @payment.errors.add(:amount, "no puede exceder el monto acordado para este show (#{view_context.number_to_currency(max_pending, unit: (gig.currency.presence || '$'))})")
        @assigned_gigs = current_user.assigned_gigs.includes(:client).order(date: :desc)
        @gig = gig
        render :new_worker_report, status: :unprocessable_entity and return
      end

      # Evitar reportes duplicados pendientes de aprobación para el mismo show
      if current_user.employee_payments.pending_approval.where(gig_id: gig.id).exists?
        @payment = current_company.employee_payments.build(report_params)
        @payment.user = current_user
        @payment.errors.add(:base, "Ya tienes un reporte de pago en revisión por el líder para este show.")
        @assigned_gigs = current_user.assigned_gigs.includes(:client).order(date: :desc)
        @gig = gig
        render :new_worker_report, status: :unprocessable_entity and return
      end
    end

    # 3. Construcción hermética obligatoria (el trabajador no puede manipular estado ni origen)
    @payment = current_company.employee_payments.build(
      user: current_user,
      gig: gig,
      amount: amount,
      currency: report_params[:currency].presence || gig&.currency.presence || "USD",
      date_paid: report_params[:date_paid].presence || Date.today,
      payment_method: report_params[:payment_method].presence || "Efectivo",
      notes: report_params[:notes],
      status: 'pending_approval',
      reported_by_worker: true,
      funding_source: 'payroll_fund'
    )

    if @payment.save
      redirect_to my_payments_path, notice: "✅ Tu reporte de pago por #{view_context.number_to_currency(@payment.amount, unit: (@payment.currency.presence || '$'))} ha sido registrado y enviado al líder para confirmación."
    else
      @assigned_gigs = current_user.assigned_gigs.includes(:client).order(date: :desc)
      @gig = gig
      render :new_worker_report, status: :unprocessable_entity
    end
  end

  def approve
    ActiveRecord::Base.transaction do
      total_payroll_available = FundAllocation.total_payroll_remaining
      payment_amount = @payment.amount.to_f

      if total_payroll_available >= payment_amount
        # Todo cubierto del fondo de nómina
        @payment.funding_source = 'payroll_fund'
        consume_payroll_funds(@payment.gig, payment_amount, @payment)
      elsif total_payroll_available > 0
        # Parcialmente cubierto de nómina y el resto capital externo automático
        consumed_from_payroll = total_payroll_available
        consume_payroll_funds(@payment.gig, consumed_from_payroll, @payment)
        @payment.funding_source = 'external_capital'
        @payment.external_source_name = "Nómina ($#{consumed_from_payroll}) + Capital personal del leader ($#{payment_amount - consumed_from_payroll})"
      else
        # 0 en fondo de nómina: pasa 100% automáticamente a capital externo del líder
        @payment.funding_source = 'external_capital'
        @payment.external_source_name = 'Capital personal del leader (Fondos nómina en $0)'
      end

      @payment.status = 'approved'
      @payment.approved_at = Time.current
      @payment.save!
    end

    funding_info = @payment.from_external_capital? ? "(#{@payment.funding_source_label})" : "(Fondo Nómina)"
    redirect_back fallback_location: employee_payments_path, notice: "✅ Pago de #{view_context.number_to_currency(@payment.amount, unit: (@payment.currency.presence || '$'))} a #{@payment.user.display_name} confirmado y aprobado exitosamente #{funding_info}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: employee_payments_path, alert: "Error al aprobar pago: #{e.message}"
  end

  def reject
    @payment.status = 'rejected'
    @payment.rejection_reason = params[:rejection_reason].presence || 'Rechazado por el líder.'
    @payment.save!

    redirect_back fallback_location: employee_payments_path, alert: "❌ El reporte de pago de #{@payment.user.display_name} ha sido rechazado."
  end

  def reset_balance
    worker = current_company.users.find(params[:user_id])
    new_balance = params[:new_balance].to_f.round(2)

    current_balance   = worker.pending_balance.round(2)
    adjustment        = (new_balance - current_balance).round(2)

    if adjustment == 0
      redirect_back fallback_location: employee_payments_path(user_id: worker.id),
                    notice: "ℹ️ El saldo de #{worker.display_name} ya está en #{view_context.number_to_currency(new_balance, unit: 'USD')}. No se realizó ningún ajuste."
      return
    end

    # Un ajuste positivo significa que el trabajador aún tiene saldo a favor →
    # debemos "pagarle" virtualmente la diferencia para que el saldo baje al nuevo acordado.
    # Un ajuste negativo significa que pagamos de más en el historial →
    # debemos añadir expected_amount para que el saldo "suba" al nuevo acordado.
    note_text = "[AJUSTE LIDER #{Date.today.strftime('%d/%m/%Y')}] "\
                "Saldo anterior: #{view_context.number_to_currency(current_balance, unit: 'USD')} → "\
                "Nuevo saldo: #{view_context.number_to_currency(new_balance, unit: 'USD')}. Editado directamente por el líder."

    ActiveRecord::Base.transaction do
      if adjustment > 0
        # El saldo actual es menor al nuevo acordado → añadimos expected_amount (deuda adicional)
        # Creamos un pago de ajuste con monto 0 y expected_amount = adjustment
        # para que "agreed total" suba y el saldo aumente correctamente.
        # PERO lo más simple y auditable: creamos un EmployeePayment de "pago virtual"
        # con amount = -adjustment... Rails no admite negativos, así que usamos expected_amount.

        # Estrategia: crear un payment con amount = adjustment (pago ficticio que equilibra)
        # y expected_amount = 0 → esto reduce el saldo pendiente en 'adjustment'
        current_company.employee_payments.create!(
          user:                worker,
          amount:              adjustment,
          expected_amount:     0.0,
          currency:            'USD',
          date_paid:           Date.today,
          payment_method:      'Ajuste contable',
          funding_source:      'external_capital',
          external_source_name: 'Ajuste por el Líder',
          notes:               note_text,
          status:              'approved',
          reported_by_worker:  false
        )
      else
        # El saldo actual es mayor al nuevo acordado (pagamos de más o hay error)
        # → Añadimos expected_amount (deuda virtual) para que el saldo suba al acordado
        abs_adjustment = adjustment.abs
        current_company.employee_payments.create!(
          user:                worker,
          amount:              0.01,         # mínimo técnico para pasar validación > 0
          expected_amount:     abs_adjustment + 0.01,
          currency:            'USD',
          date_paid:           Date.today,
          payment_method:      'Ajuste contable',
          funding_source:      'external_capital',
          external_source_name: 'Ajuste por el Líder',
          notes:               note_text,
          status:              'approved',
          reported_by_worker:  false
        )
      end
    end

    direction = adjustment > 0 ? "↓ reducido" : "↑ corregido"
    redirect_to employee_payments_path(user_id: worker.id),
                notice: "✅ Saldo de #{worker.display_name} #{direction} a #{view_context.number_to_currency(new_balance, unit: 'USD')}. Ajuste registrado por el líder."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: employee_payments_path(user_id: params[:user_id]),
                  alert: "Error al registrar el acuerdo: #{e.message}"
  end

  def new
    @gig = current_company.gigs.find_by(id: params[:gig_id]) if params[:gig_id].present?
    @gigs = current_company.gigs.includes(:client).order(date: :desc)
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
      date_paid: Date.today,
      status: 'approved'
    )
    @payroll_balance = FundAllocation.total_payroll_remaining
    @gig_payroll_balance = @gig&.total_payroll_remaining.to_f
  end

  def create
    @payment = current_company.employee_payments.build(payment_params)
    @payment.status = 'approved'
    payroll_gig = @payment.gig

    if @payment.from_payroll_fund?
      total_payroll_available = FundAllocation.total_payroll_remaining

      if @payment.amount.to_f > total_payroll_available
        formatted_avail = view_context.number_to_currency(total_payroll_available, unit: 'USD')
        @payroll_balance = total_payroll_available
        @gig_payroll_balance = @payment.gig&.total_payroll_remaining.to_f
        @gigs = current_company.gigs.includes(:client).order(date: :desc)
        flash.now[:alert] = "El monto excede el saldo disponible en el fondo de Nómina (#{formatted_avail}). Puedes cambiar el origen a 'Capital Externo (Dinero personal del leader)' para proceder."
        render :new, status: :unprocessable_entity and return
      end
    end

    ActiveRecord::Base.transaction do
      @payment.save!
      consume_payroll_funds(payroll_gig, @payment.amount.to_f, @payment) if @payment.from_payroll_fund?
    end

    worker_name  = @payment.user.display_name rescue @payment.user.email
    currency_sym = @payment.currency.presence || '$'
    amount_label = "#{currency_sym}#{'%.2f' % @payment.amount.to_f}"
    gig_id       = @payment.gig_id

    flash[:payment_success] = {
      message:     "Pago de #{amount_label} a #{worker_name} registrado correctamente.",
      worker_id:   @payment.user_id,
      gig_id:      gig_id
    }.to_json

    redirect_to new_employee_payment_path(user_id: @payment.user_id, gig_id: gig_id)
  rescue ActiveRecord::RecordInvalid
    @payroll_balance = FundAllocation.total_payroll_remaining
    @gig_payroll_balance = @payment.gig&.total_payroll_remaining.to_f
    @gigs = current_company.gigs.includes(:client).order(date: :desc)
    render :new, status: :unprocessable_entity
  end

  def edit
    @gigs = current_company.gigs.includes(:client).order(date: :desc)
    @payroll_balance = FundAllocation.total_payroll_remaining
    @gig_payroll_balance = @payment.gig&.total_payroll_remaining.to_f
  end

  def update
    ActiveRecord::Base.transaction do
      # Revertir los gastos de nómina anteriores asociados a este pago
      @payment.fund_expenses.destroy_all

      @payment.assign_attributes(payment_params)

      if @payment.from_payroll_fund? && @payment.approved?
        total_payroll_available = FundAllocation.total_payroll_remaining

        if @payment.amount.to_f > total_payroll_available
          formatted_avail = view_context.number_to_currency(total_payroll_available, unit: 'USD')
          @payment.errors.add(:amount, "excede el saldo disponible en el fondo de Nómina (#{formatted_avail}). Puedes cambiar el origen a 'Capital Externo'.")
          raise ActiveRecord::RecordInvalid.new(@payment)
        end
      end

      @payment.save!
      consume_payroll_funds(@payment.gig, @payment.amount.to_f, @payment) if @payment.from_payroll_fund? && @payment.approved?
    end

    redirect_to employee_payments_path(user_id: @payment.user_id), notice: "Pago a trabajador actualizado correctamente."
  rescue ActiveRecord::RecordInvalid
    @payroll_balance = FundAllocation.total_payroll_remaining
    @gig_payroll_balance = @payment.gig&.total_payroll_remaining.to_f
    @gigs = current_company.gigs.includes(:client).order(date: :desc)
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
      :funding_source, :external_source_name, :status
    )
    p_params[:expected_amount] = 0.0 if p_params[:expected_amount].blank?
    p_params
  end

  def worker_report_params
    p_params = params.require(:employee_payment).permit(
      :gig_id, :amount, :currency, :date_paid, 
      :payment_method, :notes
    )
    p_params
  end
end
