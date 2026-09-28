class UserMailer < ApplicationMailer
  def welcome_email(user)
    @user = user
    @company = user.company
    return unless @user.email.present?

    @login_url = new_user_session_url
    @dashboard_url = authenticated_root_url rescue root_url
    @join_url = @company&.slug.present? ? join_company_url(slug: @company.slug) : nil
    @trial_days = Company::DEFAULT_TRIAL_DAYS
    @trial_ends_at = @company&.trial_ends_at || @trial_days.days.from_now

    mail(
      to: @user.email,
      subject: "🎉 ¡Bienvenido a GigManager! Tus 30 días de prueba gratuita están activos"
    )
  end

  def trial_expiring_reminder(user)
    @user = user
    @company = user.company
    return unless @user.email.present?

    @subscriptions_url = subscriptions_url
    @days_left = @company&.days_left_in_trial.to_i

    mail(
      to: @user.email,
      subject: "⏳ Tu prueba gratuita de GigManager vence pronto (#{@days_left} días restantes)"
    )
  end
end
