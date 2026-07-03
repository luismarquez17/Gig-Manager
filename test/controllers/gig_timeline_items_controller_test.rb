require "test_helper"

class GigTimelineItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @gig = gigs(:one)
  end

  test "should create gig_timeline_item" do
    assert_difference("GigTimelineItem.count") do
      post gig_gig_timeline_items_url(@gig), params: { 
        gig_timeline_item: { 
          time: "10:00 PM", 
          title: "Inicio Show", 
          description: "Entra el robot LED" 
        } 
      }
    end
    assert_redirected_to gig_path(@gig)
    follow_redirect!
    assert_match "Hito del cronograma agregado con éxito.", response.body
  end

  test "should destroy gig_timeline_item" do
    item = GigTimelineItem.create!(gig: @gig, time: "09:00 PM", title: "Montaje")
    assert_difference("GigTimelineItem.count", -1) do
      delete gig_gig_timeline_item_url(@gig, item)
    end
    assert_redirected_to gig_path(@gig)
    follow_redirect!
    assert_match "Hito del cronograma eliminado con éxito.", response.body
  end

  test "should not create if not leader" do
    sign_out @user
    sign_in users(:two) # staff user
    assert_no_difference("GigTimelineItem.count") do
      post gig_gig_timeline_items_url(@gig), params: { 
        gig_timeline_item: { 
          time: "10:00 PM", 
          title: "Inicio Show" 
        } 
      }
    end
    assert_redirected_to root_path
  end
end
