class StripeWebhooksController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_tenant
  skip_before_action :check_company_subscription!
  skip_before_action :verify_authenticity_token

  def create
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET'] || Rails.application.credentials.dig(:stripe, :webhook_secret)

    event = nil

    begin
      if endpoint_secret.present?
        event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
      else
        data = JSON.parse(payload, symbolize_names: true)
        event = Stripe::Event.construct_from(data)
      end
    rescue JSON::ParserError => e
      render json: { error: "Payload JSON inválido: #{e.message}" }, status: 400 and return
    rescue Stripe::SignatureVerificationError => e
      render json: { error: "Firma de Webhook Stripe inválida: #{e.message}" }, status: 400 and return
    end

    case event.type
    when 'checkout.session.completed'
      session = event.data.object
      handle_checkout_session_completed(session)
    when 'customer.subscription.updated'
      subscription = event.data.object
      handle_subscription_updated(subscription)
    when 'customer.subscription.deleted'
      subscription = event.data.object
      handle_subscription_deleted(subscription)
    when 'invoice.payment_succeeded'
      invoice = event.data.object
      handle_invoice_payment_succeeded(invoice)
    when 'invoice.payment_failed'
      invoice = event.data.object
      handle_invoice_payment_failed(invoice)
    end

    render json: { status: 'success' }, status: 200
  end

  private

  def handle_checkout_session_completed(session)
    company_id = session.metadata&.company_id
    plan_tier = session.metadata&.plan_tier || 'starter'
    company = Company.find_by(id: company_id) || Company.find_by(stripe_customer_id: session.customer)

    if company
      company.update!(
        stripe_customer_id: session.customer,
        stripe_subscription_id: session.subscription,
        subscription_status: 'active',
        plan_tier: plan_tier
      )
    end
  end

  def handle_subscription_updated(subscription)
    company = Company.find_by(stripe_subscription_id: subscription.id) || Company.find_by(stripe_customer_id: subscription.customer)
    if company
      status = subscription.status == 'active' ? 'active' : subscription.status
      company.update!(subscription_status: status)
    end
  end

  def handle_subscription_deleted(subscription)
    company = Company.find_by(stripe_subscription_id: subscription.id) || Company.find_by(stripe_customer_id: subscription.customer)
    if company
      company.update!(subscription_status: 'canceled')
    end
  end

  def handle_invoice_payment_succeeded(invoice)
    company = Company.find_by(stripe_customer_id: invoice.customer)
    if company
      company.update!(subscription_status: 'active')
    end
  end

  def handle_invoice_payment_failed(invoice)
    company = Company.find_by(stripe_customer_id: invoice.customer)
    if company
      company.update!(subscription_status: 'past_due')
    end
  end
end
