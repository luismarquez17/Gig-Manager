module Superadmin
  class SubscriptionPaymentsController < BaseController
    before_action :set_payment, only: [:approve, :reject]

    def index
      @pending_payments = SubscriptionPayment.includes(:company, :user).pending.order(created_at: :desc)
      @recent_payments = SubscriptionPayment.includes(:company, :user).where.not(status: 'pending').order(updated_at: :desc).limit(20)
    end

    def pending_summary
      pending = SubscriptionPayment.includes(:company, :user).pending.order(created_at: :desc)
      latest = pending.first
      render json: {
        pending_count: pending.count,
        latest_id: latest&.id,
        latest_company: latest&.company&.name,
        latest_amount: latest ? sprintf("%.2f", latest.amount.to_f) : nil,
        latest_method: latest&.payment_method_label,
        latest_reference: latest&.reference_number,
        has_voucher: latest&.voucher_attached? || false
      }
    end

    def approve
      @payment.approve!(current_user)
      wa_url = @payment.whatsapp_confirmation_url
      company_name = @payment.company&.name || "Empresa"
      if wa_url.present?
        redirect_to superadmin_subscription_payments_path, notice: "✅ Pago ##{@payment.reference_number} de #{company_name} APROBADO exitosamente. <a href='#{wa_url}' target='_blank' style='text-decoration: underline; font-weight: 800; color: #065f46; margin-left: 6px;'>Enviar WhatsApp de Confirmación 💬</a>".html_safe
      else
        redirect_to superadmin_subscription_payments_path, notice: "✅ Pago ##{@payment.reference_number} de #{company_name} APROBADO exitosamente."
      end
    rescue => e
      redirect_to superadmin_subscription_payments_path, alert: "Error al aprobar pago: #{e.message}"
    end

    def reject
      reason = params[:reason].presence || "No fue posible verificar el comprobante o número de referencia."
      @payment.reject!(reason, current_user)
      redirect_to superadmin_subscription_payments_path, alert: "❌ Pago ##{@payment.reference_number} rechazado."
    end

    private

    def set_payment
      @payment = SubscriptionPayment.find(params[:id])
    end
  end
end
