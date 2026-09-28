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
  has_many :cash_adjustments, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :invitation_token, uniqueness: true, allow_nil: true
  validates :monthly_fee, numericality: { greater_than_or_equal_to: 0 }

  DEFAULT_TRIAL_DAYS = 30

  before_validation :generate_slug_and_token, on: :create
  before_create :set_default_trial_period

  def set_default_trial_period
    self.trial_started_at ||= Time.current
    self.trial_ends_at ||= DEFAULT_TRIAL_DAYS.days.from_now
    self.subscription_status ||= "trialing"
    self.plan_tier ||= "starter"
    self.enabled_modules ||= AppModule.default_hash
  end

  # ==========================================
  # GESTIÓN DE MÓDULOS / FEATURE FLAGS
  # ==========================================

  def modules
    stored = (has_attribute?(:enabled_modules) && enabled_modules.is_a?(Hash)) ? enabled_modules : {}
    AppModule.default_hash.merge(stored)
  end

  def module_enabled?(module_key)
    return false if module_key.blank?
    key_str = module_key.to_s
    # Por defecto, si no está explícitamente en falso, está habilitado
    modules[key_str] != false && modules[key_str] != "false" && modules[key_str] != 0
  end

  def enable_module!(module_key)
    return if module_key.blank?
    cfg = modules.dup
    cfg[module_key.to_s] = true
    update!(enabled_modules: cfg)
  end

  def disable_module!(module_key)
    return if module_key.blank?
    cfg = modules.dup
    cfg[module_key.to_s] = false
    update!(enabled_modules: cfg)
  end

  def update_modules!(new_modules_hash)
    formatted = {}
    AppModule.keys.each do |key|
      val = new_modules_hash[key] || new_modules_hash[key.to_sym]
      formatted[key] = (val == true || val == "1" || val == "true" || val == 1)
    end
    update!(enabled_modules: formatted)
  end

  def enabled_module_keys
    AppModule.keys.select { |key| module_enabled?(key) }
  end

  # ==========================================
  # ESTADOS DE SUSCRIPCIÓN & FREE TRIAL
  # ==========================================

  def in_trial?
    subscription_status == "trialing"
  end

  def trial_active?
    in_trial? && trial_ends_at.present? && trial_ends_at > Time.current
  end

  def trial_expired?
    in_trial? && trial_ends_at.present? && trial_ends_at <= Time.current
  end

  def days_left_in_trial
    return 0 unless trial_ends_at.present? && trial_ends_at > Time.current
    ((trial_ends_at - Time.current) / 1.day).ceil
  end

  def active_subscription?
    subscription_status == "active"
  end

  def access_granted?
    return false if suspended?
    return true if active_subscription? || trial_active?
    false
  end

  def plan_tier_name
    AppModule.package_info(plan_tier)&.dig(:name) || plan_tier.to_s.titleize
  end

  def subscription_label
    if suspended?
      "Suspendida"
    elsif active_subscription?
      "Suscripción Activa (#{plan_tier_name})"
    elsif trial_active?
      "Prueba Gratuita (#{days_left_in_trial} días restantes)"
    elsif trial_expired?
      "Prueba Gratuita Vencida"
    elsif past_due?
      "Pago Vencido"
    else
      subscription_status.to_s.titleize
    end
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
