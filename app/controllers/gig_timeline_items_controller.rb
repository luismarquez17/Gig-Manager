class GigTimelineItemsController < ApplicationController
  before_action :require_leader!
  before_action :set_gig

  def create
    @timeline_item = @gig.gig_timeline_items.build(timeline_item_params)
    @timeline_item.position = @gig.gig_timeline_items.maximum(:position).to_i + 1
    
    if @timeline_item.save
      redirect_to gig_path(@gig), notice: "Hito del cronograma agregado con éxito."
    else
      redirect_to gig_path(@gig), alert: "Error al agregar hito: #{@timeline_item.errors.full_messages.join(', ')}"
    end
  end

  def destroy
    @timeline_item = @gig.gig_timeline_items.find(params[:id])
    @timeline_item.destroy
    redirect_to gig_path(@gig), notice: "Hito del cronograma eliminado con éxito."
  end

  private

  def set_gig
    @gig = Gig.find(params[:gig_id])
  end

  def timeline_item_params
    params.require(:gig_timeline_item).permit(:time, :title, :description, :position, :for_musician)
  end
end
