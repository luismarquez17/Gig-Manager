require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  setup do
    @company = Company.create!(
      name: "Banda Los Dinámicos",
      slug: "los-dinamicos-123",
      monthly_fee: 0.0,
      subscription_status: "trialing",
      trial_started_at: Time.current,
      trial_ends_at: 30.days.from_now
    )
    @user = User.create!(
      name: "Carlos Director",
      email: "carlos_director@test.com",
      password: "password123",
      role: :leader,
      company: @company
    )
  end

  test "welcome_email delivers properly with trial info and links" do
    email = UserMailer.welcome_email(@user)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal ["carlos_director@test.com"], email.to
    assert_match /¡Bienvenido a GigManager!/, email.subject
    assert_match /Carlos Director/, email.text_part.body.decoded
    assert_match /Banda Los Dinámicos/, email.text_part.body.decoded
    assert_match /los-dinamicos-123/, email.text_part.body.decoded
    assert_match /58 424 6208725/, email.text_part.body.decoded
  end

  test "trial_expiring_reminder delivers properly with subscriptions link" do
    email = UserMailer.trial_expiring_reminder(@user)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal ["carlos_director@test.com"], email.to
    assert_match /Tu prueba gratuita de GigManager vence pronto/, email.subject
    assert_match /Banda Los Dinámicos/, email.text_part.body.decoded
    assert_match /subscriptions/, email.text_part.body.decoded
    assert_match /0424-6208725/, email.text_part.body.decoded
  end
end
