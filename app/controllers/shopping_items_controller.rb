class ShoppingItemsController < ApplicationController
  before_action :require_leader!
  before_action :set_shopping_item, only: [:edit, :update, :destroy, :toggle_purchased, :add_to_inventory, :increment_inventory]


  def index
    @shopping_items = ShoppingItem.all

    # Filtros
    @shopping_items = @shopping_items.where(status: params[:status]) if params[:status].present?
    @shopping_items = @shopping_items.where(priority: params[:priority]) if params[:priority].present?
    @shopping_items = @shopping_items.where(category: params[:category]) if params[:category].present?

    @shopping_items = @shopping_items.pending_first

    # Stats
    @total_count    = ShoppingItem.count
    @pending_count  = ShoppingItem.pending.count
    @purchased_count = ShoppingItem.purchased.count
    @total_estimated = ShoppingItem.pending.where(currency: 'USD').sum(:estimated_price).to_f
    @total_estimated_bs = ShoppingItem.pending.where(currency: 'BS').sum(:estimated_price).to_f

    @categories = ShoppingItem::CATEGORIES
  end

  def new
    @shopping_item = ShoppingItem.new
    @categories = ShoppingItem::CATEGORIES
  end

  def create
    @shopping_item = ShoppingItem.new(shopping_item_params)
    if @shopping_item.save
      redirect_to shopping_items_path, notice: "✅ Ítem agregado a la lista de compras."
    else
      @categories = ShoppingItem::CATEGORIES
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @categories = ShoppingItem::CATEGORIES
  end

  def update
    if @shopping_item.update(shopping_item_params)
      redirect_to shopping_items_path, notice: "✏️ Ítem actualizado correctamente."
    else
      @categories = ShoppingItem::CATEGORIES
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @shopping_item.destroy
    redirect_to shopping_items_path, notice: "🗑️ Ítem eliminado de la lista."
  end

  def toggle_purchased
    if @shopping_item.pending?
      @shopping_item.update!(status: :purchased)
      # Redirigir a la página de "¿Añadir al inventario?"
      redirect_to add_to_inventory_shopping_item_path(@shopping_item)
    else
      @shopping_item.update!(status: :pending)
      redirect_to shopping_items_path, notice: "↩️ \"#{@shopping_item.name}\" marcado como pendiente."
    end
  end

  def add_to_inventory
    # Sugerencia automática por nombre (puede estar vacía)
    @suggested_item = Item.where("unaccent(name) ILIKE unaccent(?)", @shopping_item.name.strip).first

    # Lista completa del inventario para que el usuario elija manualmente
    @all_items = Item.order(:category, :name)

    # Formulario pre-llenado para el caso de crear uno nuevo
    @item = Item.new(
      name:     @shopping_item.name,
      category: map_category(@shopping_item.category),
      status:   "Excelente",
      quantity: 1
    )
  end

  # Suma 1 unidad a un ítem de inventario existente
  def increment_inventory
    amount = (params[:amount].presence || 1).to_i
    existing_item = Item.find(params[:item_id])
    new_quantity = (existing_item.quantity || 0) + amount
    existing_item.update!(quantity: new_quantity)
    redirect_to shopping_items_path,
      notice: "📦 Se añadió #{amount} unidad#{'es' if amount > 1} de \"#{existing_item.name}\" al inventario. Ahora tiene #{new_quantity} en total. 🎉"
  end

  private

  def set_shopping_item
    @shopping_item = ShoppingItem.find(params[:id])
  end

  def shopping_item_params
    params.require(:shopping_item).permit(
      :name, :category, :reason, :purpose,
      :estimated_price, :currency, :priority, :status, :notes
    )
  end

  # Mapea categorías del carrito a las categorías del inventario
  def map_category(shopping_category)
    mapping = {
      "Cables"             => "Cables",
      "Micrófonos"         => "Microfonos",
      "Iluminación"        => "Luces",
      "Audio / Mezcla"     => "Consolas",
      "Instrumentos"       => "Bajos",
      "Accesorios"         => "Accesorios",
      "Transporte / Carga" => "Estructuras",
      "Energía / Corriente" => "Accesorios",
      "Herramientas"       => "Accesorios",
      "Otros"              => nil
    }
    mapping[shopping_category]
  end
end

