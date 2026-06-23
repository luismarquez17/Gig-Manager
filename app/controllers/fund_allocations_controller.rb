class FundAllocationsController < ApplicationController
  before_action :require_leader!
  before_action :set_gig

  def create
    amount = params.dig(:fund_allocation, :amount).to_f
    fund_type = params.dig(:fund_allocation, :fund_type)
    notes = params.dig(:fund_allocation, :notes)

    if amount <= 0
      redirect_to gig_path(@gig), alert: "El monto debe ser mayor a 0."
      return
    end

    if amount > @gig.remaining_balance.to_f
      redirect_to gig_path(@gig), alert: "El monto excede el sobrante disponible." and return
    end

    allocation = @gig.fund_allocations.create(amount: amount, currency: @gig.currency, fund_type: fund_type, notes: notes)
    if allocation.persisted?
      formatted = view_context.number_with_precision(allocation.amount, precision: 2)
      redirect_to gig_path(@gig), notice: "Asignación registrada: #{allocation.fund_label} - #{formatted}"
    else
      redirect_to gig_path(@gig), alert: allocation.errors.full_messages.join(', ')
    end
  end

  def destroy
    allocation = @gig.fund_allocations.find(params[:id])
    allocation.destroy
    redirect_to gig_path(@gig), notice: "Asignación eliminada."
  rescue ActiveRecord::RecordNotFound
    redirect_to gig_path(@gig), alert: "Asignación no encontrada."
  end

  private

  def set_gig
    @gig = Gig.find(params[:gig_id])
  end
end
