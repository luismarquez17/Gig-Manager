# frozen_string_literal: true

module Pages
  module WorkerPortal
    extend ActiveSupport::Concern

    def my_payments
      unless current_user.staff? || current_user.musician? || current_user.leader? || current_user.superadmin?
        redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
        return
      end

      @worker = if (current_user.leader? || current_user.superadmin?) && params[:user_id].present?
                  current_company.users.find_by(id: params[:user_id]) || current_user
                else
                  current_user
                end

      @employee_payments = @worker.employee_payments.includes(:gig).order(created_at: :desc)
      @worker_payment_items = @worker.worker_payment_items
      @total_expected = @worker.total_agreed_amount
      @total_paid = @worker.total_paid_amount
      @total_owed = @worker.pending_balance
    end
  end
end
