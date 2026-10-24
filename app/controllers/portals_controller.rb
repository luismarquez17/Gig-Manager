# frozen_string_literal: true

class PortalsController < ApplicationController
  include Portals::AuthenticationActions
  include Portals::ClientActions

  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: [:sign_contract, :request_upsell]
  layout 'portal'

  before_action :set_gig

  def show
    @client = @gig.client
    @gig_payments = @gig.company&.module_enabled?(:finances) ? @gig.gig_payments.order(date_paid: :desc) : []
    @timeline_items = @gig.company&.module_enabled?(:gigs) ? @gig.gig_timeline_items.for_client.order(:position, :time) : []
    @staff_members = @gig.company&.module_enabled?(:payroll) ? @gig.staff_members.with_attached_avatar : []
  end

  def payment_receipt
    @payment = @gig.gig_payments.find_by(id: params[:payment_id])
    if @payment.nil?
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
      return
    end
    @company = @gig.company
    @client = @gig.client
    render 'gig_payments/receipt', layout: false
  end

  def worker_profile
    unless @gig.company&.module_enabled?(:payroll)
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
      return
    end

    @worker = User.find(params[:worker_id])
    unless @gig.staff_members.include?(@worker)
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
      return
    end
  end

  private

  def set_gig
    @gig = Gig.find_by(portal_token: params[:token])
    if @gig.nil?
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
    else
      ActsAsTenant.current_tenant = @gig.company
      Current.company = @gig.company
    end
  end
end
