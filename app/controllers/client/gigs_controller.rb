class Client::GigsController < ApplicationController
  before_action :require_client!
  before_action :set_gig, only: [:show]

  def index
    if current_user.client_id.present?
      @gigs = Gig.where(client_id: current_user.client_id).order(date: :desc)
    else
      @gigs = Gig.none
    end
  end

  def show
    @gig_payments = @gig.gig_payments.order(date_paid: :desc)
    @timeline_items = @gig.gig_timeline_items.order(:position, :time)
    @staff_members = @gig.staff_members.with_attached_avatar
  end

  private

  def require_client!
    unless current_user&.client?
      redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
    end
  end

  def set_gig
    @gig = Gig.find_by(id: params[:id])
    if @gig.nil? || @gig.client_id != current_user.client_id
      redirect_to client_gigs_path, alert: "No tienes acceso a este evento."
    end
  end
end
