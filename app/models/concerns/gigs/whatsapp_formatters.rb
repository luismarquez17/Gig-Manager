# frozen_string_literal: true

module Gigs
  module WhatsappFormatters
    extend ActiveSupport::Concern

    def whatsapp_payment_statement_text(portal_url = nil)
      status_text = if paid_in_full?
                      "✅ SALDADO EN SU TOTALIDAD"
                    elsif total_received.positive?
                      "⏳ ABONADO PARCIALMENTE (#{payment_percentage}%)"
                    else
                      "⚠️ PENDIENTE POR ABONAR"
                    end

      comp_name = company&.name.presence || "Gig Manager"
      c_name = client_display_name.to_s.encode('UTF-8', invalid: :replace, undef: :replace)
      loc = (location.presence || 'Por definir').to_s.encode('UTF-8', invalid: :replace, undef: :replace)
      dt = date ? date.strftime('%d/%m/%Y') : 'Por definir'

      lines = [
        "📋 *ESTADO DE CUENTA - #{comp_name.to_s.upcase}*",
        "─────────────────────────",
        "👤 *Cliente:* #{c_name}",
        "📅 *Fecha:* #{dt}",
        "📍 *Ubicación:* #{loc}",
        "─────────────────────────",
        "💰 *Total Acordado:* $#{sprintf('%.2f', amount.to_f)} #{currency || 'USD'}",
        "💵 *Total Abonado:* $#{sprintf('%.2f', total_received)} #{currency || 'USD'}",
        "💳 *Saldo Pendiente:* $#{sprintf('%.2f', remaining_amount)} #{currency || 'USD'}",
        "📊 *Estado:* #{status_text}",
        "─────────────────────────"
      ]

      payments = gig_payments.order(date_paid: :asc)
      if payments.any?
        lines << "🧾 *Abonos Registrados:*"
        payments.each_with_index do |p, i|
          p_date = p.date_paid ? p.date_paid.strftime('%d/%m/%Y') : '---'
          p_cat = (p.category.presence || 'Abono').to_s.encode('UTF-8', invalid: :replace, undef: :replace)
          lines << "  • #{p_date} - $#{sprintf('%.2f', p.amount.to_f)} #{p.currency} (#{p_cat})"
        end
        lines << "─────────────────────────"
      end

      if portal_url.present?
        lines << "🔗 *Portal Privado y Recibos Digitales:*"
        lines << portal_url.to_s
      end

      lines.map { |l| l.encode('UTF-8', invalid: :replace, undef: :replace) }.join("\n")
    end

    def whatsapp_client_welcome_text(portal_url = nil)
      comp_name = company&.name.presence || "Gig Manager"
      c_name = client_display_name
      dt = date ? date.strftime('%d/%m/%Y') : 'Por definir'
      loc = location.presence || 'Por definir'
      time_str = formatted_time_range.presence || 'Horario por coordinar'

      lines = [
        "✨ *¡Hola #{c_name}! Te saluda el equipo de #{comp_name}* ✨",
        "",
        "¡Estamos muy felices de acompañarte en tu próximo evento! 🎉",
        "Hemos preparado tu *Portal Privado de Cliente* donde podrás consultar todos los detalles en tiempo real:",
        "",
        "📅 *Fecha:* #{dt}",
        "🕐 *Horario Acordado:* #{time_str}",
        "📍 *Lugar:* #{loc}",
        ""
      ]

      if portal_url.present?
        lines << "🔗 *Accede a tu Portal Exclusivo aquí:*"
        lines << portal_url.to_s
        lines << ""
        features_desc = []
        features_desc << "el cronograma del día" if company.nil? || company.module_enabled?(:gigs)
        features_desc << "validar tus abonos y recibos" if company.nil? || company.module_enabled?(:finances)
        features_desc << "solicitar adicionales" if company.nil? || company.module_enabled?(:clients_crm)
        if features_desc.any?
          lines << "Desde allí podrás revisar #{features_desc.to_sentence} para tu evento."
        end
      end

      lines << ""
      lines << "Cualquier consulta estamos a tu total disposición. ¡Será un evento inolvidable! 🙌"
      lines.join("\n")
    end

    def whatsapp_client_schedule_text(portal_url = nil)
      comp_name = company&.name.presence || "Gig Manager"
      c_name = client_display_name
      dt = date ? date.strftime('%d/%m/%Y') : 'Por definir'
      loc = location.presence || 'Por definir'

      lines = [
        "⏰ *CRONOGRAMA Y PAUTA TÉCNICA - #{comp_name.to_s.upcase}*",
        "─────────────────────────",
        "👤 *Cliente:* #{c_name}",
        "📅 *Fecha:* #{dt}",
        "📍 *Lugar:* #{loc}",
        "─────────────────────────"
      ]

      timeline_items = gig_timeline_items.order(position: :asc, time: :asc)
      if timeline_items.any?
        lines << "⏱️ *Itinerario del Evento:*"
        timeline_items.each do |item|
          t_str = item.time.presence || "--:--"
          lines << "  • *#{t_str}* - #{item.title}"
          lines << "    _#{item.description}_" if item.description.present?
        end
        lines << "─────────────────────────"
      end

      if portal_url.present?
        lines << "📱 *Portal en Vivo:* #{portal_url}"
      end

      lines.join("\n")
    end

    def whatsapp_staff_call_sheet_text(staff_user = nil, stage_url = nil)
      comp_name = company&.name.presence || "Gig Manager"
      dt = date ? date.strftime('%d/%m/%Y') : 'Por definir'
      loc = location.presence || 'Por definir'
      c_name = client_display_name
      is_venue = company&.business_type == 'venue_hall'

      assignment = staff_assignments.find_by(user_id: staff_user&.id) if staff_user.present?

      sheet_title = is_venue ? "🏛️ *PAUTA DE PERSONAL - #{comp_name.to_s.upcase}*" : "🎸 *PAUTA DE CONVOCATORIA (CALL SHEET) - #{comp_name.to_s.upcase}*"

      lines = [
        sheet_title,
        "─────────────────────────",
        "📅 *Fecha:* #{dt}",
        "👤 *Evento:* #{c_name}",
        "📍 *Ubicación:* #{loc}",
        "─────────────────────────"
      ]

      if start_time.present?
        arr_time = (start_time - 90.minutes).strftime("%I:%M %p")
        lines << "🚪 *Convocatoria / Montaje:* #{arr_time}"
        lines << "🎤 *Inicio:* #{start_time.strftime('%I:%M %p')}"
        lines << "🏁 *Finalización:* #{end_time ? end_time.strftime('%I:%M %p') : 'Por definir'}"
      else
        lines << "🕐 *Horario:* Por coordinar en el grupo"
      end

      # Dress code si existe en notas
      if details.to_s.match?(/negro|black/i)
        lines << "👔 *Código de Vestimenta:* Total Black (Todo Negro)"
      elsif details.to_s.match?(/formal|traje|etiqueta/i)
        lines << "👔 *Código de Vestimenta:* Traje Formal"
      elsif details.to_s.match?(/casual|semiformal/i)
        lines << "👔 *Código de Vestimenta:* Casual Elegante"
      elsif details.to_s.match?(/blanco|white/i)
        lines << "👔 *Código de Vestimenta:* Blanco / Claro"
      end

      if assignment.present? && assignment.agreed_amount.to_f > 0
        lines << "💰 *Pago Acordado:* $#{sprintf('%.2f', assignment.agreed_amount.to_f)} #{currency || 'USD'}"
      end

      if (company.nil? || company.module_enabled?(:songs_repertoire)) && has_music_notes?
        lines << "─────────────────────────"
        lines << "🎵 *Protocolo / Momentos Clave:*"
        lines << music_notes.to_s.lines.first(3).map { |l| "  • #{l.strip}" }.join("\n")
      end

      if stage_url.present?
        lines << "─────────────────────────"
        lines << "⚡ *Modo Escenario en Vivo (Cronograma & Detalles):*"
        lines << stage_url.to_s
      end

      lines.join("\n")
    end
  end

  WhatsAppFormatters = WhatsappFormatters
end
