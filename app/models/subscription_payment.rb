class SubscriptionPayment < ApplicationRecord
  belongs_to :company
  belongs_to :user

  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }

  validates :payment_method, :reference_number, :amount, presence: true

  PAYMENT_METHODS = {
    "zelle" => "🇺🇸 Zelle (USD)",
    "binance" => "🔶 Binance Pay (USDT)",
    "pago_movil" => "🇻🇪 Pago Móvil (Tasa BCV)",
    "transferencia" => "🏦 Transferencia Bancaria (VES / USD)"
  }.freeze

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def payment_method_label
    PAYMENT_METHODS[payment_method] || payment_method.titleize
  end

  def approve!
    ActiveRecord::Base.transaction do
      update!(status: 'approved', approved_at: Time.current)
      
      base_date = if company.trial_ends_at.present? && company.trial_ends_at > Time.current
                    company.trial_ends_at
                  else
                    Time.current
                  end

      company.update!(
        subscription_status: 'active',
        plan_tier: plan_tier,
        trial_ends_at: base_date + 30.days
      )
    end
  end

  def reject!(reason = nil)
    update!(status: 'rejected', notes: reason)
  end

  def whatsapp_confirmation_url
    return nil unless user&.formatted_phone_for_whatsapp.present?
    text = "Hola *#{user.display_name}*! 👋 Tu pago de *$#{'%.2f' % amount} USD* vía #{payment_method_label} (Ref: #{reference_number}) ha sido verificado exitosamente y tu suscripción a Gig Manager (Plan #{plan_tier.to_s.capitalize}) está *ACTIVA*."
    user.whatsapp_url(text: text)
  end
end
