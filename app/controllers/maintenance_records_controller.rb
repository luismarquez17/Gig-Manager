class MaintenanceRecordsController < ApplicationController
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
  end

  def update
    # Si pasa a fixed o discarded, registramos la fecha de finalización
    if ["fixed", "discarded"].include?(maintenance_record_params[:status])
      @maintenance_record.completed_at = Date.today
    end

    if @maintenance_record.update(maintenance_record_params)
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
