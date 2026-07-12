class PortalsController < ApplicationController
  skip_before_action :authenticate_user!
  layout 'portal'

  before_action :set_gig

  def show
    @client = @gig.client
    @gig_payments = @gig.gig_payments.order(date_paid: :desc)
    @timeline_items = @gig.gig_timeline_items.for_client.order(:position, :time)
    @staff_members = @gig.staff_members.with_attached_avatar
  end

  def worker_profile
    @worker = User.find(params[:worker_id])
    unless @gig.staff_members.include?(@worker)
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
      return
    end
  end

  def sign_contract
    if params[:signature_name].blank?
      render json: { success: false, error: "El nombre es obligatorio para firmar." }, status: :unprocessable_entity
      return
    end

    if @gig.update(
      contract_signed: true,
      contract_signed_at: Time.current,
      contract_signed_ip: request.remote_ip,
      contract_signed_name: params[:signature_name]
    )
      render json: { 
        success: true, 
        signed_at: @gig.contract_signed_at.strftime("%d/%m/%Y %I:%M %p"),
        ip: @gig.contract_signed_ip,
        name: @gig.contract_signed_name
      }
    else
      render json: { success: false, error: "No se pudo registrar la firma." }, status: :unprocessable_entity
    end
  end

  private

  def set_gig
    @gig = Gig.find_by(portal_token: params[:token])
    if @gig.nil?
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
    end
  end
end
