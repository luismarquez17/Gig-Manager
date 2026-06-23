class GigItemsController < ApplicationController
  before_action :require_leader!, only: [:create, :destroy]
  before_action :require_staff_or_leader!, only: [:toggle, :update_quantities, :report_damage, :report_lost]
  before_action :check_gig_item_assignment, only: [:toggle, :update_quantities, :report_damage, :report_lost]

  def check_gig_item_assignment
    @gig_item = GigItem.find(params[:id])
    unless current_user.leader? || current_user.assigned_gigs.include?(@gig_item.gig)
      respond_to do |format|
        format.html { redirect_to root_path, alert: "No tienes permiso." }
        format.json { render json: { success: false, error: "No tienes permiso." }, status: :forbidden }
      end
    end
  end

  def create
    @gig = Gig.find(params[:gig_id])
    item_id = params[:gig_item][:item_id]
    
    if item_id.blank?
      redirect_to gig_path(@gig), alert: "Debes seleccionar un producto válido del inventario."
      return
    end

    @gig_item = @gig.gig_items.build(gig_item_params)
    
    if @gig_item.save
      redirect_to gig_path(@gig), notice: "Equipo agregado a la lista del evento."
    else
      redirect_to gig_path(@gig), alert: "Error al agregar equipo: #{@gig_item.errors.full_messages.join(', ')}"
    end
  end

  def destroy
    @gig_item = GigItem.find(params[:id])
    @gig = @gig_item.gig
    @gig_item.destroy
    redirect_to gig_path(@gig), notice: "Equipo removido de la lista."
  end

  def toggle
    @gig_item ||= GigItem.find(params[:id])
    @gig_item.update(checked: !@gig_item.checked)
    
    respond_to do |format|
      format.html { redirect_to gig_path(@gig_item.gig) }
      format.json { render json: { success: true, checked: @gig_item.checked } }
    end
  end

  def update_quantities
    @gig_item ||= GigItem.find(params[:id])
    loaded = params[:loaded_quantity].to_i
    returned = params[:returned_quantity].to_i

    # Ajustamos límites de seguridad en backend
    loaded = [[loaded, 0].max, @gig_item.quantity].min
    returned = [[returned, 0].max, loaded].min

    if @gig_item.update(loaded_quantity: loaded, returned_quantity: returned)
      render json: { 
        success: true, 
        loaded_quantity: @gig_item.loaded_quantity, 
        returned_quantity: @gig_item.returned_quantity,
        discrepancy: @gig_item.discrepancy?
      }
    else
      render json: { success: false, error: @gig_item.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def report_damage
    @gig_item ||= GigItem.find(params[:id])
    @item = @gig_item.item
    @gig = @gig_item.gig

    damage_notes = params[:notes].to_s.strip

    if damage_notes.blank?
      render json: { success: false, error: "Las notas de daño son requeridas." }, status: :unprocessable_entity
      return
    end

    # Construimos la nota de daño con contexto completo
    damage_entry = "[#{Date.today.strftime('%d/%m/%Y')}] Daño en Show con #{@gig.client.name}"
    damage_entry += " (#{@gig.date&.strftime('%d/%m/%Y')})" if @gig.date.present?
    damage_entry += ": #{damage_notes}"

    existing_notes = @item.notes.presence || ""
    new_notes = existing_notes.empty? ? damage_entry : "#{existing_notes}\n#{damage_entry}"

    ActiveRecord::Base.transaction do
      @item.update!(notes: new_notes)
      # El callback de MaintenanceRecord asignará automáticamente un InventoryItem disponible
      # y lo pondrá en estado 'maintenance'. El Item se marcará como 'Operativo' o 'Dañado'
      # según cuántas copias queden disponibles.
      MaintenanceRecord.create!(
        item: @item,
        gig: @gig,
        description: "Reportado en evento: #{damage_notes}",
        status: :pending,
        cost: 0.00,
        started_at: Date.today
      )
    end

    render json: { success: true }
  rescue => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  def report_lost
    @gig_item ||= GigItem.find(params[:id])
    @item = @gig_item.item
    @gig = @gig_item.gig
    lost_qty = params[:quantity].to_i
    lost_notes = params[:notes].to_s.strip

    if lost_qty <= 0
      render json: { success: false, error: "La cantidad perdida debe ser mayor a cero." }, status: :unprocessable_entity
      return
    end

    if lost_notes.blank?
      render json: { success: false, error: "Las notas de pérdida son requeridas." }, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      # Ajustamos la cantidad retornada en el gig para cuadrar la carga
      new_returned = [[@gig_item.returned_quantity + lost_qty, 0].max, @gig_item.loaded_quantity].min
      @gig_item.update!(returned_quantity: new_returned)

      # Registramos la pérdida en las notas del ítem
      lost_entry = "[#{Date.today.strftime('%d/%m/%Y')}][PÉRDIDA] #{lost_qty} ud(s) en Show con #{@gig.client.name} (#{@gig.date&.strftime('%d/%m/%Y')}): #{lost_notes}"
      existing_notes = @item.notes.presence || ""
      new_notes = existing_notes.empty? ? lost_entry : "#{existing_notes}\n#{lost_entry}"
      @item.update!(notes: new_notes)

      # Por cada unidad perdida creamos un MaintenanceRecord en estado :discarded.
      # El callback de MaintenanceRecord eliminará el InventoryItem asociado y
      # decrementará automáticamente item.quantity.
      lost_qty.times do
        MaintenanceRecord.create!(
          item: @item,
          gig: @gig,
          description: "PÉRDIDA EN EVENTO: #{lost_notes}",
          status: :discarded,
          cost: 0.00,
          started_at: Date.today,
          completed_at: Date.today
        )
      end
    end

    render json: { success: true }
  rescue => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def gig_item_params
    params.require(:gig_item).permit(:item_id, :quantity)
  end
end
