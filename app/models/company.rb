class Company < ApplicationRecord
  enum status: { active: 0, suspended: 1, past_due: 2, trial: 3 }

  has_many :users, dependent: :destroy
  has_many :clients, dependent: :destroy
  has_many :gigs, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :kits, dependent: :destroy
  has_many :investments, dependent: :destroy
  has_many :preset_budgets, dependent: :destroy
  has_many :standard_upsells, dependent: :destroy
  has_many :shopping_items, dependent: :destroy
  has_many :finance_settings, dependent: :destroy
  has_many :employee_payments, dependent: :destroy
  has_many :subscription_payments, dependent: :destroy
  has_many :gig_upsell_requests, dependent: :destroy
  has_many :client_quotes, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :invitation_token, uniqueness: true, allow_nil: true
  validates :monthly_fee, numericality: { greater_than_or_equal_to: 0 }

  before_validation :generate_slug_and_token, on: :create
  before_create :set_default_trial_period

  def set_default_trial_period
    self.trial_started_at ||= Time.current
    self.trial_ends_at ||= 30.days.from_now
    self.subscription_status ||= "trialing"
    self.plan_tier ||= "starter"
  end

  def trial_active?
    subscription_status == "trialing" && trial_ends_at.present? && trial_ends_at > Time.current
  end

  def trial_expired?
    subscription_status == "trialing" && trial_ends_at.present? && trial_ends_at <= Time.current
  end

  def days_left_in_trial
    return 0 unless trial_ends_at.present? && trial_ends_at > Time.current
    ((trial_ends_at - Time.current) / 1.day).ceil
  end

  def active_subscription?
    subscription_status == "active"
  end

  def access_granted?
    return true if active_subscription? || trial_active?
    false
  end

  def leaders
    users.where(role: [:leader, :superadmin])
  end

  def primary_leader
    leaders.first
  end

  def regenerate_token!
    update!(invitation_token: SecureRandom.hex(12))
  end

  def status_badge_class
    case status.to_sym
    when :active
      "bg-emerald-500/10 text-emerald-400 border-emerald-500/20"
    when :suspended
      "bg-rose-500/10 text-rose-400 border-rose-500/20"
    when :past_due
      "bg-amber-500/10 text-amber-400 border-amber-500/20"
    when :trial
      "bg-blue-500/10 text-blue-400 border-blue-500/20"
    else
      "bg-slate-500/10 text-slate-400 border-slate-500/20"
    end
  end

  DEFAULT_PAYMENT_METHODS = {
    "zelle" => {
      "enabled" => true,
      "email" => "",
      "holder_name" => "",
      "bank" => "",
      "notes" => "Indicar el nombre del titular o evento en la descripción de Zelle."
    },
    "binance" => {
      "enabled" => true,
      "pay_id" => "",
      "email" => "",
      "network" => "USDT (TRC20 / BEP20)",
      "nickname" => "",
      "notes" => "Transferencia directa por Binance Pay sin comisiones."
    },
    "pago_movil" => {
      "enabled" => true,
      "bank" => "",
      "id_number" => "",
      "phone" => "",
      "holder_name" => "",
      "notes" => "Calcular al monto en Bolívares según la tasa del día."
    },
    "bank_transfer" => {
      "enabled" => false,
      "bank" => "",
      "account_number" => "",
      "account_type" => "Corriente",
      "id_number" => "",
      "holder_name" => "",
      "notes" => ""
    },
    "general_instructions" => "Una vez realizado tu pago o anticipo, por favor envía el capture o comprobante por WhatsApp para registrar tu fecha o saldo."
  }.freeze

  def payment_methods
    cfg = (has_attribute?(:payment_methods_config) && payment_methods_config.is_a?(Hash)) ? payment_methods_config : {}
    DEFAULT_PAYMENT_METHODS.deep_merge(cfg)
  end

  def zelle_info
    payment_methods["zelle"] || {}
  end

  def binance_info
    payment_methods["binance"] || {}
  end

  def pago_movil_info
    payment_methods["pago_movil"] || {}
  end

  def bank_transfer_info
    payment_methods["bank_transfer"] || {}
  end

  def any_payment_method_enabled?
    zelle_enabled? || binance_enabled? || pago_movil_enabled? || bank_transfer_enabled?
  end

  def zelle_enabled?
    zelle_info["enabled"].to_s == "true" || zelle_info["enabled"] == true
  end

  def binance_enabled?
    binance_info["enabled"].to_s == "true" || binance_info["enabled"] == true
  end

  def pago_movil_enabled?
    pago_movil_info["enabled"].to_s == "true" || pago_movil_info["enabled"] == true
  end

  def bank_transfer_enabled?
    bank_transfer_info["enabled"].to_s == "true" || bank_transfer_info["enabled"] == true
  end

  private

  def generate_slug_and_token
    self.slug ||= name.to_s.parameterize.presence || SecureRandom.hex(4)
    self.invitation_token ||= SecureRandom.hex(12)
  end
end
