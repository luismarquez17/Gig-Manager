class StandardUpsellsController < ApplicationController
  before_action :require_leader!
  before_action :set_standard_upsell, only: [:edit, :update, :destroy]

  def index
    @standard_upsells = current_company.standard_upsells.all_with_defaults
  end

  def new
    @standard_upsell = current_company.standard_upsells.build(currency: 'USD', active: true)
  end

  def create
    @standard_upsell = current_company.standard_upsells.build(standard_upsell_params)
    if @standard_upsell.save
      redirect_to standard_upsells_path, notice: "Adicional estándar '#{@standard_upsell.title}' creado exitosamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @standard_upsell.update(standard_upsell_params)
      redirect_to standard_upsells_path, notice: "Adicional estándar '#{@standard_upsell.title}' actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @standard_upsell.title
    @standard_upsell.destroy
    redirect_to standard_upsells_path, notice: "Adicional '#{title}' eliminado."
  end

  private

  def set_standard_upsell
    @standard_upsell = current_company.standard_upsells.find(params[:id])
  end

  def standard_upsell_params
    params.require(:standard_upsell).permit(:title, :emoji, :price, :currency, :description, :active, :key)
  end
end
