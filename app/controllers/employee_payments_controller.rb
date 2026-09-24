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

    @worker_metrics = WorkerBalanceService.build_metrics_for_company(current_company)
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
      @payment.funding_source = 'payroll_fund' if @payment.funding_source.blank?
      @payment.status = 'approved'
      @payment.approved_at = Time.current
      @payment.save!
    end

    target_area = @payment.user.musician? ? 'musicians' : 'staffs'
    AppNotification.create(
      company: current_company,
      sender: current_user,
      target_area: target_area,
      notification_type: 'payment_alert',
      title: "Pago Aprobado",
      message: "Tu pago de $#{@payment.amount} (#{@payment.gig ? 'Show: ' + (@payment.gig.client&.name || @payment.gig.date.to_s) : 'Pago directo'}) ha sido aprobado.",
      action_url: "/my_payments"
    ) rescue nil

    redirect_back fallback_location: employee_payments_path, notice: "✅ Pago de #{view_context.number_to_currency(@payment.amount, unit: (@payment.currency.presence || '$'))} a #{@payment.user.display_name} confirmado y aprobado exitosamente."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: employee_payments_path, alert: "Error al aprobar pago: #{e.message}"
  end

  def reject
    @payment.status = 'rejected'
    @payment.rejection_reason = params[:rejection_reason].presence || 'Rechazado por el líder.'
    @payment.save!

    target_area = @payment.user.musician? ? 'musicians' : 'staffs'
    AppNotification.create(
      company: current_company,
      sender: current_user,
      target_area: target_area,
      notification_type: 'urgent',
      title: "Reporte de Pago Rechazado",
      message: "Tu reporte de pago de $#{@payment.amount} ha sido rechazado: #{@payment.rejection_reason}",
      action_url: "/my_payments"
    ) rescue nil

    redirect_back fallback_location: employee_payments_path, alert: "❌ El reporte de pago de #{@payment.user.display_name} ha sido rechazado."
  end

  def reset_balance
    worker = current_company.users.find(params[:user_id])
    mode   = params[:adjustment_mode].presence || 'company_debt'

    # Calcular situación actual de shows pasados
    today       = Date.today
    assignments = StaffAssignment.where(user_id: worker.id).includes(:gig)
    all_payments = worker.employee_payments.approved.to_a
    paid_by_gig = worker.employee_payments.approved.where.not(gig_id: nil).group(:gig_id).sum(:amount)

    raw_past_balance = assignments.sum do |sa|
      next 0 unless sa.gig.present?
      unpaid = sa.agreed_amount.to_f - paid_by_gig[sa.gig_id].to_f
      unpaid > 0 ? unpaid : 0
    end

    raw_past_overpaid = assignments.sum do |sa|
      next 0 unless sa.gig.present?
      excess = paid_by_gig[sa.gig_id].to_f - sa.agreed_amount.to_f
      excess > 0 ? excess : 0
    end

    net_adjustment_credits = all_payments
      .select { |p| p.gig_id.nil? }
      .sum { |p| p.amount.to_f - p.expected_amount.to_f }

    current_net_diff = (raw_past_balance - raw_past_overpaid - net_adjustment_credits).round(2)
    current_company_debt = [current_net_diff, 0].max
    current_worker_owes   = [-current_net_diff, 0].max

    target_net_diff = case mode
    when 'settle_all'
      0.0
    when 'worker_owes'
      w_owes = params[:worker_owes].to_f.round(2)
      -w_owes
    else # 'company_debt'
      c_debt = params[:company_debt].presence || params[:new_balance]
      c_debt.to_f.round(2)
    end

    delta = (target_net_diff - current_net_diff).round(2)

    if delta == 0
      redirect_back fallback_location: employee_payments_path(user_id: worker.id),
                    notice: "ℹ️ El saldo de #{worker.display_name} ya está en el valor indicado. No se requirió ningún ajuste."
      return
    end

    note_text = case mode
    when 'settle_all'
      "[AJUSTE LÍDER #{Date.today.strftime('%d/%m/%Y')}] Saldado completamente: $0.00 en ambos apartados."
    when 'worker_owes'
      target_val = -target_net_diff
      "[AJUSTE LÍDER #{Date.today.strftime('%d/%m/%Y')}] 'Nos debe' ajustado: #{view_context.number_to_currency(current_worker_owes, unit: 'USD')} → #{view_context.number_to_currency(target_val, unit: 'USD')}."
    else
      "[AJUSTE LÍDER #{Date.today.strftime('%d/%m/%Y')}] Deuda empresa ajustada: #{view_context.number_to_currency(current_company_debt, unit: 'USD')} → #{view_context.number_to_currency(target_net_diff, unit: 'USD')}."
    end

    ActiveRecord::Base.transaction do
      if delta > 0
        # Aumentar saldo a favor del trabajador (disminuir lo que nos debe o aumentar deuda de la empresa)
        current_company.employee_payments.create!(
          user:                 worker,
          amount:               0.01,
          expected_amount:      delta + 0.01,
          gig_id:               nil,
          currency:             'USD',
          date_paid:            Date.today,
          payment_method:       'Ajuste contable',
          funding_source:       'external_capital',
          external_source_name: 'Ajuste por el Líder',
          notes:                note_text,
          status:               'approved',
          reported_by_worker:   false
        )
      else
        # delta < 0: Disminuir saldo a favor del trabajador (pagar shows pendientes o registrar exceso/anticipo)
        remaining_adj = delta.abs

        past_assignments = assignments
          .select { |sa| sa.gig.present? }
          .sort_by { |sa| sa.gig.date || today }

        past_assignments.each do |sa|
          break if remaining_adj <= 0
          paid_for_gig = worker.employee_payments.approved.where(gig_id: sa.gig_id).sum(:amount).to_f
          pending_gig  = sa.agreed_amount.to_f - paid_for_gig
          next if pending_gig <= 0

          portion = [remaining_adj, pending_gig].min.round(2)
          next if portion <= 0

          gig_note = "#{note_text} (Show: #{sa.gig.client&.name.presence || sa.gig.date&.strftime('%d/%m/%Y')})"
          current_company.employee_payments.create!(
            user:                 worker,
            amount:               portion,
            expected_amount:      0.0,
            gig_id:               sa.gig_id,
            currency:             'USD',
            date_paid:            Date.today,
            payment_method:       'Ajuste contable',
            funding_source:       'external_capital',
            external_source_name: 'Ajuste por el Líder',
            notes:                gig_note,
            status:               'approved',
            reported_by_worker:   false
          )
          remaining_adj = (remaining_adj - portion).round(2)
        end

        if remaining_adj > 0
          current_company.employee_payments.create!(
            user:                 worker,
            amount:               remaining_adj,
            expected_amount:      0.0,
            gig_id:               nil,
            currency:             'USD',
            date_paid:            Date.today,
            payment_method:       'Ajuste contable',
            funding_source:       'external_capital',
            external_source_name: 'Ajuste por el Líder',
            notes:                note_text,
            status:               'approved',
            reported_by_worker:   false
          )
        end
      end
    end

    notice_msg = if target_net_diff > 0
      "✅ Saldo de #{worker.display_name} ajustado: la empresa le debe #{view_context.number_to_currency(target_net_diff, unit: 'USD')}."
    elsif target_net_diff < 0
      "✅ Saldo de #{worker.display_name} ajustado: el trabajador nos debe #{view_context.number_to_currency(-target_net_diff, unit: 'USD')}."
    else
      "✅ Saldo de #{worker.display_name} saldado completamente ($0.00). El trabajador está al día."
    end

    redirect_to employee_payments_path(user_id: worker.id), notice: notice_msg
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: employee_payments_path(user_id: params[:user_id]),
                  alert: "Error al registrar el ajuste: #{e.message}"
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
      status: 'approved',
      funding_source: 'payroll_fund'
    )
  end

  def create
    @payment = current_company.employee_payments.build(payment_params)
    @payment.status = 'approved'
    @payment.funding_source = 'payroll_fund' if @payment.funding_source.blank?
    if @payment.from_external_capital? && @payment.external_source_name.blank?
      @payment.external_source_name = params.dig(:employee_payment, :external_source_name).presence || 'Capital personal del leader'
    end

    if @payment.save
      worker_name  = @payment.user.display_name rescue @payment.user.email
      currency_sym = @payment.currency.presence || '$'
      amount_label = "#{currency_sym}#{'%.2f' % @payment.amount.to_f}"

      redirect_to employee_payments_path(user_id: @payment.user_id),
                  notice: "✅ Pago de #{amount_label} a #{worker_name} registrado y aplicado a su cuenta correctamente."
    else
      @gigs = current_company.gigs.includes(:client).order(date: :desc)
      flash.now[:alert] = "Error al registrar el pago: #{@payment.errors.full_messages.to_sentence}"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @gigs = current_company.gigs.includes(:client).order(date: :desc)
  end

  def update
    @payment.assign_attributes(payment_params)
    @payment.funding_source = 'payroll_fund' if @payment.funding_source.blank?
    if @payment.from_external_capital? && @payment.external_source_name.blank?
      @payment.external_source_name = params.dig(:employee_payment, :external_source_name).presence || 'Capital personal del leader'
    end

    if @payment.save
      redirect_to employee_payments_path(user_id: @payment.user_id), notice: "Pago a trabajador actualizado correctamente."
    else
      @gigs = current_company.gigs.includes(:client).order(date: :desc)
      flash.now[:alert] = "Error al actualizar el pago: #{@payment.errors.full_messages.to_sentence}"
      render :edit, status: :unprocessable_entity
    end
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

  def payment_params
    p_params = params.require(:employee_payment).permit(
      :user_id, :gig_id, :amount, :currency, :date_paid, 
      :payment_method, :notes, :expected_amount, 
      :funding_source, :external_source_name, :status
    )
    p_params[:amount] = p_params[:amount].to_s.tr(',', '.').strip if p_params[:amount].present?
    p_params[:expected_amount] = p_params[:expected_amount].to_s.tr(',', '.').strip if p_params[:expected_amount].present?
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
