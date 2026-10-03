# frozen_string_literal: true

class FinancialAuditLogsController < ApplicationController
  before_action :require_leader!
  before_action -> { require_module!(:finances) }

  def index
    @logs = current_company.financial_audit_logs.includes(:user).recent_first

    # 1. Filtro por tipo de acción
    if params[:action_type].present? && FinancialAuditLog::ACTIONS.include?(params[:action_type])
      @logs = @logs.where(action: params[:action_type])
    end

    # 2. Filtro por tipo de registro financiero
    if params[:model_type].present?
      @logs = @logs.where(auditable_type: params[:model_type])
    end

    # 3. Filtro por usuario que realizó la acción
    if params[:user_id].present?
      @logs = @logs.where(user_id: params[:user_id])
    end

    # 4. Filtro por rango de fechas
    if params[:start_date].present?
      @logs = @logs.where("created_at >= ?", params[:start_date].to_date.beginning_of_day) rescue @logs
    end
    if params[:end_date].present?
      @logs = @logs.where("created_at <= ?", params[:end_date].to_date.end_of_day) rescue @logs
    end

    # 5. Búsqueda por texto (motivo o detalles)
    if params[:query].present?
      term = "%#{params[:query].to_s.strip}%"
      @logs = @logs.where("reason ILIKE ? OR details::text ILIKE ?", term, term)
    end

    # Métricas para las tarjetas de resumen
    base_logs = current_company.financial_audit_logs
    @total_logs_count     = base_logs.count
    @updates_count        = base_logs.where(action: 'updated').count
    @deletions_count      = base_logs.where(action: 'deleted').count
    @creations_count      = base_logs.where(action: 'created').count
    @latest_log           = base_logs.recent_first.first

    @users_for_filter = current_company.users.where(id: base_logs.select(:user_id).distinct).order(:email)
  end
end
