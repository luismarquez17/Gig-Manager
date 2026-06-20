class KitsController < ApplicationController
  before_action :set_kit, only: [:show, :edit, :update, :destroy, :add_item, :remove_item]

  def index
    @kits = Kit.all
  end

  def show
    @kit_items = @kit.kit_items.includes(:item).order('items.name ASC')
    @new_kit_item = KitItem.new
  end

  def new
    @kit = Kit.new
  end

  def create
    @kit = Kit.new(kit_params)
    if @kit.save
      redirect_to kit_path(@kit), notice: "🎉 Plantilla creada. Ahora agrega los equipos."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @kit.update(kit_params)
      redirect_to kits_path, notice: "Plantilla actualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @kit.destroy
    redirect_to kits_path, notice: "Plantilla eliminada."
  end

  # Acción para agregar un equipo al Kit
  def add_item
    item_id = params[:kit_item][:item_id]
    quantity = params[:kit_item][:quantity].to_i

    if item_id.blank?
      redirect_to kit_path(@kit), alert: "Selecciona un equipo válido."
      return
    end

    # Si ya existe el item en el kit, sumamos la cantidad
    existing_item = @kit.kit_items.find_by(item_id: item_id)
    if existing_item
      existing_item.update(quantity: existing_item.quantity + quantity)
    else
      @kit.kit_items.create(item_id: item_id, quantity: quantity)
    end

    redirect_to kit_path(@kit), notice: "Equipo añadido a la plantilla."
  end

  # Acción para remover un equipo del Kit
  def remove_item
    kit_item = @kit.kit_items.find(params[:item_id])
    kit_item.destroy
    redirect_to kit_path(@kit), notice: "Equipo removido de la plantilla."
  end

  private

  def set_kit
    @kit = Kit.find(params[:id])
  end

  def kit_params
    params.require(:kit).permit(:name, :description)
  end
end
