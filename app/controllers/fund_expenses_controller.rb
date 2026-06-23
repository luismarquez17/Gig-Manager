class FundExpensesController < ApplicationController
  before_action :require_leader!
  before_action :set_gig
  before_action :set_fund_allocation

  def create
    amount = params.dig(:fund_expense, :amount).to_f
    notes = params.dig(:fund_expense, :notes)

    if amount <= 0
      redirect_to gig_path(@gig), alert: "El monto debe ser mayor a 0." and return
    end

    if amount > @fund_allocation.remaining
      redirect_to gig_path(@gig), alert: "El monto excede el saldo disponible del fondo." and return
    end

    expense = @fund_allocation.fund_expenses.create(amount: amount, currency: @fund_allocation.currency, notes: notes)
    if expense.persisted?
      formatted = view_context.number_with_precision(expense.amount, precision: 2)
      redirect_to gig_path(@gig), notice: "Gasto registrado: #{formatted} — #{expense.notes.presence || '-'}"
    else
      redirect_to gig_path(@gig), alert: expense.errors.full_messages.join(', ')
    end
  end

  def destroy
    expense = @fund_allocation.fund_expenses.find(params[:id])
    expense.destroy
    redirect_to gig_path(@gig), notice: "Gasto eliminado." 
  rescue ActiveRecord::RecordNotFound
    redirect_to gig_path(@gig), alert: "Gasto no encontrado."
  end

  private

  def set_gig
    @gig = Gig.find(params[:gig_id])
  end

  def set_fund_allocation
    @fund_allocation = @gig.fund_allocations.find(params[:fund_allocation_id])
  end
end
