class GigsController < ApplicationController
  before_action :require_leader!, except: [:show, :load_in_checklist, :my, :flashcard, :stage_mode]
  before_action -> { require_module!(:gigs) }
  before_action -> { require_module!(:inventory) }, only: [:load_in_checklist, :add_kit]
  before_action :require_staff_or_leader!, only: [:show, :load_in_checklist, :print_contract, :flashcard, :stage_mode]
  before_action :check_gig_assignment, only: [:show, :load_in_checklist, :flashcard, :stage_mode]
  before_action :set_gig, only: [:add_kit, :assign_staff, :remove_staff, :update_staff_pay, :print_contract, :flashcard, :stage_mode, :add_upsell, :edit, :update, :destroy, :closeout, :process_closeout]

  def check_gig_assignment
    @gig = current_company.gigs.find_by!(id: params[:id])
    # Usamos exists? para verificar la asignación directamente en SQL sin cargar
    # todos los gigs asignados en memoria.
    unless current_user.superadmin? || current_user.leader? ||
           current_user.staff_assignments.exists?(gig_id: @gig.id)
      redirect_to root_path, alert: "No tienes asignado este evento."
    end
  end

  def index
    # 1. Unimos la tabla de clientes para poder buscar y filtrar dentro de la empresa
    @gigs = current_company.gigs.left_joins(:client).includes(:client, :gig_payments, :staff_assignments)

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
          "unaccent(COALESCE(gigs.music_notes, '')) ILIKE unaccent(?) OR " \
          "gigs.client_email ILIKE ?",
          query_term, query_term, query_term, query_term, query_term, query_term
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
    @total_usd = GigPayment.where(gig_id: gig_ids).sum(:amount).to_f
  end

  def show
    @gig = current_company.gigs.includes(:client, :gig_payments, :gig_timeline_items, :gig_upsell_requests, :employee_payments, staff_assignments: :user).find(params[:id])
    @gig_items = @gig.gig_items.includes(:item).order('items.name ASC')
    @new_gig_item = GigItem.new
  end

  def load_in_checklist
    @gig ||= current_company.gigs.find(params[:id])
    @gig_items = @gig.gig_items.includes(:item).order('items.name ASC')
    # Use a layout specifically without navbar, or render false and build full html
    render layout: false
  end

  def add_kit
    kit = current_company.kits.find(params[:kit_id])

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
    user = if params[:staff_id].present?
             current_company.users.find_by(id: params[:staff_id])
           elsif params[:new_eventual_worker_name].present?
             User.create_eventual_worker!(
               company: current_company,
               name: params[:new_eventual_worker_name],
               role: params[:new_eventual_worker_role].presence || 'staff',
               phone: params[:new_eventual_worker_phone].presence,
               specialty: params[:new_eventual_worker_specialty].presence
             )
           end

    agreed_amount = params[:agreed_amount].to_s.tr(',', '.').to_f

    if user && (user.staff? || user.leader? || user.musician?)
      assignment = @gig.staff_assignments.find_or_initialize_by(user_id: user.id)
      is_new = assignment.new_record?
      previous_amount = assignment.agreed_amount.to_f
      assignment.agreed_amount = agreed_amount
      assignment.save!

      target_area = user.musician? ? 'musicians' : 'staffs'
      date_formatted = @gig.date ? @gig.date.strftime("%d/%m/%Y") : "próximamente"
      client_name = @gig.client&.name || "Cliente"

      if is_new && !user.eventual?
        # Notificar al músico / staff asignado (únicamente a este usuario)
        AppNotification.create(
          company: @gig.company,
          sender: current_user,
          recipient: user,
          target_area: target_area,
          notification_type: 'gig_alert',
          title: "🎸 Has sido asignado a un evento",
          message: "Fuiste asignado al show de '#{client_name}' para la fecha #{date_formatted} en #{@gig.location.presence || 'Ubicación por confirmar'}.",
          action_url: "/my_gigs"
        ) rescue nil
      end

      if is_new
        # Notificar al área de líderes
        eventual_tag = user.eventual? ? " (Trabajador Eventual)" : ""
        AppNotification.create(
          company: @gig.company,
          sender: current_user,
          target_area: 'leaders',
          notification_type: 'gig_alert',
          title: "👤 Nueva Asignación de Personal",
          message: "#{user.display_name}#{eventual_tag} ha sido asignado(a) al show '#{client_name}' (#{date_formatted}).",
          action_url: "/gigs/#{@gig.id}"
        ) rescue nil
      elsif (agreed_amount - previous_amount).abs > 0.01 && !user.eventual?
        # Notificar al trabajador si se actualizó el pago acordado
        AppNotification.create(
          company: @gig.company,
          sender: current_user,
          recipient: user,
          target_area: target_area,
          notification_type: 'payment_alert',
          title: "💰 Actualización de Pago Acordado",
          message: "Se actualizó tu pago acordado a $#{view_context.number_with_precision(agreed_amount, precision: 2)} en el show de '#{client_name}' (#{date_formatted}).",
          action_url: "/my_payments"
        ) rescue nil
      end

      prefix = user.eventual? ? "⚡ Trabajador eventual " : "Trabajador "
      notice_msg = is_new ? "#{prefix}'#{user.display_name}' asignado con éxito con pago acordado de $#{view_context.number_with_precision(agreed_amount, precision: 2)}." : "Pago acordado para #{user.display_name} actualizado."
      redirect_to gig_path(@gig), notice: notice_msg
    else
      redirect_to gig_path(@gig), alert: "Debes seleccionar o ingresar un trabajador válido."
    end
  end

  def remove_staff
    user = current_company.users.find_by(id: params[:staff_id])
    assignment = @gig.staff_assignments.find_by(user_id: user&.id)

    if assignment
      assignment.destroy
      redirect_to gig_path(@gig), notice: "Trabajador desasignado del show."
    else
      redirect_to gig_path(@gig), alert: "Asignación no encontrada."
    end
  end

  def update_staff_pay
    assignment = @gig.staff_assignments.find_by(id: params[:staff_assignment_id])
    agreed_amount = params[:agreed_amount].to_s.tr(',', '.').to_f

    if assignment
      assignment.update!(agreed_amount: agreed_amount)

      date_formatted = @gig.date ? @gig.date.strftime("%d/%m/%Y") : "próximamente"
      client_name = @gig.client&.name || "Cliente"
      target_area = assignment.user.musician? ? 'musicians' : 'staffs'

      AppNotification.create(
        company: @gig.company,
        sender: current_user,
        recipient: assignment.user,
        target_area: target_area,
        notification_type: 'payment_alert',
        title: "💰 Actualización de Pago Acordado",
        message: "Se actualizó tu pago acordado a $#{view_context.number_with_precision(agreed_amount, precision: 2)} en el show de '#{client_name}' (#{date_formatted}).",
        action_url: "/my_payments"
      ) rescue nil

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
    render layout: false
  end

  def flashcard
    render layout: false
  end

  def stage_mode
    @gig = current_company.gigs.includes(:client, :gig_timeline_items, staff_assignments: :user, gig_items: :item).find(params[:id])
    @timeline_items = @gig.gig_timeline_items.order(position: :asc, time: :asc)
    @staff_assignments = @gig.staff_assignments.includes(:user)
    @gig_items = @gig.gig_items.includes(:item).order('items.name ASC')
    @songs = current_company.songs.where(active: true).order(genre: :asc, title: :asc) rescue []
    render layout: false
  end

  def add_upsell
    upsell_key = params[:upsell_key].to_s

    custom_map = @gig.custom_upsells || {}
    custom_data = custom_map[upsell_key] || {}
    std_upsell = current_company.standard_upsells.find_by(key: upsell_key)

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
    @available_quotes = current_company.client_quotes.convertible.recent_first

    if params[:quote_id].present?
      @quote = current_company.client_quotes.find_by(id: params[:quote_id])
      if @quote.present?
        quote_name = @quote.client_name.to_s.strip
        client = @quote.client

        # Si el cliente asignado no coincide con el nombre especificado en el formulario
        if quote_name.present? && (client.nil? || client.name.to_s.strip.downcase != quote_name.downcase)
          client = Client.find_or_create_for_gig(
            company: current_company,
            email: @quote.client_email,
            name: quote_name,
            phone: @quote.client_phone
          )
          @quote.update_column(:client_id, client.id) if client.present?
        end

        @gig.client = client
        @gig.client_id = client&.id
        @gig.client_email = @quote.client_email.presence || client&.email
        @gig.amount = @quote.amount
        @gig.currency = @quote.currency
        @gig.location = @quote.event_location
        @gig.date = @quote.event_date || Date.today
        @gig.start_time = @quote.start_time
        @gig.end_time = @quote.end_time
        @gig.details = @quote.details
        @selected_quote_id = @quote.id
        @default_advance_amount = @quote.advance_amount
      end
    end
  end

  def create
    @gig = current_company.gigs.build(gig_params)

    name_to_use = params[:client_name].presence || params.dig(:gig, :client_name).presence
    email_to_use = @gig.client_email.presence || params[:client_email].presence
    phone_to_use = params[:client_phone].presence

    if name_to_use.present?
      current_client = current_company.clients.find_by(id: @gig.client_id)
      # Si no hay cliente o el cliente seleccionado no coincide con el nombre ingresado
      if current_client.nil? || current_client.name.to_s.strip.downcase != name_to_use.to_s.strip.downcase
        matched_client = Client.find_or_create_for_gig(
          company: current_company,
          email: email_to_use,
          name: name_to_use,
          phone: phone_to_use
        )
        @gig.client = matched_client if matched_client.present?
        @gig.client_id = matched_client&.id
      end
    elsif @gig.client_id.blank? && email_to_use.present?
      matched_client = Client.find_or_create_for_gig(
        company: current_company,
        email: email_to_use,
        name: nil,
        phone: phone_to_use
      )
      @gig.client = matched_client if matched_client.present?
      @gig.client_id = matched_client&.id
    end

    if @gig.save
      @gig.client&.update_priority!

      advance_val = params[:advance_amount].to_s.tr(',', '.').to_f
      if advance_val > 0
        @gig.gig_payments.create!(
          amount: advance_val,
          currency: @gig.currency.presence || "USD",
          date_paid: params[:advance_date_paid].presence || Date.today,
          is_advance: true,
          payer_name: @gig.client&.name.presence || params[:client_name].presence || "Cliente",
          notes: "Adelanto Inicial (Anticipo) registrado al crear el evento."
        ) rescue nil
      end

      if params[:client_quote_id].present?
        quote = current_company.client_quotes.find_by(id: params[:client_quote_id])
        if quote
          quote.update(status: 'converted', gig_id: @gig.id, client_id: @gig.client_id)
        end
      end

      redirect_to gigs_path, notice: "Toque registrado con éxito."
    else
      @available_quotes = current_company.client_quotes.convertible.recent_first
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @gig.update(gig_params)
      @gig.client&.update_priority! if @gig.client
      respond_to do |format|
        format.html { redirect_to gig_path(@gig), notice: "Evento actualizado correctamente." }
        format.json { render json: { success: true, music_notes: @gig.music_notes } }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @gig.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @client = @gig.client
    
    if @gig.destroy
      @client.update_priority! if @client
      redirect_to gigs_path, notice: "Registro eliminado y prioridad actualizada."
    else
      redirect_to gigs_path, alert: "No se pudo eliminar el registro."
    end
  end
  def closeout
    @remaining_client_balance = @gig.remaining_amount
    @staff_assignments = @gig.staff_assignments.includes(:user)
    @worker_unpaid_items = @staff_assignments.map do |sa|
      {
        assignment: sa,
        user: sa.user,
        agreed: sa.agreed_amount.to_f,
        paid: sa.total_paid.to_f,
        pending: sa.pending_balance.to_f
      }
    end
    @total_pending_payroll = @worker_unpaid_items.sum { |item| item[:pending] }
  end

  def process_closeout
    client_amount = params[:client_collected_amount].to_s.tr(',', '.').strip.to_f
    client_payment_method = params[:client_payment_method].presence || 'cash'
    client_reference = params[:client_reference_number].presence
    client_notes = params[:client_payment_notes].presence || "Liquidación de cierre de evento"

    worker_payments_data = params[:worker_payments] || {}
    fund_allocation_amount = params[:fund_amount].to_s.tr(',', '.').strip.to_f
    fund_notes = params[:fund_notes].presence || "Ingreso de remanente por cierre de evento: #{@gig.client_display_name}"

    ActiveRecord::Base.transaction do
      # 1. Registrar cobro del cliente si se cobró dinero hoy
      if client_amount > 0
        @gig.gig_payments.create!(
          amount: client_amount,
          currency: @gig.currency.presence || 'USD',
          date_paid: Date.today,
          payment_method: client_payment_method,
          reference_number: client_reference,
          notes: client_notes,
          status: 'approved',
          audit_reason: "Cierre de Show: Cobro de $#{client_amount} (#{client_payment_method})"
        )
      end

      # 2. Registrar pagos a trabajadores seleccionados
      worker_payments_data.each do |user_id, w_data|
        next unless w_data[:pay] == '1' || w_data[:pay] == true
        w_amt = w_data[:amount].to_s.tr(',', '.').strip.to_f
        next if w_amt <= 0

        user = current_company.users.find(user_id)
        w_method = w_data[:payment_method].presence || 'Efectivo'
        w_notes = w_data[:notes].presence || "Pago liquidado en tarima / cierre de show"

        current_company.employee_payments.create!(
          user: user,
          gig: @gig,
          amount: w_amt,
          currency: @gig.currency.presence || 'USD',
          date_paid: Date.today,
          payment_method: w_method,
          notes: w_notes,
          funding_source: 'payroll_fund',
          status: 'approved',
          audit_reason: "Cierre de Show: Pago a #{user.display_name} de $#{w_amt} (#{w_method})"
        )
      end

      # 3. Asignar excedente al Fondo de la Empresa / Caja si se especificó
      if fund_allocation_amount > 0 && (params[:deposit_to_fund] == '1' || params[:deposit_to_fund] == true)
        current_company.cash_adjustments.create!(
          user: current_user,
          amount: fund_allocation_amount,
          currency: @gig.currency.presence || 'USD',
          adjustment_type: :deposit,
          date: Date.today,
          description: fund_notes,
          status: 'approved',
          audit_reason: "Cierre de Show: Aporte al fondo de $#{fund_allocation_amount}"
        )
      end
    end

    redirect_to gig_path(@gig), notice: "🏁 Cierre de evento realizado exitosamente. Cobros, nóminas y balances actualizados."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to closeout_gig_path(@gig), alert: "Error al procesar el cierre: #{e.message}"
  rescue StandardError => e
    redirect_to closeout_gig_path(@gig), alert: "Ocurrió un problema: #{e.message}"
  end

  private

  def set_gig
    @gig = current_company.gigs.find(params[:id])
  end

  def gig_params
    params.require(:gig).permit(:client_id, :client_email, :amount, :date, :location, :currency, :details, :music_notes, :start_time, :end_time).tap do |whitelisted|
      if params[:gig].has_key?(:custom_upsells)
        whitelisted[:custom_upsells] = params[:gig][:custom_upsells].presence&.to_unsafe_h || {}
      end
    end
  end
end