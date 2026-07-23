class InventoryItemsController < ApplicationController
  before_action :require_leader!

  def update
    @item = Item.find(params[:item_id])
    @inventory_item = @item.inventory_items.find(params[:id])
    previous_status = @inventory_item.status

    if @inventory_item.update(inventory_item_params)
      if @inventory_item.damaged? && previous_status != 'damaged'
        unless @inventory_item.maintenance_records.where(status: [:pending, :in_repair]).any?
          MaintenanceRecord.create!(
            item: @item,
            inventory_item: @inventory_item,
            status: :pending,
            description: params[:damage_description].presence || "Unidad marcada como dañada desde el inventario",
            started_at: Date.today,
            cost: 0.0
          )
        end
        redirect_to item_path(@item), notice: "Unidad física marcada como dañada y enviada al Taller de reparaciones."
      else
        redirect_to item_path(@item), notice: "Unidad física actualizada correctamente."
      end
    else
      redirect_to item_path(@item), alert: "Error al actualizar la unidad física: #{@inventory_item.errors.full_messages.join(', ')}"
    end
  end

  private

  def inventory_item_params
    params.require(:inventory_item).permit(:status, :serial_number)
  end
end
