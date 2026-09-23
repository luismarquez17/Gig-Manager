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
    PAYMENT_METHODS[payment_method] || payment_method.to_s.titleize.presence || "Manual"
  end

  def approve!
    ActiveRecord::Base.transaction do
      update!(status: 'approved', approved_at: Time.current)
      
      base_date = if company&.trial_ends_at.present? && company.trial_ends_at > Time.current
                    company.trial_ends_at
                  else
                    Time.current
                  end

      company&.update!(
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
    formatted_num = user&.formatted_phone_for_whatsapp.presence ||
                    company&.whatsapp_number.to_s.gsub(/\D/, '').presence ||
                    company&.contact_phone.to_s.gsub(/\D/, '').presence
    return nil if formatted_num.blank?

    if formatted_num.start_with?('0') && formatted_num.length == 11
      formatted_num = "58#{formatted_num[1..]}"
    elsif formatted_num.length == 10 && formatted_num.start_with?('4')
      formatted_num = "58#{formatted_num}"
    end

    user_name = user&.display_name.presence || company&.name.presence || "Cliente"
    text = "Hola *#{user_name}*! 👋 Tu pago de *$#{'%.2f' % amount.to_f} USD* vía #{payment_method_label} (Ref: #{reference_number}) ha sido verificado exitosamente y tu suscripción a Gig Manager (Plan #{plan_tier.to_s.capitalize}) está *ACTIVA*."
    "https://wa.me/#{formatted_num}?text=#{ERB::Util.url_encode(text)}"
  rescue => e
    Rails.logger.error "[SubscriptionPayment#whatsapp_confirmation_url] #{e.message}"
    nil
  end
end
