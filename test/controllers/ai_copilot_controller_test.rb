# frozen_string_literal: true

require 'test_helper'

class AiCopilotControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = companies(:one)
    @leader = users(:one)
    @musician = users(:musician)
  end

  test "should redirect unauthenticated users" do
    post ai_copilot_message_path, params: { message: "Hola" }
    assert_redirected_to new_user_session_path
  end

  test "should deny non-leaders access" do
    sign_in @musician
    post ai_copilot_message_path, params: { message: "Hola" }
    assert_redirected_to root_path
    follow_redirect!
    assert_equal "No tienes permiso para acceder a esta sección.", flash[:alert]
  end

  test "should return diagnostic for leader" do
    sign_in @leader
    get ai_copilot_diagnostic_path
    assert_response :success
    json = JSON.parse(response.body)
    assert json.key?('cash_balance')
    assert json.key?('diagnostic_items')
  end

  test "should return response for message" do
    sign_in @leader
    post ai_copilot_message_path, params: { message: "Hola" }, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json.key?('reply')
  end

  test "should execute quick action approve_all_pending_payments" do
    sign_in @leader
    post ai_copilot_quick_action_path, params: { action_key: 'approve_all_pending_payments' }, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json['success']
    assert json['message'].include?("aprobaron")
  end
end
