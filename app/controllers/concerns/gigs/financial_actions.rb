# frozen_string_literal: true

module Gigs
  module FinancialActions
    extend ActiveSupport::Concern

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

    def add_upsell
      operation = params[:operation].presence || 'add'
      upsell_key = params[:upsell_key].to_s

      custom_map = @gig.custom_upsells || {}
      custom_data = custom_map[upsell_key] || {}
      std_upsell = current_company.standard_upsells.find_by(key: upsell_key)

      title = params[:title].presence || custom_data['title'].presence || std_upsell&.title || upsell_key.humanize
      
      if params[:price].present?
        price = params[:price].to_s.tr(',', '.').to_f.abs
      elsif custom_data['price'].present?
        price = custom_data['price'].to_f.abs
      else
        price = std_upsell&.price.to_f.abs
      end

      hours_input = params[:hours].presence
      hours_count = hours_input ? hours_input.to_i : (upsell_key == 'extra_time' ? 1 : 0)

      extended_time_msg = ""
      is_extra_time = upsell_key == 'extra_time' || upsell_key.include?('time') || upsell_key.include?('hora') || title.downcase.include?('hora')

      timestamp = Time.current.strftime("%d/%m/%Y %I:%M %p")
      price_formatted = helpers.number_with_precision(price, precision: 2)

      if operation == 'subtract'
        if is_extra_time && @gig.end_time.present? && hours_count > 0
          @gig.end_time = @gig.end_time - hours_count.hours
          extended_time_msg = " y se restó #{hours_count} hora(s) al horario del evento"
        end

        @gig.amount = [@gig.amount.to_f - price, 0.0].max
        note = "Deducción / Descuento registrado (#{timestamp}): #{title} (-$#{price_formatted} #{@gig.currency || 'USD'})"
        @gig.details = @gig.details.present? ? "#{@gig.details}\n• #{note}" : "• #{note}"

        if @gig.save
          redirect_to gig_path(@gig), notice: "Deducción de $#{price_formatted} #{@gig.currency || 'USD'} aplicada al presupuesto#{extended_time_msg}."
        else
          redirect_to gig_path(@gig), alert: "No se pudo aplicar la deducción: #{@gig.errors.full_messages.join(', ')}"
        end
      else
        if is_extra_time && @gig.end_time.present? && hours_count > 0
          @gig.end_time = @gig.end_time + hours_count.hours
          extended_time_msg = " y se sumó #{hours_count} hora(s) al horario del evento"
        end

        @gig.amount = @gig.amount.to_f + price
        note = "Adicional añadido (#{timestamp}): #{title} (+$#{price_formatted} #{@gig.currency || 'USD'})"
        @gig.details = @gig.details.present? ? "#{@gig.details}\n• #{note}" : "• #{note}"

        # Creamos el registro de GigUpsellRequest para que pueda ser cancelado/eliminado en 1 clic
        emoji = custom_data['emoji'].presence || std_upsell&.emoji || (is_extra_time ? '⏰' : '✨')
        key = upsell_key.presence || "manual_#{Time.current.to_i}"

        @gig.gig_upsell_requests.build(
          company: current_company,
          upsell_key: key,
          title: title,
          emoji: emoji,
          price: price,
          currency: @gig.currency.presence || 'USD',
          status: 'approved',
          hours_added: (is_extra_time ? hours_count : 0),
          notes: (hours_count > 0 ? "+#{hours_count} hora(s)" : nil),
          requested_at: Time.current,
          processed_at: Time.current
        )

        if @gig.save
          redirect_to gig_path(@gig), notice: "Adicional '#{title}' añadido con éxito (+ $#{price_formatted} #{@gig.currency || 'USD'})#{extended_time_msg}."
        else
          redirect_to gig_path(@gig), alert: "No se pudo añadir el adicional: #{@gig.errors.full_messages.join(', ')}"
        end
      end
    end

    def adjust_price
      new_amount_raw = params[:new_amount].to_s.tr(',', '.').strip
      if new_amount_raw.blank?
        redirect_to gig_path(@gig), alert: "Debes ingresar un monto válido."
        return
      end

      new_amount = new_amount_raw.to_f
      if new_amount < 0
        redirect_to gig_path(@gig), alert: "El monto no puede ser negativo."
        return
      end

      reason = params[:reason].to_s.strip
      adjust_hours = params[:adjust_hours].to_i
      old_amount = @gig.amount.to_f

      @gig.amount = new_amount

      time_msg = ""
      if adjust_hours != 0 && @gig.end_time.present?
        @gig.end_time = @gig.end_time + adjust_hours.hours
        time_msg = " y se #{adjust_hours > 0 ? 'sumó' : 'restó'} #{adjust_hours.abs} hora(s) al horario final"
      end

      timestamp = Time.current.strftime("%d/%m/%Y %I:%M %p")
      diff = new_amount - old_amount
      diff_sign = diff >= 0 ? "+$" : "-$"
      diff_str = "#{diff_sign}#{helpers.number_with_precision(diff.abs, precision: 2)}"
      reason_str = reason.present? ? " (Motivo: #{reason})" : ""

      note = "Ajuste de precio general (#{timestamp}): De $#{helpers.number_with_precision(old_amount, precision: 2)} a $#{helpers.number_with_precision(new_amount, precision: 2)} #{@gig.currency || 'USD'} [#{diff_str}]#{reason_str}"
      @gig.details = @gig.details.present? ? "#{@gig.details}\n• #{note}" : "• #{note}"

      if @gig.save
        redirect_to gig_path(@gig), notice: "✅ Presupuesto general actualizado a $#{helpers.number_with_precision(new_amount, precision: 2)} #{@gig.currency || 'USD'}#{time_msg}."
      else
        redirect_to gig_path(@gig), alert: "No se pudo actualizar el precio: #{@gig.errors.full_messages.join(', ')}"
      end
    end

    def save_profit_to_goal
      goal_id = params[:reinvestment_goal_id].presence
      amount = params[:amount].to_s.tr(',', '.').strip.to_f
      notes = params[:notes].presence || "Aporte de ganancia libre del evento #{@gig.client_display_name}"

      if goal_id.blank?
        redirect_to gig_path(@gig), alert: "Debes seleccionar una meta de ahorro."
        return
      end

      if amount <= 0
        redirect_to gig_path(@gig), alert: "El monto a ahorrar debe ser mayor a 0."
        return
      end

      goal = current_company.reinvestment_goals.find(goal_id)
      contribution = goal.goal_savings_contributions.create!(
        amount: amount,
        currency: @gig.currency.presence || 'USD',
        date: Date.today,
        user: current_user,
        gig: @gig,
        notes: notes
      )

      formatted = helpers.number_with_precision(amount, precision: 2)
      redirect_to gig_path(@gig), notice: "🎉 ¡Se han guardado $#{formatted} USD de ganancia neta en la meta '#{goal.title}'! Tu progreso avanzó al #{goal.progress_percentage}%."
    rescue ActiveRecord::RecordNotFound
      redirect_to gig_path(@gig), alert: "Meta de ahorro no encontrada."
    rescue StandardError => e
      redirect_to gig_path(@gig), alert: "No se pudo registrar el ahorro: #{e.message}"
    end
  end
end
