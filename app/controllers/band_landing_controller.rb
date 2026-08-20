class BandLandingController < ApplicationController
  skip_before_action :authenticate_user!
  layout 'band_landing'

  before_action :set_company

  def show
    unless @company.landing_enabled?
      render :landing_disabled, status: :ok
      return
    end

    @preset_budgets = @company.landing_preset_budgets
    @staff_members = @company.landing_staff_members.presence || @company.users.where(role: [:leader, :musician, :staff, :superadmin])
    @reviews = @company.approved_reviews.order(pinned: :desc, created_at: :desc).limit(12)
    @media_items = @company.company_media_items.active.ordered
    @standard_upsells = @company.landing_upsells.presence || @company.standard_upsells.where(active: true).presence || StandardUpsell.where(company: @company).presence || StandardUpsell.all_with_defaults.select(&:active)
    @calculator_formats = @company.effective_calculator_formats
    @rating = @company.average_rating
    @reviews_count = @reviews.count
    @whatsapp_number = @company.whatsapp_number.presence || @company.contact_phone.presence || "584140000000"
    @faqs = @company.effective_faqs
  end

  def quote
    # Redirige de forma transparente a la sección del cotizador dentro de la Landing Page
    redirect_to band_landing_path(slug: @company.slug, anchor: 'cotizador')
  end

  private

  def set_company
    @company = Company.find_by(slug: params[:slug])
    if @company.nil?
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
    end
  end
end
