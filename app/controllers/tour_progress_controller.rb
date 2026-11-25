# frozen_string_literal: true

class TourProgressController < ApplicationController
  skip_before_action :check_company_subscription!
  skip_before_action :ensure_company_onboarding!

  def update
    action_type = params[:action_type].to_s
    area_key = params[:area_key].to_s

    unless %w[complete_area dismiss_area disable_all enable_all reset_all].include?(action_type)
      render json: { success: false, error: "Acción inválida" }, status: :unprocessable_entity
      return
    end

    new_state = current_user.record_tour_action!(action_type, area_key)
    render json: { success: true, tour_state: new_state }
  end
end
