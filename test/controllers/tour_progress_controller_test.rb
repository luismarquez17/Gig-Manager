# frozen_string_literal: true

require "test_helper"

class TourProgressControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @company = companies(:one)
    @leader = users(:one)
    @leader.update_column(:tour_state, {})
  end

  test "requiere usuario autenticado" do
    patch tour_progress_path, params: { action_type: "complete_area", area_key: "dashboard" }, as: :json
    assert_response :unauthorized
  end

  test "persiste progreso de areas vistas, omitidas y desactivacion global" do
    sign_in @leader

    patch tour_progress_path, params: { action_type: "complete_area", area_key: "dashboard" }, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
    assert_equal ["dashboard"], json.dig("tour_state", "completed_areas")

    # Simula entrar semanas después a un área nueva (ej. inventario) y declinarla
    patch tour_progress_path, params: { action_type: "dismiss_area", area_key: "items_index" }, as: :json
    assert_response :success
    @leader.reload
    assert_includes @leader.normalized_tour_state["completed_areas"], "dashboard"
    assert_includes @leader.normalized_tour_state["dismissed_areas"], "items_index"

    # Si luego completa manualmente desde el botón de guía, se mueve a completed_areas
    patch tour_progress_path, params: { action_type: "complete_area", area_key: "items_index" }, as: :json
    assert_response :success
    @leader.reload
    assert_includes @leader.normalized_tour_state["completed_areas"], "items_index"
    assert_not_includes @leader.normalized_tour_state["dismissed_areas"], "items_index"

    # Desactivar guías automáticas
    patch tour_progress_path, params: { action_type: "disable_all" }, as: :json
    assert_response :success
    assert_equal true, @leader.reload.normalized_tour_state["disabled"]
  end

  test "renderiza motor de tutorial guiado y marcadores data-tour en vistas principales" do
    sign_in @leader

    [
      dashboard_path,
      gigs_path,
      items_path,
      clients_path,
      subscriptions_path
    ].each do |path|
      get path
      assert_response :success
      assert_includes response.body, "gm-tour-overlay"
      assert_includes response.body, "gm-tour-prompt"
      assert_includes response.body, "sidebar-tour-trigger-btn"
    end
  end
end
