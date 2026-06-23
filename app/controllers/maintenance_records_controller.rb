class MaintenanceRecordsController < ApplicationController
  before_action :require_leader!
  before_action :set_maintenance_record, only: [:edit, :update]

  def index
    @maintenance_records = MaintenanceRecord.includes(:item, :gig).order(created_at: :desc)
    @active_records = @maintenance_records.where(status: [:pending, :in_repair])
    @resolved_records = @maintenance_records.where(status: [:fixed, :discarded])

    @total_cost = MaintenanceRecord.sum(:cost)
    @pending_count = @active_records.where(status: :pending).count
    @in_repair_count = @active_records.where(status: :in_repair).count
  end

  def edit
    # saldo disponible en repairs
    total_alloc = FundAllocation.where(fund_type: 'repairs').sum(:amount)
    total_spent = FundAllocation.joins(:fund_expenses).where(fund_type: 'repairs').sum('fund_expenses.amount')
    @repairs_available = total_alloc.to_f - total_spent.to_f
  end

  def update
    # Si pasa a fixed o discarded, registramos la fecha de finalización
    if ["fixed", "discarded"].include?(maintenance_record_params[:status])
      @maintenance_record.completed_at = Date.today
    end

    allow_cross = params[:allow_cross_fund] == '1'
    if @maintenance_record.update(maintenance_record_params)
      # Si se marca como fixed, intentamos cargar el costo desde fondos
      if @maintenance_record.status == 'fixed' && @maintenance_record.cost.to_f > 0
        begin
          res = @maintenance_record.charge_from_funds!(allow_cross_fund: allow_cross)
          unless res[:success]
            redirect_to edit_maintenance_record_path(@maintenance_record), alert: "Fondos insuficientes para cubrir el costo. Marca 'Permitir usar otros fondos' o asigna fondos primero." and return
          end
        rescue => e
          redirect_to edit_maintenance_record_path(@maintenance_record), alert: "No se pudo cargar el monto: #{e.message}" and return
        end
      end

      redirect_to maintenance_records_path, notice: "Registro de taller actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_maintenance_record
    @maintenance_record = MaintenanceRecord.find(params[:id])
  end

  def maintenance_record_params
    params.require(:maintenance_record).permit(:status, :cost, :description, :started_at, :completed_at)
  end
end
