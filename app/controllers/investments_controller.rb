class InvestmentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_investment, only: [:edit, :update, :destroy]
  layout :resolve_layout

  def index
    @investments = Investment.recent
    @investments = @investments.by_category(params[:category]) if params[:category].present?
    @investments = @investments.by_currency(params[:currency]) if params[:currency].present?

    @total_usd = Investment.where(currency: 'USD').sum(:amount)
    @total_bs  = Investment.where(currency: 'BS').sum(:amount)
    @total_by_category = Investment.group(:category).sum(:amount)

    @categories = Investment::CATEGORIES
  end

  def new
    @investment = Investment.new
  end

  def create
    @investment = Investment.new(investment_params)
    if @investment.save
      redirect_to investments_path, notice: "✅ Inversión registrada correctamente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @investment.update(investment_params)
      redirect_to investments_path, notice: "✅ Inversión actualizada correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @investment.destroy
    redirect_to investments_path, notice: "🗑️ Inversión eliminada."
  end

  def report
    @investments = Investment.recent
    @total_usd  = Investment.where(currency: 'USD').sum(:amount)
    @total_bs   = Investment.where(currency: 'BS').sum(:amount)

    # Total facturado en Gigs (USD)
    @total_billed_usd = Gig.where(currency: 'USD').sum(:amount)

    # Métricas de retorno (en USD)
    @net_gain   = @total_billed_usd - @total_usd
    @roi_pct    = @total_usd > 0 ? (@net_gain / @total_usd) * 100 : 0

    @report_date = Date.today
  end

  private

  def set_investment
    @investment = Investment.find(params[:id])
  end

  def investment_params
    params.require(:investment).permit(:description, :category, :amount, :currency, :date, :notes, :receipt_number)
  end

  def resolve_layout
    action_name == 'report' ? 'print' : 'application'
  end
end
