module Superadmin
  class SubscriptionPaymentsController < BaseController
    before_action :set_payment, only: [:approve, :reject]

    def index
      @pending_payments = SubscriptionPayment.includes(:company, :user).pending.order(created_at: :desc)
      @recent_payments = SubscriptionPayment.includes(:company, :user).where.not(status: 'pending').order(updated_at: :desc).limit(20)
    end

    def approve
      @payment.approve!
      wa_url = @payment.whatsapp_confirmation_url
      if wa_url.present?
        redirect_to superadmin_subscription_payments_path, notice: "✅ Pago ##{@payment.reference_number} de #{@payment.company.name} APROBADO exitosamente. <a href='#{wa_url}' target='_blank' class='underline font-bold text-emerald-300 ml-2'>Enviar WhatsApp de Confirmación 💬</a>".html_safe
      else
        redirect_to superadmin_subscription_payments_path, notice: "✅ Pago ##{@payment.reference_number} de #{@payment.company.name} APROBADO exitosamente."
      end
    rescue => e
      redirect_to superadmin_subscription_payments_path, alert: "Error al aprobar pago: #{e.message}"
    end

    def reject
      @payment.reject!(params[:reason].presence || "No fue posible verificar el número de referencia.")
      redirect_to superadmin_subscription_payments_path, alert: "❌ Pago ##{@payment.reference_number} rechazado."
    end

    private

    def set_payment
      @payment = SubscriptionPayment.find(params[:id])
    end
  end
end
