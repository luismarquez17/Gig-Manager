# frozen_string_literal: true

class FinancialAuditLog < ApplicationRecord
  include TenantScoped

  belongs_to :company
  belongs_to :user, optional: true
  belongs_to :auditable, polymorphic: true, optional: true

  ACTIONS = %w[created updated deleted approved rejected voided].freeze

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
    when 'voided'   then 'Anulación Contable'
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
    when 'voided'   then '#fee2e2'
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
    when 'voided'   then '#991b1b'
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
    when 'voided'   then '🚫'
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

  IGNORED_AUDIT_FIELDS = %w[updated_at receipt_image_base64 created_at].freeze

  FIELD_LABELS = {
    'status'              => 'Estado',
    'amount'              => 'Monto',
    'approved_at'         => 'Fecha de Aprobación',
    'approved_by_id'      => 'Aprobado por',
    'approved_by'         => 'Aprobado por',
    'receipt_number'      => 'Nº de Recibo / Folio',
    'payment_method'      => 'Método de Pago',
    'reference_number'    => 'Nº de Referencia',
    'notes'               => 'Notas',
    'date_paid'           => 'Fecha de Pago',
    'reported_by_client'  => 'Reportado por Cliente',
    'rejection_reason'    => 'Motivo de Rechazo',
    'payer_name'          => 'Nombre de Pagador',
    'currency'            => 'Moneda',
    'category'            => 'Categoría',
    'description'         => 'Descripción',
    'adjustment_type'     => 'Tipo de Movimiento',
    'reason'              => 'Motivo'
  }.freeze

  def humanized_changes
    return [] unless details.is_a?(Hash) && details['changes'].is_a?(Hash)

    list = []
    details['changes'].each do |raw_field, diff|
      next if IGNORED_AUDIT_FIELDS.include?(raw_field.to_s)

      field_name = FIELD_LABELS[raw_field.to_s] || raw_field.to_s.humanize
      val_before = humanize_value(raw_field, diff.is_a?(Array) ? diff.first : nil)
      val_after  = humanize_value(raw_field, diff.is_a?(Array) ? diff.last : diff)

      list << {
        field: field_name,
        before: val_before,
        after: val_after,
        raw_field: raw_field
      }
    end
    list
  end

  def humanize_value(field, val)
    return '—' if val.nil? || (val.is_a?(String) && val.blank?)

    case field.to_s
    when 'status'
      case val.to_s
      when 'pending_approval' then '⏳ En Revisión'
      when 'approved'         then '✅ Aprobado'
      when 'rejected'         then '❌ Rechazado'
      when 'pending'          then '⏳ Pendiente'
      when 'paid'             then '✅ Pagado'
      else val.to_s.humanize
      end
    when 'payment_method'
      pm_info = GigPayment::PAYMENT_METHODS[val.to_s] || {}
      pm_info[:label] ? "#{pm_info[:emoji]} #{pm_info[:label]}" : val.to_s.humanize
    when 'approved_by_id', 'approved_by', 'user_id'
      if val.is_a?(Integer) || (val.is_a?(String) && val =~ /^\d+$/)
        u = User.find_by(id: val)
        u&.display_name.presence || "Usuario ##{val}"
      else
        val.to_s
      end
    when 'approved_at', 'created_at', 'date_paid', 'for_date'
      if val.is_a?(Time) || val.is_a?(DateTime) || val.is_a?(ActiveSupport::TimeWithZone)
        val.strftime('%d/%m/%Y %I:%M %p')
      elsif val.is_a?(Date)
        val.strftime('%d/%m/%Y')
      elsif val.to_s =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
        Time.parse(val.to_s).strftime('%d/%m/%Y %I:%M %p') rescue val.to_s
      elsif val.to_s =~ /^\d{4}-\d{2}-\d{2}$/
        Date.parse(val.to_s).strftime('%d/%m/%Y') rescue val.to_s
      else
        val.to_s
      end
    when 'reported_by_client', 'is_advance'
      val == true || val == 'true' ? 'Sí' : 'No'
    when 'amount'
      "$#{sprintf('%.2f', val.to_f)}"
    else
      val.to_s
    end
  end
end
