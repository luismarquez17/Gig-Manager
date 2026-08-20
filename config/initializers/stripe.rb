require 'stripe'

Stripe.api_key = ENV['STRIPE_SECRET_KEY'] || Rails.application.credentials.dig(:stripe, :secret_key)
Stripe.api_version = '2023-10-16'
