class BandLandingController < ApplicationController
  skip_before_action :authenticate_user!
  layout 'band_landing'

  before_action :set_company

  def show
    @preset_budgets = @company.preset_budgets.order(:price)
    @staff_members = @company.users.where(role: [:leader, :musician, :staff])
    @reviews = @company.approved_reviews.order(pinned: :desc, created_at: :desc).limit(12)
    @standard_upsells = StandardUpsell.where(company: @company).presence || StandardUpsell.all_with_defaults.select(&:active)
    @rating = @company.average_rating
    @reviews_count = @reviews.count
  end

  def quote
    @preset_budgets = @company.preset_budgets.order(:price)
    @standard_upsells = StandardUpsell.where(company: @company).presence || StandardUpsell.all_with_defaults.select(&:active)
  end

  private

  def set_company
    @company = Company.find_by(slug: params[:slug])
    if @company.nil?
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
    end
  end
end
