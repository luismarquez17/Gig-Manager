class GigsController < ApplicationController
  before_action :require_leader!, except: [:show, :load_in_checklist, :my]
  before_action :require_staff_or_leader!, only: [:show, :load_in_checklist, :print_contract]
  before_action :check_gig_assignment, only: [:show, :load_in_checklist]

  def check_gig_assignment
    @gig = current_company.gigs.find_by!(id: params[:id])
    unless current_user.superadmin? || current_user.leader? || current_user.assigned_gigs.include?(@gig)
      redirect_to root_path, alert: "No tienes asignado este evento."
    end
  end

  def index
    # 1. Unimos la tabla de clientes para poder buscar y filtrar dentro de la empresa
    @gigs = current_company.gigs.left_joins(:client).includes(:client, :gig_payments, :fund_allocations)

    # Conteo global de shows con fondos por asignar
    @unallocated_gigs_count = current_company.gigs.with_unallocated_funds.count

    # 2. Buscador inteligente por nombre de cliente, teléfono, correo, ubicación o detalles del toque
    if params[:query].present?
      terms = params[:query].split(/\s+/)
      terms.each do |term|
        next if term.blank?
        query_term = "%#{term}%"
        @gigs = @gigs.where(
          "unaccent(clients.name) ILIKE unaccent(?) OR " \
          "clients.phone ILIKE ? OR " \
          "unaccent(gigs.location) ILIKE unaccent(?) OR " \
          "unaccent(gigs.details) ILIKE unaccent(?) OR " \
          "gigs.client_email ILIKE ?",
          query_term, query_term, query_term, query_term, query_term
        )
      end
    end

    # 3. Filtro por prioridad
    if params[:priority].present?
      @gigs = @gigs.where(clients: { priority: params[:priority].downcase })
    end

    # Filtro por Fecha (Próximos vs Pasados)
    if params[:date_filter] == "upcoming"
      @gigs = @gigs.where("gigs.date >= ?", Date.today)
    elsif params[:date_filter] == "past"
      @gigs = @gigs.where("gigs.date < ?", Date.today)
    end

    # Filtro por Asignación de Fondos (ej. fondos cobrados pero no asignados a nada)
    case params[:funds_filter]
    when "unallocated"
      @gigs = @gigs.with_unallocated_funds
    when "no_allocations"
      @gigs = @gigs.without_any_fund_allocations
    when "fully_allocated"
      @gigs = @gigs.fully_allocated_funds
    end

    # 4. Lógica de Ordenamiento Dinámico
    case params[:sort]
    when "monto_desc"
      @gigs = @gigs.order(amount: :desc)
    when "monto_asc"
      @gigs = @gigs.order(amount: :asc)
    when "fecha_asc"
      @gigs = @gigs.order(date: :asc)
    when "fecha_desc"
      @gigs = @gigs.order(date: :desc)
    else
      # Si el filtro es "Próximos", ordenamos del show más cercano (Date.today ➔ Futuro)
      if params[:date_filter] == "upcoming"
        @gigs = @gigs.order(date: :asc)
      else
        # Orden por defecto general: Fecha más reciente primero
        @gigs = @gigs.order(date: :desc)
      end
    end
    
    # 5. Cálculos para el resumen (basados en la lista ya filtrada)
    # Mostramos dinero REALMENTE COBRADO (gig_payments), no el presupuesto acordado
    gig_ids = @gigs.pluck(:id)
    @total_usd = GigPayment.where(gig_id: gig_ids, currency: 'USD').sum(:amount).to_f
    @total_bs = GigPayment.where(gig_id: gig_ids, currency: 'BS').sum(:amount).to_f
  end

  def show
    @gig ||= Gig.find(params[:id])
    @gig_items = @gig.gig_items.includes(:item).order('items.name ASC')
    @new_gig_item = GigItem.new
  end

  def load_in_checklist
    @gig ||= Gig.find(params[:id])
    @gig_items = @gig.gig_items.includes(:item).order('items.name ASC')
    # Use a layout specifically without navbar, or render false and build full html
    render layout: false
  end

  def add_kit
    @gig = Gig.find(params[:id])
    kit = Kit.find(params[:kit_id])

    if kit.kit_items.empty?
      redirect_to gig_path(@gig), alert: "La plantilla seleccionada está vacía."
      return
    end

    ActiveRecord::Base.transaction do
      kit.kit_items.each do |kit_item|
        gig_item = @gig.gig_items.find_or_initialize_by(item_id: kit_item.item_id)
        gig_item.quantity ||= 0
        gig_item.quantity += kit_item.quantity
        gig_item.save!
      end
    end

    redirect_to gig_path(@gig), notice: "Plantilla '#{kit.name}' aplicada con éxito al evento."
  rescue ActiveRecord::RecordNotFound
    redirect_to gig_path(@gig), alert: "Plantilla no encontrada."
  end

  def assign_staff
    @gig = Gig.find(params[:id])
    user = User.find_by(id: params[:staff_id])
    agreed_amount = params[:agreed_amount].to_s.tr(',', '.').to_f

    if user && (user.staff? || user.leader? || user.musician?)
      assignment = @gig.staff_assignments.find_or_initialize_by(user_id: user.id)
      is_new = assignment.new_record?
      assignment.agreed_amount = agreed_amount
      assignment.save!

      notice_msg = is_new ? "Trabajador #{user.display_name} asignado con éxito con pago acordado de $#{view_context.number_with_precision(agreed_amount, precision: 2)}." : "Pago acordado para #{user.display_name} actualizado."
      redirect_to gig_path(@gig), notice: notice_msg
    else
      redirect_to gig_path(@gig), alert: "Usuario no válido."
    end
  end

  def remove_staff
    @gig = Gig.find(params[:id])
    user = User.find_by(id: params[:staff_id])
    assignment = @gig.staff_assignments.find_by(user_id: user&.id)

    if assignment
      assignment.destroy
      redirect_to gig_path(@gig), notice: "Trabajador desasignado del show."
    else
      redirect_to gig_path(@gig), alert: "Asignación no encontrada."
    end
  end

  def update_staff_pay
    @gig = Gig.find(params[:id])
    assignment = @gig.staff_assignments.find_by(id: params[:staff_assignment_id])
    agreed_amount = params[:agreed_amount].to_s.tr(',', '.').to_f

    if assignment
      assignment.update!(agreed_amount: agreed_amount)
      redirect_to gig_path(@gig), notice: "Pago acordado para #{assignment.user.display_name} actualizado a $#{view_context.number_with_precision(agreed_amount, precision: 2)}."
    else
      redirect_to gig_path(@gig), alert: "Asignación no encontrada."
    end
  end

  # Show gigs assigned to current staff member
  def my
    @gigs = current_user.assigned_gigs.order(date: :asc)

    gig_ids = @gigs.pluck(:id)
    @pending_gig_items = GigItem.where(gig_id: gig_ids).where(loaded_quantity: 0)
    @items_to_load_count = @pending_gig_items.sum(:quantity)
  end

  def print_contract
    @gig = Gig.find(params[:id])
    render layout: false
  end

  def add_upsell
    @gig = Gig.find(params[:id])
    upsell_key = params[:upsell_key].to_s

    custom_map = @gig.custom_upsells || {}
    custom_data = custom_map[upsell_key] || {}
    std_upsell = StandardUpsell.find_by(key: upsell_key)

    title = params[:title].presence || custom_data['title'].presence || std_upsell&.title || upsell_key.humanize
    
    if params[:price].present?
      price = params[:price].to_s.tr(',', '.').to_f
    elsif custom_data['price'].present?
      price = custom_data['price'].to_f
    else
      price = std_upsell&.price.to_f
    end

    hours_to_add = (params[:hours].presence || 1).to_i

    extended_time_msg = ""
    is_extra_time = upsell_key == 'extra_time' || upsell_key.include?('time') || upsell_key.include?('hora') || title.downcase.include?('hora')

    if is_extra_time && @gig.end_time.present?
      @gig.end_time = @gig.end_time + hours_to_add.hours
      extended_time_msg = " y se sumó #{hours_to_add} hora(s) al horario del evento"
    end

    @gig.amount = @gig.amount.to_f + price

    timestamp = Time.current.strftime("%d/%m/%Y %I:%M %p")
    price_formatted = helpers.number_with_precision(price, precision: 2)
    note = "Adicional añadido (#{timestamp}): #{title} (+$#{price_formatted} #{@gig.currency || 'USD'})"
    @gig.details = @gig.details.present? ? "#{@gig.details}\n• #{note}" : "• #{note}"

    if @gig.save
      redirect_to gig_path(@gig), notice: "Adicional '#{title}' añadido con éxito (+ $#{price_formatted} #{@gig.currency || 'USD'})#{extended_time_msg}."
    else
      redirect_to gig_path(@gig), alert: "No se pudo añadir el adicional: #{@gig.errors.full_messages.join(', ')}"
    end
  end

  def new
    @gig = Gig.new
  end

  def create
    @gig = Gig.new(gig_params)
    if @gig.save
      @gig.client.update_priority! 
      redirect_to gigs_path, notice: "Toque registrado y prioridad actualizada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @gig = current_company.gigs.find(params[:id])
  end

  def update
    @gig = current_company.gigs.find(params[:id])
    if @gig.update(gig_params)
      @gig.client.update_priority! if @gig.client
      redirect_to gig_path(@gig), notice: "Evento actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @gig = current_company.gigs.find(params[:id])
    @client = @gig.client
    
    if @gig.destroy
      @client.update_priority! if @client
      redirect_to gigs_path, notice: "Registro eliminado y prioridad actualizada."
    else
      redirect_to gigs_path, alert: "No se pudo eliminar el registro."
    end
  end


  private

  def gig_params
    params.require(:gig).permit(:client_id, :client_email, :amount, :date, :location, :currency, :details, :start_time, :end_time).tap do |whitelisted|
      if params[:gig].has_key?(:custom_upsells)
        whitelisted[:custom_upsells] = params[:gig][:custom_upsells].presence&.to_unsafe_h || {}
      end
    end
  end
end