# frozen_string_literal: true

module EmployeePayments
  module LeaderActions
    extend ActiveSupport::Concern

    def approve
      ActiveRecord::Base.transaction do
        @payment.funding_source = 'payroll_fund' if @payment.funding_source.blank?
        @payment.status = 'approved'
        @payment.approved_at = Time.current
        @payment.save!
      end

      target_area = @payment.user.musician? ? 'musicians' : 'staffs'
      amount_formatted = view_context.number_to_currency(@payment.amount, unit: '$')
      show_label = @payment.gig.present? ? (@payment.gig.client&.name || "Show del #{@payment.gig.date&.strftime('%d/%m/%Y')}") : "Pago general"

      AppNotification.create(
        company: current_company,
        sender: current_user,
        recipient: @payment.user,
        target_area: target_area,
        notification_type: 'payment_alert',
        title: "✅ Pago Confirmado",
        message: "Tu reporte de pago de #{amount_formatted} (#{show_label}) ha sido confirmado y aprobado por el líder. Tu balance ha sido actualizado.",
        action_url: "/my_payments"
      ) rescue nil

      redirect_back fallback_location: employee_payments_path, notice: "✅ Pago de #{amount_formatted} a #{@payment.user.display_name} confirmado y aprobado exitosamente."
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: employee_payments_path, alert: "Error al aprobar pago: #{e.message}"
    end

    def reject
      @payment.status = 'rejected'
      @payment.rejection_reason = params[:rejection_reason].presence || 'Rechazado por el líder.'
      @payment.save!

      target_area = @payment.user.musician? ? 'musicians' : 'staffs'
      amount_formatted = view_context.number_to_currency(@payment.amount, unit: '$')

      AppNotification.create(
        company: current_company,
        sender: current_user,
        recipient: @payment.user,
        target_area: target_area,
        notification_type: 'urgent',
        title: "❌ Reporte de Pago Rechazado",
        message: "Tu reporte de pago de #{amount_formatted} no fue aceptado: #{@payment.rejection_reason}",
        action_url: "/my_payments"
      ) rescue nil

      redirect_back fallback_location: employee_payments_path, alert: "❌ El reporte de pago de #{@payment.user.display_name} ha sido rechazado."
    end

    def void
      reason = params[:void_reason].presence || params[:reason].presence || "Anulación contable solicitada por el líder"
      @payment.void!(reason, current_user)
      redirect_back fallback_location: employee_payments_path(user_id: @payment.user_id), notice: "🚫 Pago de nómina ##{@payment.receipt_display_number} anulado exitosamente."
    rescue StandardError => e
      redirect_back fallback_location: employee_payments_path, alert: "Error al anular: #{e.message}"
    end

    def receipt
      @gig = @payment.gig
      @worker = @payment.user
      @company = @payment.company || current_company
      render layout: false
    end

    def reset_balance
      worker = current_company.users.find_by(id: params[:user_id])
      unless worker
        redirect_back fallback_location: employee_payments_path, alert: "Trabajador no encontrado.", status: :see_other and return
      end

      mode = params[:adjustment_mode].presence || 'company_debt'

      # Calcular situación actual de shows pasados
      today        = Date.today
      assignments  = StaffAssignment.joins(:gig).where(gigs: { company_id: current_company.id }, user_id: worker.id).includes(:gig)
      all_payments = current_company.employee_payments.approved.where(user_id: worker.id).to_a

      balance_service = WorkerBalanceService.new(
        worker: worker,
        worker_payments: all_payments,
        worker_assignments: assignments,
        today: today
      )

      current_company_debt = balance_service.past_balance
      current_worker_owes  = balance_service.overpaid
      current_net_diff     = (current_company_debt - current_worker_owes).round(2)

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
                      notice: "ℹ️ El saldo de #{worker.display_name} ya está en el valor indicado. No se requirió ningún ajuste.",
                      status: :see_other
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
            amount:               0.0,
            expected_amount:      delta,
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
          # delta < 0: Disminuir saldo a favor del trabajador (disminuir deuda de la empresa o aumentar lo que nos debe)
          current_company.employee_payments.create!(
            user:                 worker,
            amount:               delta.abs,
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

      notice_msg = if target_net_diff > 0
        "✅ Saldo de #{worker.display_name} ajustado: la empresa le debe #{view_context.number_to_currency(target_net_diff, unit: 'USD')}."
      elsif target_net_diff < 0
        "✅ Saldo de #{worker.display_name} ajustado: el trabajador nos debe #{view_context.number_to_currency(-target_net_diff, unit: 'USD')}."
      else
        "✅ Saldo de #{worker.display_name} saldado completamente ($0.00). El trabajador está al día."
      end

      redirect_to employee_payments_path(user_id: worker.id), notice: notice_msg, status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: employee_payments_path(user_id: params[:user_id]),
                    alert: "Error al registrar el ajuste: #{e.message}",
                    status: :see_other
    end

    private

    def build_worker_unpaid_gigs_map
      workers = current_company.users.workers
      worker_ids = workers.pluck(:id)
      
      assignments = StaffAssignment.where(user_id: worker_ids).includes(:user, gig: :client)
      
      map = {}
      workers.each do |w|
        worker_assignments = assignments.select { |sa| sa.user_id == w.id && sa.gig.present? }
        unpaid = worker_assignments.select { |sa| sa.pending_balance > 0 }
        
        map[w.id] = unpaid.map do |sa|
          client_name = sa.gig.client&.name || "Show"
          date_str = sa.gig.date ? sa.gig.date.strftime('%d/%m/%Y') : 'Sin fecha'
          pending_str = view_context.number_to_currency(sa.pending_balance, unit: '$')
          show_or_event = current_company&.venue_mode? ? "Evento" : "Show"
          status_label = sa.gig.has_not_occurred? ? "📅 Próximo #{show_or_event}: #{pending_str} al celebrarse" : "⏳ Pendiente: #{pending_str}"
          {
            id: sa.gig_id,
            title: "#{client_name} - #{date_str} (#{status_label})",
            pending_amount: sa.pending_balance,
            currency: "USD"
          }
        end
      end
      map
    end
  end
end
