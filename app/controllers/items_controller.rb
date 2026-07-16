class ItemsController < ApplicationController
  before_action :require_leader!
  before_action :set_item, only: [:show, :edit, :update, :destroy]

  def index
    @items = Item.all

    # 1. Búsqueda por Nombre O Subcategoría (Texto libre)
    if params[:query].present?
      # El operador OR permite que si buscas "RCA" encuentre el equipo aunque el nombre sea "Cable 1"
      @items = @items.where("name ILIKE :q OR sub_category ILIKE :q", q: "%#{params[:query]}%")
    end

    # 2. Filtro por Categoría
    if params[:category].present?
      @items = @items.where(category: params[:category])
    end

    # 3. Filtro por Estado (Excelente, Operativo, Dañado)
    if params[:status].present?
      @items = @items.where(status: params[:status])
    end

    # Ordenamiento final
    @items = @items.order(category: :asc, name: :asc)
  end

  def show
  end

  def new
    @item = Item.new
  end

  def create
    handle_sub_categories
    @item = Item.new(item_params)
    @item.status ||= "Excelente"

    if @item.save
      if params[:from_shopping_item].present?
        redirect_to shopping_items_path,
          notice: "📦 ¡\"#{@item.name}\" añadido al inventario exitosamente! Ya está disponible para tus próximos gigs. 🎉"
      else
        redirect_to items_path, notice: "Equipo registrado exitosamente."
      end
    else
      render :new, status: :unprocessable_entity
    end
  end


  def edit
  end

  def update
    handle_sub_categories
    
    if @item.update(item_params)
      redirect_to items_path, notice: "Equipo actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @item.destroy
    redirect_to items_path, notice: "Equipo eliminado."
  end

  private

  def set_item
    @item = Item.find(params[:id])
  end

  def handle_sub_categories
    return if params[:item].blank?

    # Asignamos el valor de los selects dinámicos a la columna real sub_category
    if params[:item][:sub_category_cable].present?
      params[:item][:sub_category] = params[:item][:sub_category_cable]
    elsif params[:item][:sub_category_light].present?
      params[:item][:sub_category] = params[:item][:sub_category_light]
    end

    # Limpiamos los parámetros virtuales para que no den error al guardar/actualizar
    params[:item].delete(:sub_category_cable)
    params[:item].delete(:sub_category_light)
  end

  def item_params
    params.require(:item).permit(
      :name, 
      :category, 
      :sub_category, 
      :status, 
      :quantity, 
      :notes, 
      :sub_category_cable, 
      :sub_category_light
    )
  end
end