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

  def new
    @maintenance_record = MaintenanceRecord.new
    @items = Item.order(:name)
  end

  def create
    mode = params[:mode]
    qty = params[:quantity].to_i
    qty = 1 if qty <= 0

    status = params[:initial_status] || 'pending' # 'pending' or 'discarded'
    description = params[:description].presence || "Reportado desde el Taller"
    started_at = params[:started_at].presence || Date.today
    completed_at = (status == 'discarded') ? Date.today : nil

    ActiveRecord::Base.transaction do
      if mode == 'new'
        category = params[:category]
        sub_category = nil
        if category == "Cables" && params[:sub_category_cable].present?
          sub_category = params[:sub_category_cable]
        elsif category == "Luces" && params[:sub_category_light].present?
          sub_category = params[:sub_category_light]
        end

        @item = Item.new(
          name: params[:name],
          category: category,
          sub_category: sub_category,
          status: (status == 'discarded' ? 'Dañado' : 'Excelente'),
          quantity: qty,
          notes: "[#{Date.today.strftime('%d/%m/%Y')}] Creado desde el taller como #{status == 'discarded' ? 'Pérdida Total' : 'Dañado'}: #{description}"
        )

        unless @item.save
          @items = Item.order(:name)
          @maintenance_record = MaintenanceRecord.new
          flash.now[:alert] = "Error al crear el nuevo equipo: #{@item.errors.full_messages.join(', ')}"
          render :new, status: :unprocessable_entity
          return
        end

        new_items = @item.inventory_items.to_a
        qty.times do |i|
          ii = new_items[i] || @item.inventory_items.create!(status: :available)
          MaintenanceRecord.create!(
            item: @item,
            inventory_item: ii,
            status: status,
            description: description,
            started_at: started_at,
            completed_at: completed_at,
            cost: 0.0
          )
        end

      else # mode == 'existing'
        @item = Item.find_by(id: params[:item_id])
        if @item.nil?
          @items = Item.order(:name)
          @maintenance_record = MaintenanceRecord.new
          flash.now[:alert] = "Debes seleccionar un equipo existente."
          render :new, status: :unprocessable_entity
          return
        end

        existing_action = params[:existing_action]

        if existing_action == 'add_extra'
          new_qty = @item.quantity.to_i + qty
          @item.update!(quantity: new_qty)
          
          new_items = @item.inventory_items.where(status: :available).last(qty)
          qty.times do |i|
            ii = new_items[i]
            MaintenanceRecord.create!(
              item: @item,
              inventory_item: ii,
              status: status,
              description: description,
              started_at: started_at,
              completed_at: completed_at,
              cost: 0.0
            )
          end

        else # 'mark_damaged'
          if status == 'discarded'
            to_discard = @item.inventory_items.order(status: :asc).limit(qty).to_a
            
            if to_discard.empty?
              qty.times do
                MaintenanceRecord.create!(
                  item: @item,
                  inventory_item: nil,
                  status: :discarded,
                  description: description,
                  started_at: started_at,
                  completed_at: completed_at,
                  cost: 0.0
                )
              end
            else
              to_discard.each do |ii|
                MaintenanceRecord.create!(
                  item: @item,
                  inventory_item: ii,
                  status: :discarded,
                  description: description,
                  started_at: started_at,
                  completed_at: completed_at,
                  cost: 0.0
                )
              end
              if qty > to_discard.size
                (qty - to_discard.size).times do
                  MaintenanceRecord.create!(
                    item: @item,
                    inventory_item: nil,
                    status: :discarded,
                    description: description,
                    started_at: started_at,
                    completed_at: completed_at,
                    cost: 0.0
                  )
                end
              end
            end
          else # status is pending/in_repair
            availables = @item.inventory_items.where(status: :available).limit(qty).to_a
            
            if availables.size < qty
              @items = Item.order(:name)
              @maintenance_record = MaintenanceRecord.new
              flash.now[:alert] = "No hay suficientes unidades disponibles en inventario para marcar como dañadas. Solo hay #{availables.size} disponibles."
              render :new, status: :unprocessable_entity
              return
            end

            availables.each do |ii|
              MaintenanceRecord.create!(
                item: @item,
                inventory_item: ii,
                status: status,
                description: description,
                started_at: started_at,
                completed_at: completed_at,
                cost: 0.0
              )
            end
          end
        end
      end
    end

    redirect_to maintenance_records_path, notice: "Equipo dañado reportado exitosamente."
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
