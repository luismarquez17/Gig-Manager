class SubCategoriesController < ApplicationController
  before_action :require_leader!

  def create
    @sub_category = SubCategory.new(sub_category_params)
    respond_to do |format|
      if @sub_category.save
        format.html { redirect_back fallback_location: items_path, notice: "✅ Sub-categoría '#{@sub_category.name}' creada correctamente." }
        format.json { render json: { success: true, sub_category: @sub_category } }
      else
        format.html { redirect_back fallback_location: items_path, alert: "No se pudo crear la sub-categoría: #{@sub_category.errors.full_messages.join(', ')}" }
        format.json { render json: { success: false, errors: @sub_category.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @sub_category = SubCategory.find(params[:id])
    name = @sub_category.name
    @sub_category.destroy
    redirect_back fallback_location: items_path, notice: "🗑️ Sub-categoría '#{name}' eliminada."
  end

  private

  def sub_category_params
    params.require(:sub_category).permit(:name, :category)
  end
end
