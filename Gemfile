source "https://rubygems.org"

ruby "3.3.4"

# Rails y Core
gem "rails", "~> 7.1.6"
gem "sprockets-rails"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "bootsnap", require: false

# Base de datos
gem "pg", "~> 1.5"

# --- Gemas de Lógica Específica ---
gem "money-rails", "~> 1.15"
gem "aasm", "~> 5.5"
gem "bootstrap", "~> 5.3"
gem "devise", "~> 4.9"
gem "dartsass-rails"

# --- Gemas de Funcionalidades Pro (NUEVAS) ---

# Reportes PDF
gem "wicked_pdf", "~> 2.8"
gem "wkhtmltopdf-binary", "~> 0.12.6"

# Tareas en segundo plano (Recordatorios y automatización)
gem "sidekiq", "~> 7.2"
gem "sidekiq-scheduler", "~> 5.0"

# Manejo de fechas avanzado
gem "chronic", "~> 0.10.2"

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