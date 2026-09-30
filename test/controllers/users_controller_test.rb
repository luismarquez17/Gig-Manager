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

  test "leader should create a new staff worker by email" do
    sign_in @leader
    assert_difference("User.count", 1) do
      post create_worker_users_url, params: {
        user: {
          email: "newworker@testcompany.com",
          name: "Nuevo Staff",
          role: "staff"
        }
      }
    end
    assert_redirected_to users_path
    new_user = User.find_by(email: "newworker@testcompany.com")
    assert_not_nil new_user
    assert_equal @leader.company_id, new_user.company_id
    assert_equal "staff", new_user.role
    assert_equal "Nuevo Staff", new_user.name
  end

  test "leader should link an existing user to their company as musician" do
    sign_in @leader
    other_user = User.create!(
      email: "existingother@example.com",
      password: "password123",
      role: :client
    )
    assert_not_equal @leader.company_id, other_user.company_id

    assert_no_difference("User.count") do
      post create_worker_users_url, params: {
        user: {
          email: "existingother@example.com",
          name: "Músico Transferido",
          role: "musician"
        }
      }
    end
    assert_redirected_to users_path
    other_user.reload
    assert_equal @leader.company_id, other_user.company_id
    assert_equal "musician", other_user.role
    assert_equal "Músico Transferido", other_user.name
  end

  test "staff should not be able to create or link workers" do
    sign_in @staff
    assert_no_difference("User.count") do
      post create_worker_users_url, params: {
        user: {
          email: "unauthorized@example.com",
          role: "staff"
        }
      }
    end
    assert_redirected_to root_path
  end

  test "leader should create eventual worker without email" do
    sign_in @leader
    assert_difference("User.count", 1) do
      post create_worker_users_url, params: {
        eventual: "1",
        user: {
          name: "Ramón Mesonero",
          role: "staff",
          specialty: "Mesonero",
          phone: "04249998877"
        }
      }
    end
    assert_redirected_to users_path
    new_worker = User.last
    assert new_worker.eventual?
    assert_equal "Ramón Mesonero", new_worker.name
    assert_equal "04249998877", new_worker.phone
    assert_equal @leader.company_id, new_worker.company_id
  end

  test "leader should claim eventual worker account and set real credentials" do
    sign_in @leader
    eventual_worker = User.create_eventual_worker!(
      company: @leader.company,
      name: "Laura Protocolo",
      role: "staff"
    )

    post claim_account_user_url(eventual_worker), params: {
      user: {
        email: "laura.protocolo@example.com",
        password: "password123"
      }
    }

    assert_redirected_to users_path
    eventual_worker.reload
    assert_not eventual_worker.eventual?
    assert_equal "laura.protocolo@example.com", eventual_worker.email
    assert eventual_worker.valid_password?("password123")
  end
end
