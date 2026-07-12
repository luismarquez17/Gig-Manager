class CategoriesController < ApplicationController
  before_action :require_leader!

  def create
    @category = Category.new(category_params)
    respond_to do |format|
      if @category.save
        format.html { redirect_to items_path, notice: "✅ Categoría '#{@category.name}' creada correctamente." }
        format.json { render json: { success: true, category: @category } }
      else
        format.html { redirect_to items_path, alert: "No se pudo crear la categoría: #{@category.errors.full_messages.join(', ')}" }
        format.json { render json: { success: false, errors: @category.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @category = Category.find(params[:id])
    name = @category.name
    @category.destroy
    redirect_to items_path, notice: "🗑️ Categoría '#{name}' eliminada."
  end

  private

  def category_params
    params.require(:category).permit(:name)
  end
end
