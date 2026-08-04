class InvestmentsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_leader!
  before_action :set_investment, only: [:edit, :update, :destroy]
  layout :resolve_layout

  def index
    @investments = current_company.investments
    @investments = @investments.by_category(params[:category]) if params[:category].present?
    @investments = @investments.by_currency(params[:currency]) if params[:currency].present?
    @investments = @investments.by_source(params[:source]) if params[:source].present?

    @total_usd = current_company.investments.where(currency: 'USD').sum(:amount).to_f
    @total_bs  = current_company.investments.where(currency: 'BS').sum(:amount).to_f
    @total_by_category = current_company.investments.group(:category).sum(:amount)
    @total_by_source = current_company.investments.group(:source).sum(:amount)

    @categories = Investment::CATEGORIES
    @sources = Investment::SOURCES
  end

  def new
    @investment = current_company.investments.build
  end

  def create
    @investment = current_company.investments.build(investment_params)
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
    @investments = current_company.investments
    @total_usd  = current_company.investments.where(currency: 'USD').sum(:amount).to_f
    @total_bs   = current_company.investments.where(currency: 'BS').sum(:amount).to_f

    company_gig_payments = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id })
    @total_billed_usd = company_gig_payments.where(currency: 'USD').sum(:amount).to_f
    @total_billed_bs  = company_gig_payments.where(currency: 'BS').sum(:amount).to_f

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
    @investment = current_company.investments.find(params[:id])
  end

  def investment_params
    params.require(:investment).permit(:description, :category, :amount, :currency, :date, :notes, :receipt_number, :source, :investor_name)
  end

  def resolve_layout
    action_name == 'report' ? 'print' : 'application'
  end
end
