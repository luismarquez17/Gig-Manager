require "test_helper"

class Client::GigsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Configurar usuario con rol de cliente
    @client_user = users(:one)
    @client_user.update!(role: :client)
    
    # Asociar perfil de cliente
    @client_profile = clients(:one)
    @client_user.update!(client: @client_profile)
    
    # Asignar gig al cliente
    @gig = gigs(:one)
    @gig.update!(client: @client_profile, client_email: @client_user.email)
    
    sign_in @client_user
  end

  test "should get index of client gigs" do
    get client_gigs_url
    assert_response :success
    assert_select "h1", /Mis Eventos/
  end

  test "should show client gig details" do
    get client_gig_url(@gig)
    assert_response :success
    assert_select "h1", /El Evento de/
  end

  test "should redirect if client tries to access other client gig" do
    other_client = clients(:two)
    other_gig = gigs(:two)
    other_gig.update!(client: other_client)
    
    get client_gig_url(other_gig)
    assert_redirected_to client_gigs_url
    assert_equal "No tienes acceso a este evento.", flash[:alert]
  end

  test "should redirect if client tries to access internal gigs dashboard" do
    get gigs_url
    assert_redirected_to root_url
    assert_equal "No tienes permiso para acceder a esta sección.", flash[:alert]
  end
end
