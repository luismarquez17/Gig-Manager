# frozen_string_literal: true

class Company < ApplicationRecord
  include Companies::BusinessProfiles
  include Companies::SubscriptionManager

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
  has_many :reinvestment_goals, dependent: :destroy
  has_many :goal_savings_contributions, dependent: :destroy
  has_many :finance_settings, dependent: :destroy
  has_many :employee_payments, dependent: :destroy
  has_many :subscription_payments, dependent: :destroy
  has_many :gig_upsell_requests, dependent: :destroy
  has_many :client_quotes, dependent: :destroy
  has_many :cash_adjustments, dependent: :destroy
  has_many :financial_audit_logs, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :invitation_token, uniqueness: true, allow_nil: true
  validates :monthly_fee, numericality: { greater_than_or_equal_to: 0 }

  before_validation :generate_slug_and_token, on: :create
  attribute :business_type, :string, default: 'music_band'

  def clients_count
    clients.count
  end

  def clients_with_user_count
    clients.with_user_account.distinct.count
  end

  def clients_without_user_count
    [clients_count - clients_with_user_count, 0].max
  end

  def clients_active_count
    clients.with_gigs.count
  end

  def clients_adoption_percentage
    return 0.0 if clients_count.zero?
    ((clients_with_user_count.to_f / clients_count) * 100).round(1)
  end

  def financial_reset_active?
    financial_reset_date.present?
  end

  def effective_reset_date
    financial_reset_date
  end

  def current_cash_balance
    total_gigs_received    = GigPayment.joins(:gig).where(gigs: { company_id: id }).approved.sum(:amount).to_f
    total_cash_deposits    = cash_adjustments.inflows.sum(:amount).to_f
    total_inflow           = total_gigs_received + total_cash_deposits

    total_payroll_paid     = employee_payments.approved.where.not(funding_source: 'external_capital').sum(:amount).to_f
    total_maintenance      = MaintenanceRecord.joins(:item).where(items: { company_id: id }).sum(:cost).to_f
    total_investments      = investments.sum(:amount).to_f
    total_cash_withdrawals = cash_adjustments.outflows.sum(:amount).to_f
    total_outflow          = total_payroll_paid + total_maintenance + total_investments + total_cash_withdrawals

    (total_inflow - total_outflow).round(2)
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
  # USUARIOS Y ACCESO LÍDER
  # ==========================================

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

  # ==========================================
  # MÉTODOS DE PAGO Y CONFIGURACIÓN BANCARIA
  # ==========================================

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
    "exchange_rate" => {
      "mode" => "auto_bcv",
      "custom_rate" => nil,
      "show_in_portals" => true
    },
    "general_instructions" => "Una vez realizado tu pago o transferencia, sube tu comprobante en el botón 'Reportar Abono' para generar tu recibo oficial y actualizar tu saldo de inmediato."
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

  def exchange_rate_config
    payment_methods["exchange_rate"] || { "mode" => "auto_bcv", "custom_rate" => nil, "show_in_portals" => true }
  end

  def effective_exchange_rate
    ExchangeRateService.current_rate(self)
  end

  def exchange_rate_details
    ExchangeRateService.today_rate_info(self)
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
