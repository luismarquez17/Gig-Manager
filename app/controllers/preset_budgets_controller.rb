class PresetBudgetsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show]
  before_action :require_leader!, only: [:new, :create, :edit, :update, :destroy, :print]
  before_action :set_preset_budget, only: [:show, :edit, :update, :destroy, :print]

  def index
    @preset_budgets = current_company.preset_budgets.order(created_at: :desc)
  end

  def show
  end

  def new
    @preset_budget = current_company.preset_budgets.build
  end

  def create
    @preset_budget = current_company.preset_budgets.build(preset_budget_params)
    if @preset_budget.save
      redirect_to preset_budgets_path, notice: "🎯 ¡Presupuesto base creado con éxito!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @preset_budget.update(preset_budget_params)
      redirect_to preset_budgets_path, notice: "✅ Presupuesto base actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @preset_budget.destroy
    redirect_to preset_budgets_path, notice: "🗑️ Presupuesto base eliminado."
  end

  def print
    render layout: false
  end

  private

  def set_preset_budget
    @preset_budget = current_company ? current_company.preset_budgets.find(params[:id]) : PresetBudget.find(params[:id])
  end

  def preset_budget_params
    params.require(:preset_budget).permit(:title, :description, :price, :currency, :image)
  end
end
