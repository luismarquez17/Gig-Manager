class FundsController < ApplicationController
  before_action :require_leader!

  def show
    @fund_type = params[:fund_type]
    @allocations = FundAllocation.includes(:fund_expenses, :gig).where(fund_type: @fund_type).order(created_at: :desc)

    @total_allocated = @allocations.sum(:amount)
    @total_spent = @allocations.joins(:fund_expenses).sum('fund_expenses.amount')
    @remaining = @total_allocated - @total_spent
  end
end
