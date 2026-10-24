# frozen_string_literal: true

module Gigs
  module CloseoutActions
    extend ActiveSupport::Concern

    def closeout
      @remaining_client_balance = @gig.remaining_amount
      @staff_assignments = @gig.staff_assignments.includes(:user)
      @worker_unpaid_items = @staff_assignments.map do |sa|
        {
          assignment: sa,
          user: sa.user,
          agreed: sa.agreed_amount.to_f,
          paid: sa.total_paid.to_f,
          pending: sa.pending_balance.to_f
        }
      end
      @total_pending_payroll = @worker_unpaid_items.sum { |item| item[:pending] }

      @active_goals = current_company.reinvestment_goals.active.order(priority: :desc, created_at: :desc)
      @primary_goal = @active_goals.first
      if @primary_goal.present?
        @recommendation_service = GoalRecommendationService.new(company: current_company, gig: @gig, goal: @primary_goal)
        @smart_recommendations = @recommendation_service.smart_recommendations
      end
    end

    def process_closeout
      client_amount = params[:client_collected_amount].to_s.tr(',', '.').strip.to_f
      client_payment_method = params[:client_payment_method].presence || 'cash'
      client_reference = params[:client_reference_number].presence
      client_notes = params[:client_payment_notes].presence || "Liquidación de cierre de evento"

      worker_payments_data = params[:worker_payments] || {}
      fund_allocation_amount = params[:fund_amount].to_s.tr(',', '.').strip.to_f
      fund_notes = params[:fund_notes].presence || "Ingreso de remanente por cierre de evento: #{@gig.client_display_name}"

      save_to_goal = params[:deposit_to_goal] == '1' || params[:deposit_to_goal] == true
      goal_id = params[:reinvestment_goal_id].presence
      goal_amount = params[:goal_amount].to_s.tr(',', '.').strip.to_f
      goal_notes = params[:goal_notes].presence || "Aporte de ganancia neta por cierre de show: #{@gig.client_display_name}"

      ActiveRecord::Base.transaction do
        # 1. Registrar cobro del cliente si se cobró dinero hoy
        if client_amount > 0
          @gig.gig_payments.create!(
            amount: client_amount,
            currency: @gig.currency.presence || 'USD',
            date_paid: Date.today,
            payment_method: client_payment_method,
            reference_number: client_reference,
            notes: client_notes,
            status: 'approved',
            audit_reason: "Cierre de Show: Cobro de $#{client_amount} (#{client_payment_method})"
          )
        end

        # 2. Registrar pagos a trabajadores seleccionados
        worker_payments_data.each do |user_id, w_data|
          next unless w_data[:pay] == '1' || w_data[:pay] == true
          w_amt = w_data[:amount].to_s.tr(',', '.').strip.to_f
          next if w_amt <= 0

          user = current_company.users.find(user_id)
          w_method = w_data[:payment_method].presence || 'Efectivo'
          w_notes = w_data[:notes].presence || "Pago liquidado en tarima / cierre de show"

          current_company.employee_payments.create!(
            user: user,
            gig: @gig,
            amount: w_amt,
            currency: @gig.currency.presence || 'USD',
            date_paid: Date.today,
            payment_method: w_method,
            notes: w_notes,
            funding_source: 'payroll_fund',
            status: 'approved',
            audit_reason: "Cierre de Show: Pago a #{user.display_name} de $#{w_amt} (#{w_method})"
          )
        end

        # 3. Asignar excedente a la Meta de Reinversión seleccionada
        if save_to_goal && goal_id.present? && goal_amount > 0
          target_goal = current_company.reinvestment_goals.find_by(id: goal_id)
          if target_goal
            target_goal.goal_savings_contributions.create!(
              amount: goal_amount,
              currency: @gig.currency.presence || 'USD',
              date: Date.today,
              user: current_user,
              gig: @gig,
              notes: goal_notes
            )
          end
        end

        # 4. Asignar excedente al Fondo de la Empresa / Caja si se especificó
        if fund_allocation_amount > 0 && (params[:deposit_to_fund] == '1' || params[:deposit_to_fund] == true)
          current_company.cash_adjustments.create!(
            user: current_user,
            amount: fund_allocation_amount,
            currency: @gig.currency.presence || 'USD',
            adjustment_type: :deposit,
            date: Date.today,
            description: fund_notes,
            status: 'approved',
            audit_reason: "Cierre de Show: Aporte al fondo de $#{fund_allocation_amount}"
          )
        end
      end

      redirect_to gig_path(@gig), notice: "🏁 Cierre de evento realizado exitosamente. Cobros, nóminas y balances actualizados."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to closeout_gig_path(@gig), alert: "Error al procesar el cierre: #{e.message}"
    rescue StandardError => e
      redirect_to closeout_gig_path(@gig), alert: "Ocurrió un problema: #{e.message}"
    end
  end
end
