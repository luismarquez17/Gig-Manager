class InventoryItemsController < ApplicationController
  before_action :require_leader!

  def update
    @item = Item.find(params[:item_id])
    @inventory_item = @item.inventory_items.find(params[:id])

    if @inventory_item.update(inventory_item_params)
      redirect_to item_path(@item), notice: "Unidad física actualizada correctamente."
    else
      redirect_to item_path(@item), alert: "Error al actualizar la unidad física: #{@inventory_item.errors.full_messages.join(', ')}"
    end
  end

  private

  def inventory_item_params
    params.require(:inventory_item).permit(:status, :serial_number)
  end
end
