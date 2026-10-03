# frozen_string_literal: true

class FinancialAuditLog < ApplicationRecord
  include TenantScoped

  belongs_to :company
  belongs_to :user, optional: true
  belongs_to :auditable, polymorphic: true, optional: true

  ACTIONS = %w[created updated deleted approved rejected].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :auditable_type, presence: true
  validates :auditable_id, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :for_auditable, ->(type, id) { where(auditable_type: type, auditable_id: id) }
  scope :by_action, ->(act) { where(action: act) if act.present? }
  scope :by_user, ->(u_id) { where(user_id: u_id) if u_id.present? }
  scope :by_type, ->(t) { where(auditable_type: t) if t.present? }

  def action_label
    case action
    when 'created'  then 'Creación'
    when 'updated'  then 'Modificación'
    when 'deleted'  then 'Eliminación'
    when 'approved' then 'Aprobación'
    when 'rejected' then 'Rechazo'
    else action.humanize
    end
  end

  def action_badge_bg
    case action
    when 'created'  then '#dcfce7'
    when 'updated'  then '#fef3c7'
    when 'deleted'  then '#fee2e2'
    when 'approved' then '#e0f2fe'
    when 'rejected' then '#f3e8ff'
    else '#f1f5f9'
    end
  end

  def action_badge_color
    case action
    when 'created'  then '#166534'
    when 'updated'  then '#92400e'
    when 'deleted'  then '#991b1b'
    when 'approved' then '#0369a1'
    when 'rejected' then '#6b21a8'
    else '#334155'
    end
  end

  def action_emoji
    case action
    when 'created'  then '✨'
    when 'updated'  then '✏️'
    when 'deleted'  then '🗑️'
    when 'approved' then '✅'
    when 'rejected' then '❌'
    else '📝'
    end
  end

  def auditable_human_type
    case auditable_type
    when 'GigPayment'       then 'Abono de Cliente (Show)'
    when 'EmployeePayment'  then 'Nómina de Personal / Músico'
    when 'CashAdjustment'   then 'Movimiento de Caja General'
    when 'Investment'       then 'Inversión en Equipos'
    when 'MaintenanceRecord' then 'Gasto de Mantenimiento'
    else auditable_type.titleize
    end
  end

  def user_display_name
    user&.display_name.presence || user&.email.presence || 'Sistema / Automático'
  end

  def formatted_amount_change
    case action
    when 'created'
      "+$#{sprintf('%.2f', amount_after.to_f)} #{currency}"
    when 'deleted'
      "-$#{sprintf('%.2f', amount_before.to_f)} #{currency} (Eliminado)"
    when 'updated'
      if amount_before.to_f != amount_after.to_f
        diff = (amount_after.to_f - amount_before.to_f).round(2)
        diff_str = diff.positive? ? "+$#{sprintf('%.2f', diff)}" : "-$#{sprintf('%.2f', diff.abs)}"
        "$#{sprintf('%.2f', amount_before.to_f)} → $#{sprintf('%.2f', amount_after.to_f)} (#{diff_str})"
      else
        "$#{sprintf('%.2f', amount_after.to_f)} #{currency}"
      end
    when 'approved', 'rejected'
      "$#{sprintf('%.2f', amount_after.to_f)} #{currency}"
    else
      "$#{sprintf('%.2f', (amount_after || amount_before).to_f)} #{currency}"
    end
  end
end
