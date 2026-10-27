require "test_helper"

class GigsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @gig = gigs(:one)
  end

  test "should get index" do
    get gigs_url
    assert_response :success
  end

  test "should get index with next date_filter and calculate next_gig" do
    upcoming_gig = Gig.create!(
      company: @user.company,
      date: Date.current + 2.days,
      amount: 500,
      client: clients(:one)
    )

    get gigs_url
    assert_response :success
    assert_includes response.body, "El siguiente show es"
    assert_includes response.body, upcoming_gig.client_display_name

    get gigs_url, params: { date_filter: "next" }
    assert_response :success
    assert_includes response.body, upcoming_gig.client_display_name
  end

  test "should get new" do
    get new_gig_url
    assert_response :success
  end

  test "should get show" do
    get gig_url(@gig)
    assert_response :success
  end

  test "should assign staff with agreed amount and notify only the assigned worker" do
    worker = users(:musician)
    other_worker = users(:two)

    assert_difference -> { AppNotification.count }, 2 do # 1 personal notification to worker, 1 notification to leaders
      post assign_staff_gig_url(@gig), params: { staff_id: worker.id, agreed_amount: 150.0 }
    end
    assert_redirected_to gig_url(@gig)

    assignment = @gig.staff_assignments.find_by(user_id: worker.id)
    assert_not_nil assignment
    assert_equal 150.0, assignment.agreed_amount.to_f
    assert_equal 150.0, assignment.pending_balance

    personal_notif = AppNotification.find_by(recipient: worker)
    assert_not_nil personal_notif
    assert_includes worker.app_notifications, personal_notif
    assert_not_includes other_worker.app_notifications, personal_notif
  end

  test "should quick-create and assign eventual worker in gig without email" do
    assert_difference "User.count", 1 do
      assert_difference "@gig.staff_assignments.count", 1 do
        post assign_staff_gig_url(@gig), params: {
          new_eventual_worker_name: "Técnico Luces Eventual",
          new_eventual_worker_role: "staff",
          new_eventual_worker_phone: "04120001122",
          agreed_amount: 80.0
        }
      end
    end

    assert_redirected_to gig_url(@gig)
    created_worker = User.last
    assert created_worker.eventual?
    assert_equal "Técnico Luces Eventual", created_worker.name
    assert_equal "04120001122", created_worker.phone

    assignment = @gig.staff_assignments.find_by(user_id: created_worker.id)
    assert_not_nil assignment
    assert_equal 80.0, assignment.agreed_amount.to_f
  end

  test "should remove staff from gig" do
    worker = users(:two)
    @gig.staff_assignments.create!(user: worker, agreed_amount: 100.0)

    delete remove_staff_gig_url(@gig), params: { staff_id: worker.id }
    assert_redirected_to gig_url(@gig)

    assert_nil @gig.staff_assignments.find_by(user_id: worker.id)
  end

  test "should add extra time upsell and extend end_time and increase gig amount" do
    initial_amount = @gig.amount.to_f
    @gig.update!(start_time: Time.zone.parse("20:00"), end_time: Time.zone.parse("23:00"))

    post add_upsell_gig_url(@gig), params: { upsell_key: 'extra_time', price: 40.0 }
    assert_redirected_to gig_url(@gig)

    @gig.reload
    assert_equal initial_amount + 40.0, @gig.amount.to_f
    assert_equal "00:00", @gig.end_time.strftime("%H:%M") # 23:00 + 1 hr = 00:00 midnight
    assert_includes @gig.details, "Adicional añadido"
  end

  test "should update music_notes via gig update" do
    patch gig_url(@gig), params: {
      gig: {
        music_notes: "• Vals de entrada: Tiempo de Vals\n• Canción quinceañera: A Thousand Years"
      }
    }
    assert_redirected_to gig_url(@gig)
    @gig.reload
    assert_includes @gig.music_notes, "Tiempo de Vals"
    assert_includes @gig.music_notes, "A Thousand Years"
  end

  test "should save net profit to reinvestment goal from gig" do
    goal = ReinvestmentGoal.create!(
      company: @gig.company,
      title: "Estructura Truss 4m",
      target_amount: 500.0,
      saved_amount: 0.0
    )

    assert_difference "GoalSavingsContribution.count", 1 do
      post save_profit_to_goal_gig_url(@gig), params: {
        reinvestment_goal_id: goal.id,
        amount: 250.0,
        notes: "Ahorro de la ganancia libre del evento"
      }
    end

    assert_redirected_to gig_url(@gig)
    assert_equal 250.0, goal.reload.saved_amount
    contribution = GoalSavingsContribution.last
    assert_equal @gig, contribution.gig
    assert_equal 250.0, contribution.amount
  end

  test "should allocate surplus to reinvestment goal during process_closeout" do
    @gig.update!(amount: 1000.0)
    goal = ReinvestmentGoal.create!(
      company: @gig.company,
      title: "Luces Beam 7R",
      target_amount: 800.0,
      saved_amount: 100.0
    )

    assert_difference "GoalSavingsContribution.count", 1 do
      post process_closeout_gig_url(@gig), params: {
        client_collected_amount: 500.0,
        client_payment_method: "cash",
        deposit_to_goal: "1",
        reinvestment_goal_id: goal.id,
        goal_amount: 300.0
      }
    end

    assert_redirected_to gig_url(@gig)
    assert_equal 400.0, goal.reload.saved_amount # 100 + 300
  end

  test "should adjust general gig price and update end time and audit note" do
    @gig.update!(amount: 500.0, end_time: Time.zone.parse("2026-09-01 23:00:00"))

    patch adjust_price_gig_url(@gig), params: {
      new_amount: "400.00",
      reason: "Cliente canceló 1 hora extra",
      adjust_hours: "-1"
    }

    assert_redirected_to gig_url(@gig)
    assert_includes flash[:notice], "Presupuesto general actualizado a $400.00 USD"

    @gig.reload
    assert_equal 400.0, @gig.amount.to_f
    assert_equal "22:00", @gig.end_time.strftime("%H:%M")
    assert_includes @gig.details, "Ajuste de precio general"
    assert_includes @gig.details, "De $500.00 a $400.00 USD"
    assert_includes @gig.details, "Cliente canceló 1 hora extra"
  end

  test "should add upsell and create approved GigUpsellRequest" do
    @gig.update!(amount: 500.0, end_time: Time.zone.parse("2026-09-01 23:00:00"))

    assert_difference("GigUpsellRequest.count", 1) do
      post add_upsell_gig_url(@gig), params: {
        operation: "add",
        upsell_key: "extra_time",
        title: "1 Hora Extra de Música",
        price: "60.00",
        hours: "1"
      }
    end

    assert_redirected_to gig_url(@gig)
    @gig.reload
    assert_equal 560.0, @gig.amount.to_f
    assert_equal "00:00", @gig.end_time.strftime("%H:%M")

    last_req = GigUpsellRequest.last
    assert_equal "approved", last_req.status
    assert_equal 60.0, last_req.price.to_f
    assert_equal 1, last_req.hours_added
  end

  test "should apply deduction/discount via add_upsell with subtract operation" do
    @gig.update!(amount: 500.0, end_time: Time.zone.parse("2026-09-01 23:00:00"))

    post add_upsell_gig_url(@gig), params: {
      operation: "subtract",
      upsell_key: "extra_time",
      title: "Cancelación de 1 Hora Extra",
      price: "60.00",
      hours: "1"
    }

    assert_redirected_to gig_url(@gig)
    @gig.reload
    assert_equal 440.0, @gig.amount.to_f
    assert_equal "22:00", @gig.end_time.strftime("%H:%M")
    assert_includes @gig.details, "Deducción / Descuento registrado"
  end
end
