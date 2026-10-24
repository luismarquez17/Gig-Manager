# frozen_string_literal: true

module EmployeePayments
  module WorkerReporting
    extend ActiveSupport::Concern

    def new_worker_report
      assignments = current_user.staff_assignments.includes(gig: :client)
      unpaid_assignments = assignments.select { |sa| sa.pending_balance > 0 && sa.gig.present? }
      @assigned_gigs = unpaid_assignments.map(&:gig)
      @gig = current_company.gigs.find_by(id: params[:gig_id]) if params[:gig_id].present?
      if @gig.present? && !@assigned_gigs.include?(@gig)
        @assigned_gigs.unshift(@gig)
      end
      
      default_amount = nil
      if @gig.present?
        assignment = @gig.staff_assignments.find_by(user_id: current_user.id)
        if assignment.present?
          pending_gig_bal = assignment.pending_balance
          default_amount = pending_gig_bal.positive? ? pending_gig_bal : assignment.agreed_amount.to_f
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
          @payment.errors.add(:amount, "no puede exceder el monto acordado para este show (#{view_context.number_to_currency(max_pending, unit: '$')})")
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
        amount_formatted = view_context.number_to_currency(@payment.amount, unit: '$')
        show_label = @payment.gig.present? ? (@payment.gig.client&.name || "Show del #{@payment.gig.date&.strftime('%d/%m/%Y')}") : "Pago general / Anticipo"
        notes_info = @payment.notes.present? ? " Notas: \"#{@payment.notes}\"." : ""

        AppNotification.create(
          company: current_company,
          sender: current_user,
          target_area: 'leaders',
          notification_type: 'payment_alert',
          title: "💰 Reporte de Pago: #{current_user.display_name} reportó #{amount_formatted}",
          message: "#{current_user.display_name} indicó haber recibido #{amount_formatted} el #{@payment.date_paid&.strftime('%d/%m/%Y')} vía #{@payment.payment_method || 'Efectivo'} (#{show_label}).#{notes_info} Confirma si ya se le realizó este pago.",
          action_url: "/employee_payments?status=pending_approval"
        ) rescue nil

        redirect_to my_payments_path, notice: "✅ Tu reporte de pago por #{amount_formatted} ha sido registrado y enviado al líder para confirmación."
      else
        @assigned_gigs = current_user.assigned_gigs.includes(:client).order(date: :desc)
        @gig = gig
        render :new_worker_report, status: :unprocessable_entity
      end
    end

    private

    def worker_report_params
      params.require(:employee_payment).permit(
        :gig_id, :amount, :currency, :date_paid, 
        :payment_method, :notes
      )
    end
  end
end
