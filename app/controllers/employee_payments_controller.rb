# frozen_string_literal: true

class EmployeePaymentsController < ApplicationController
  include EmployeePayments::WorkerReporting
  include EmployeePayments::LeaderActions

  before_action :require_leader!, except: [:new_worker_report, :create_worker_report, :receipt]
  before_action -> { require_module!(:payroll) }
  before_action :set_payment, only: [:edit, :update, :destroy, :approve, :reject, :void, :receipt]

  def index
    @financial_scope = params[:scope].presence || params[:financial_scope].presence || (current_company.financial_reset_active? ? 'current_cycle' : 'all_time')

    @payments = current_company.employee_payments.includes(:user, :gig).where.not(payment_method: 'Ajuste contable').order(date_paid: :desc, created_at: :desc)
    @pending_approvals = current_company.employee_payments.pending_approval.includes(:user, :gig).order(created_at: :desc)

    @worker_metrics = WorkerBalanceService.build_metrics_for_company(current_company)
    @total_payroll_paid = @worker_metrics.sum { |m| m[:total_paid] }.to_f

    if params[:user_id].present?
      @payments = @payments.where(user_id: params[:user_id])
      @selected_worker = current_company.users.find_by(id: params[:user_id])
    end

    if params[:status].present?
      @payments = @payments.where(status: params[:status])
    end
  end

  def new
    @gig = current_company.gigs.find_by(id: params[:gig_id]) if params[:gig_id].present?
    @worker_unpaid_gigs_map = build_worker_unpaid_gigs_map
    
    selected_worker_id = params[:user_id].presence
    if selected_worker_id.present?
      @selected_worker = current_company.users.find_by(id: selected_worker_id)
      @available_gigs = @worker_unpaid_gigs_map[@selected_worker&.id] || []
      if @gig.present? && !@available_gigs.any? { |g| g[:id] == @gig.id }
        assignment = @gig.staff_assignments.find_by(user_id: selected_worker_id)
        pending_val = assignment&.pending_balance.to_f
        client_name = @gig.client&.name || "Show"
        date_str = @gig.date ? @gig.date.strftime('%d/%m/%Y') : 'Sin fecha'
        show_or_event = current_company&.venue_mode? ? "Evento" : "Show"
        status_label = @gig.has_not_occurred? ? "📅 Próximo #{show_or_event}: #{view_context.number_to_currency(pending_val, unit: '$')} al celebrarse" : "⏳ Pendiente: #{view_context.number_to_currency(pending_val, unit: '$')}"
        @available_gigs << {
          id: @gig.id,
          title: "#{client_name} - #{date_str} (#{status_label})",
          pending_amount: pending_val,
          currency: "USD"
        }
      end
    else
      @available_gigs = []
    end

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
      @worker_unpaid_gigs_map = build_worker_unpaid_gigs_map
      @selected_worker = @payment.user
      @available_gigs = @worker_unpaid_gigs_map[@selected_worker&.id] || []
      flash.now[:alert] = "Error al registrar el pago: #{@payment.errors.full_messages.to_sentence}"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @worker_unpaid_gigs_map = build_worker_unpaid_gigs_map
    @selected_worker = @payment.user
    @available_gigs = (@worker_unpaid_gigs_map[@selected_worker&.id] || []).dup
    if @payment.gig.present? && !@available_gigs.any? { |g| g[:id] == @payment.gig_id }
      assignment = @payment.gig.staff_assignments.find_by(user_id: @payment.user_id)
      pending_val = assignment&.pending_balance.to_f
      client_name = @payment.gig.client&.name || "Show"
      date_str = @payment.gig.date ? @payment.gig.date.strftime('%d/%m/%Y') : 'Sin fecha'
      @available_gigs.unshift({
        id: @payment.gig_id,
        title: "#{client_name} - #{date_str} (Show actual de este pago)",
        pending_amount: pending_val,
        currency: @payment.gig.currency.presence || "USD"
      })
    end
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
      @worker_unpaid_gigs_map = build_worker_unpaid_gigs_map
      @selected_worker = @payment.user
      @available_gigs = @worker_unpaid_gigs_map[@selected_worker&.id] || []
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
    if current_user.staff? || current_user.musician?
      @payment = current_company.employee_payments.where(user_id: current_user.id).find(params[:id])
    else
      @payment = current_company.employee_payments.find(params[:id])
    end
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
end
