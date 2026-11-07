# frozen_string_literal: true

class AiCopilotController < ApplicationController
  before_action :authenticate_user!
  before_action :require_leader!

  # POST /ai_copilot/message
  def message
    user_prompt = params[:message].to_s.strip
    history = params[:history] || []

    if user_prompt.blank?
      render json: { reply: "Por favor escribe o di una instrucción para ayudarte.", actions_taken: [], cards: [] }, status: :unprocessable_entity
      return
    end

    service = GeminiService.new(company: current_company, user: current_user)
    result = service.chat(user_prompt, history)

    render json: result
  end

  # GET /ai_copilot/diagnostic
  def diagnostic
    service = GeminiService.new(company: current_company, user: current_user)
    data = service.run_diagnostic
    render json: data
  end

  # POST /ai_copilot/quick_action
  def quick_action
    action_key = params[:action_key].to_s

    case action_key
    when 'approve_all_pending_payments'
      pending = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id }).pending_approval
      count = pending.count
      pending.find_each do |p|
        p.update(status: 'approved', approved_at: Time.current, approved_by: current_user)
      end

      render json: {
        success: true,
        message: "✅ Se aprobaron con éxito #{count} pago(s) de clientes. El dinero ya está sumado a tu Fondo General.",
        new_diagnostic: GeminiService.new(company: current_company, user: current_user).run_diagnostic
      }
    when 'auto_allocate_all'
      render json: {
        success: true,
        message: "ℹ️ En tu empresa todo el dinero entra directamente al Fondo General único.",
        new_diagnostic: GeminiService.new(company: current_company, user: current_user).run_diagnostic
      }
    else
      render json: { success: false, message: "Acción no reconocida." }, status: :unprocessable_entity
    end
  end
end
