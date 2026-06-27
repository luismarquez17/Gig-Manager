class InvestmentsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_leader!
  before_action :set_investment, only: [:edit, :update, :destroy]
  layout :resolve_layout

  def index
    @investments = Investment.recent
    @investments = @investments.by_category(params[:category]) if params[:category].present?
    @investments = @investments.by_currency(params[:currency]) if params[:currency].present?
    @investments = @investments.by_source(params[:source]) if params[:source].present?

    @total_usd = Investment.where(currency: 'USD').sum(:amount).to_f
    @total_bs  = Investment.where(currency: 'BS').sum(:amount).to_f
    @total_by_category = Investment.group(:category).sum(:amount)
    @total_by_source = Investment.group(:source).sum(:amount)

    @categories = Investment::CATEGORIES
    @sources = Investment::SOURCES
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
    @total_usd  = Investment.where(currency: 'USD').sum(:amount).to_f
    @total_bs   = Investment.where(currency: 'BS').sum(:amount).to_f

    # Total REALMENTE COBRADO en Gigs
    @total_billed_usd = GigPayment.where(currency: 'USD').sum(:amount).to_f
    @total_billed_bs  = GigPayment.where(currency: 'BS').sum(:amount).to_f

    # Métricas de retorno por moneda
    @net_gain_usd = @total_billed_usd - @total_usd
    @roi_usd      = @total_usd > 0 ? (@net_gain_usd / @total_usd) * 100 : 0

    @net_gain_usd = @total_billed_usd - @total_usd
    @roi_usd      = @total_usd > 0 ? (@net_gain_usd / @total_usd) * 100 : 0

    @net_gain_bs  = @total_billed_bs - @total_bs
    @roi_bs       = @total_bs > 0 ? (@net_gain_bs / @total_bs) * 100 : 0

    @net_gain = @net_gain_usd
    @roi_pct = @roi_usd
    @report_date = Date.today
  end

  private

  def set_investment
    @investment = Investment.find(params[:id])
  end

  def investment_params
    params.require(:investment).permit(:description, :category, :amount, :currency, :date, :notes, :receipt_number, :source, :investor_name)
  end

  def resolve_layout
    action_name == 'report' ? 'print' : 'application'
  end
end
