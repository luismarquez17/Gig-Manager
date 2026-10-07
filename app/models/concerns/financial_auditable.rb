# frozen_string_literal: true

module FinancialAuditable
  extend ActiveSupport::Concern

  included do
    attr_accessor :audit_reason

    after_create :log_financial_create
    around_update :log_financial_update
    before_destroy :log_financial_destroy
  end

  private

  def log_financial_create
    company_id = resolve_audit_company_id
    return unless company_id

    current_amount = respond_to?(:amount) ? amount.to_f : (respond_to?(:cost) ? cost.to_f : 0.0)
    current_currency = respond_to?(:currency) ? (currency.presence || 'USD') : 'USD'

    FinancialAuditLog.create(
      company_id: company_id,
      user_id: Current.user&.id,
      auditable_type: self.class.name,
      auditable_id: id,
      action: 'created',
      amount_before: 0.0,
      amount_after: current_amount,
      currency: current_currency,
      reason: audit_reason.presence || Current.audit_reason.presence || audit_creation_note,
      details: audit_snapshot,
      ip_address: Current.ip_address
    )
  rescue StandardError => e
    Rails.logger.error "[FinancialAuditable#log_financial_create] Error: #{e.message}"
  end

  def log_financial_update
    amount_field = respond_to?(:amount) ? :amount : (respond_to?(:cost) ? :cost : nil)
    amount_before = amount_field ? send(amount_field).to_f : 0.0

    yield

    company_id = resolve_audit_company_id
    return unless company_id

    changes_to_log = saved_changes.except('updated_at', 'created_at')
    return if changes_to_log.empty?

    amount_after = amount_field ? send(amount_field).to_f : amount_before
    if changes_to_log.key?(amount_field.to_s)
      amount_before = changes_to_log[amount_field.to_s].first.to_f
      amount_after = changes_to_log[amount_field.to_s].last.to_f
    end

    action = 'updated'
    if changes_to_log.key?('status')
      new_status = changes_to_log['status'].last.to_s
      action = 'approved' if new_status == 'approved'
      action = 'rejected' if new_status == 'rejected'
      action = 'voided'   if new_status == 'voided'
    end

    current_currency = respond_to?(:currency) ? (currency.presence || 'USD') : 'USD'

    FinancialAuditLog.create(
      company_id: company_id,
      user_id: Current.user&.id,
      auditable_type: self.class.name,
      auditable_id: id,
      action: action,
      amount_before: amount_before,
      amount_after: amount_after,
      currency: current_currency,
      reason: audit_reason.presence || Current.audit_reason.presence || audit_update_note(changes_to_log),
      details: {
        changes: changes_to_log,
        snapshot: audit_snapshot
      },
      ip_address: Current.ip_address
    )
  rescue StandardError => e
    Rails.logger.error "[FinancialAuditable#log_financial_update] Error: #{e.message}"
  end

  def log_financial_destroy
    company_id = resolve_audit_company_id
    return unless company_id

    current_amount = respond_to?(:amount) ? amount.to_f : (respond_to?(:cost) ? cost.to_f : 0.0)
    current_currency = respond_to?(:currency) ? (currency.presence || 'USD') : 'USD'

    FinancialAuditLog.create(
      company_id: company_id,
      user_id: Current.user&.id,
      auditable_type: self.class.name,
      auditable_id: id,
      action: 'deleted',
      amount_before: current_amount,
      amount_after: 0.0,
      currency: current_currency,
      reason: audit_reason.presence || Current.audit_reason.presence || 'Registro eliminado por el usuario',
      details: audit_snapshot,
      ip_address: Current.ip_address
    )
  rescue StandardError => e
    Rails.logger.error "[FinancialAuditable#log_financial_destroy] Error: #{e.message}"
  end

  def resolve_audit_company_id
    if respond_to?(:company_id) && company_id.present?
      company_id
    elsif respond_to?(:gig) && gig&.company_id.present?
      gig.company_id
    elsif respond_to?(:item) && item&.company_id.present?
      item.company_id
    else
      Current.company&.id
    end
  end

  def audit_snapshot
    attrs = attributes.dup
    if respond_to?(:gig) && gig.present?
      attrs['_gig_info'] = {
        id: gig.id,
        date: gig.date&.to_s,
        client_name: gig.client_display_name
      }
    end
    if respond_to?(:user) && user.present?
      attrs['_worker_info'] = {
        id: user.id,
        name: user.display_name,
        email: user.email
      }
    end
    attrs
  end

  def audit_creation_note
    if is_a?(GigPayment)
      client_name = gig&.client_display_name || 'Cliente'
      "Registro de abono de #{client_name} (#{payment_method_label})"
    elsif is_a?(EmployeePayment)
      worker_name = user&.display_name || 'Personal'
      "Registro de pago a #{worker_name}"
    elsif is_a?(CashAdjustment)
      "Registro de #{type_label.downcase}: #{description}"
    else
      "Creación de registro contable"
    end
  end

  def audit_update_note(changes)
    changed_keys = changes.keys.map(&:humanize).join(', ')
    "Modificación de campos: #{changed_keys}"
  end
end
