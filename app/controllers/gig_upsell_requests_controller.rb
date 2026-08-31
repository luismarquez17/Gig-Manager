class GigUpsellRequestsController < ApplicationController
  before_action :require_leader!
  before_action :set_gig_upsell_request

  def approve
    if @gig_upsell_request.approve!
      # Notificar al cliente por email
      UpsellMailer.upsell_approved(@gig_upsell_request).deliver_later rescue nil

      price_formatted = helpers.number_with_precision(@gig_upsell_request.price, precision: 2)
      redirect_to gig_path(@gig_upsell_request.gig), notice: "Adicional '#{@gig_upsell_request.title}' aprobado con éxito (+ $#{price_formatted} #{@gig_upsell_request.currency}). El precio acordado del evento se actualizó automáticamente."
    else
      redirect_to gig_path(@gig_upsell_request.gig), alert: "No se pudo aprobar la solicitud: #{@gig_upsell_request.errors.full_messages.join(', ')}"
    end
  end

  def reject
    if @gig_upsell_request.reject!
      # Notificar al cliente por email
      UpsellMailer.upsell_rejected(@gig_upsell_request).deliver_later rescue nil

      redirect_to gig_path(@gig_upsell_request.gig), notice: "Solicitud de adicional '#{@gig_upsell_request.title}' rechazada. El precio acordado del evento no fue modificado."
    else
      redirect_to gig_path(@gig_upsell_request.gig), alert: "No se pudo rechazar la solicitud: #{@gig_upsell_request.errors.full_messages.join(', ')}"
    end
  end

  private

  def set_gig_upsell_request
    if current_user.superadmin? && session[:superadmin_company_id].blank?
      @gig_upsell_request = GigUpsellRequest.find(params[:id])
    else
      @gig_upsell_request = current_company.gig_upsell_requests.find(params[:id])
    end
  end
end
