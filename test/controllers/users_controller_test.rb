require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @leader = users(:one)
    @staff = users(:two)
    @musician = users(:musician)
    @client_user = users(:client_user)
  end

  test "should get edit for self" do
    sign_in @musician
    get edit_user_url(@musician)
    assert_response :success
  end

  test "leader should get edit for worker" do
    sign_in @leader
    get edit_user_url(@musician)
    assert_response :success
  end

  test "staff should not get edit for other worker" do
    sign_in @staff
    get edit_user_url(@musician)
    assert_redirected_to root_path
  end

  test "leader should not get edit for client" do
    sign_in @leader
    get edit_user_url(@client_user)
    assert_redirected_to root_path
  end

  test "client should get edit for self" do
    sign_in @client_user
    get edit_user_url(@client_user)
    assert_response :success
    assert_select "h1", text: /Editar Perfil de Cliente/
  end

  test "client should update self name and phone" do
    sign_in @client_user
    patch user_url(@client_user), params: { 
      user: { 
        name: "Nuevo Nombre Cliente",
        client_phone: "04125555555"
      }
    }
    assert_redirected_to root_path
    @client_user.reload
    assert_equal "Nuevo Nombre Cliente", @client_user.name
    @client_user.client.reload
    assert_equal "04125555555", @client_user.client.phone
  end

  test "musician should update self profile but not client phone" do
    sign_in @musician
    patch user_url(@musician), params: { 
      user: { 
        name: "Nuevo Nombre Musico",
        specialty: "Batería",
        bio: "Toco batería metal."
      }
    }
    assert_redirected_to root_path
    @musician.reload
    assert_equal "Nuevo Nombre Musico", @musician.name
    assert_equal "Batería", @musician.specialty
    assert_equal "Toco batería metal.", @musician.bio
  end
end
