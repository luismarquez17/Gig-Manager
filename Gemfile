source "https://rubygems.org"

ruby "3.3.4"

# Rails y Core
gem "rails", "~> 7.1.6"
gem "json", "~> 2.8"
gem "sprockets-rails"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "bootsnap", require: false

# Base de datos
gem "pg", "~> 1.5"

# --- Gemas de Lógica Específica ---
gem "aasm", "~> 5.5"
gem "bootstrap", "~> 5.3"
gem "devise", "~> 4.9"
gem "omniauth-google-oauth2", "~> 1.1"
gem "omniauth-rails_csrf_protection", "~> 1.0"
gem "dartsass-rails"

# Multi-tenancy y Pagos SaaS
gem "acts_as_tenant"
gem "stripe"

# --- Gemas opcionales sin uso actual (excluidas en producción para ahorrar RAM) ---
group :unused_optional do
  gem "jbuilder", require: false
  gem "money-rails", "~> 1.15", require: false
  gem "wicked_pdf", "~> 2.8", require: false
  gem "wkhtmltopdf-binary", "~> 0.12.6", require: false
  gem "sidekiq", "~> 7.2", require: false
  gem "sidekiq-scheduler", "~> 5.0", require: false
  gem "chronic", "~> 0.10.2", require: false
end

# --- Sistema ---
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "debug", platforms: %i[ mri windows ]
  gem "capybara"
  gem "selenium-webdriver"
  gem "dotenv-rails", "~> 3.1"
end

group :development do
  gem "web-console"
end

group :test do
  gem "minitest", "< 6"
end