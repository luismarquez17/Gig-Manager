require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "should get dashboard" do
    get root_url
    assert_response :success
  end

  test "should get availability dashboard" do
    get availability_dashboard_url
    assert_response :success
  end

  test "should get availability dashboard with conflicts" do
    item = items(:one)
    item.update!(status: "Excelente", quantity: 1)
    item.inventory_items.update_all(status: :damaged)
    
    gig = gigs(:one)
    gig.update!(date: Date.today)
    
    # Create gig_item requesting 2 copies, but 0 are available
    gig.gig_items.destroy_all
    gig.gig_items.create!(item: item, quantity: 2)
    
    get availability_dashboard_url
    assert_response :success
    assert_select "h4", "Conflictos detectados en el calendario"
  end

  test "should get financials" do
    get financials_dashboard_url
    assert_response :success
    assert_select "h1", /Métricas Financieras/
  end

  test "should get terms page unauthenticated" do
    sign_out @user
    get terms_url
    assert_response :success
    assert_select "h1", /Términos y Condiciones/
    assert_select "a[href*='wa.me/584246208725']"
  end

  test "should get privacy page unauthenticated" do
    sign_out @user
    get privacy_url
    assert_response :success
    assert_select "h1", /Política de Privacidad/
    assert_select "a[href*='wa.me/584246208725']"
  end
end
