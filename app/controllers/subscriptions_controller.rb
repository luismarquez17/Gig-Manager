class SubscriptionsController < ApplicationController
  skip_before_action :check_company_subscription!, only: [:index, :checkout, :portal, :report_payment]

  def index
    @company = current_company
    @trial_days_left = @company.days_left_in_trial
    @trial_active = @company.trial_active?
    @trial_expired = @company.trial_expired?
    @active_subscription = @company.active_subscription?
    @pending_payments = @company.subscription_payments.where(status: 'pending').order(created_at: :desc)
  end

  def report_payment
    plan_tier = params[:plan_tier] == 'pro' ? 'pro' : 'starter'
    amount = plan_tier == 'pro' ? 20.00 : 10.00

    @payment = current_company.subscription_payments.build(
      user: current_user,
      plan_tier: plan_tier,
      payment_method: params[:payment_method],
      reference_number: params[:reference_number].to_s.strip,
      amount: amount,
      notes: params[:notes]
    )

    if @payment.save
      redirect_to subscriptions_path, notice: "🎉 ¡Pago reportado con éxito! Referencia ##{@payment.reference_number}. Tu suscripción será verificada y activada en breve."
    else
      redirect_to subscriptions_path, alert: "⚠️ No se pudo reportar el pago: #{@payment.errors.full_messages.to_sentence}"
    end
  end

  def checkout
    plan_tier = params[:plan_tier] == 'pro' ? 'pro' : 'starter'
    price_amount = plan_tier == 'pro' ? 2000 : 1000 # en centavos: $20 USD o $10 USD
    plan_name = plan_tier == 'pro' ? 'Gig Manager Pro (En Ajuste por Desarrollador)' : 'Gig Manager Base'

    # Simulación directa en ambiente de desarrollo si aún no se han configurado llaves reales de Stripe
    if ENV['STRIPE_SECRET_KEY'].blank? && !Rails.application.credentials.dig(:stripe, :secret_key).present?
      if Rails.env.development?
        current_company.update!(
          subscription_status: 'active',
          plan_tier: plan_tier,
          stripe_customer_id: "cus_simulated_#{SecureRandom.hex(6)}",
          stripe_subscription_id: "sub_simulated_#{SecureRandom.hex(6)}"
        )
        redirect_to subscriptions_path, notice: "¡Modo Simulación Activo! Tu suscripción al plan #{plan_tier.capitalize} ($#{price_amount / 100}/mes) ha sido activada correctamente."
        return
      end
    end

    session_params = {
      payment_method_types: ['card'],
      mode: 'subscription',
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: plan_name,
            description: "Suscripción mensual a #{plan_name} para #{current_company.name}"
          },
          unit_amount: price_amount,
          recurring: { interval: 'month' }
        },
        quantity: 1
      }],
      metadata: {
        company_id: current_company.id,
        plan_tier: plan_tier
      },
      success_url: "#{subscriptions_url}?session_id={CHECKOUT_SESSION_ID}&success=true",
      cancel_url: "#{subscriptions_url}?canceled=true"
    }

    if current_company.stripe_customer_id.present?
      session_params[:customer] = current_company.stripe_customer_id
    else
      session_params[:customer_email] = current_user.email
    end

    checkout_session = Stripe::Checkout::Session.create(session_params)
    redirect_to checkout_session.url, allow_other_host: true
  rescue => e
    redirect_to subscriptions_path, alert: "Error al iniciar Stripe Checkout: #{e.message}"
  end

  def portal
    unless current_company.stripe_customer_id.present?
      redirect_to subscriptions_path, alert: "Aún no tienes un registro de cliente activo en Stripe."
      return
    end

    if current_company.stripe_customer_id.start_with?("cus_simulated_")
      redirect_to subscriptions_path, notice: "Estás en modo simulación local. Para administrar suscripciones reales en Stripe configura tus llaves de producción."
      return
    end

    portal_session = Stripe::BillingPortal::Session.create(
      customer: current_company.stripe_customer_id,
      return_url: subscriptions_url
    )
    redirect_to portal_session.url, allow_other_host: true
  rescue => e
    redirect_to subscriptions_path, alert: "Error al acceder al Portal de Stripe: #{e.message}"
  end
end
