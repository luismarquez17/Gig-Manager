module GigsHelper
  SPANISH_DAYS = %w[Domingo Lunes Martes Miércoles Jueves Viernes Sábado].freeze
  SPANISH_MONTHS = %w[Enero Febrero Marzo Abril Mayo Junio Julio Agosto Septiembre Octubre Noviembre Diciembre].freeze

  def spanish_long_date(date)
    return "Fecha por definir" unless date.present?

    wday = SPANISH_DAYS[date.wday]
    day = date.day
    month = SPANISH_MONTHS[date.month - 1]
    year = date.year

    "#{wday}, #{day} de #{month} #{year}"
  end

  def spanish_short_date(date)
    return "---" unless date.present?

    wday = SPANISH_DAYS[date.wday][0..2]
    day = date.day
    month = SPANISH_MONTHS[date.month - 1][0..2].upcase
    year = date.year

    "#{wday} #{day} #{month} #{year}"
  end

  def gig_arrival_time(gig)
    return "Por confirmar" unless gig.present?

    # 1. Buscar si hay algún hito en el cronograma con palabras clave
    items = gig.gig_timeline_items
    call_item = items.find { |i| i.title.to_s.downcase.match?(/llegada|montaje|convocatoria|soundcheck|prueba/i) }
    return call_item.time if call_item.present? && call_item.time.present?

    # 2. Si hay hitos en el cronograma, tomar el primero
    first_item = items.order(position: :asc, time: :asc).first
    return first_item.time if first_item.present? && first_item.time.present?

    # 3. Si tiene hora de inicio, estimar 1 hora y media antes para llegada/soundcheck
    if gig.start_time.present?
      estimated = gig.start_time - 90.minutes
      return estimated.strftime("%I:%M %p")
    end

    "Por confirmar"
  end

  def gig_dress_code_hint(gig)
    return nil unless gig.present? && gig.details.present?

    details = gig.details.to_s
    if details.match?(/negro|black|total black/i)
      "Total Black (Todo Negro)"
    elsif details.match?(/formal|traje|etiqueta/i)
      "Traje Formal"
    elsif details.match?(/casual|semiformal/i)
      "Casual Elegante"
    elsif details.match?(/blanco|white/i)
      "Blanco / Claro"
    else
      nil
    end
  end

  def clean_gig_musician_notes(gig)
    return nil unless gig.present? && gig.details.present?

    # Filtramos líneas que contengan información de precios, cobros, presupuestos o "Adicional añadido"
    filtered_lines = gig.details.to_s.lines.map(&:strip).reject do |line|
      line.blank? ||
      line.match?(/adicional a[ñn]adido|adicional|\+\s*\$|\bUSD\b|\bBS\b|\bprecio\b|\bcobrad[oa]\b|\banticipo\b|\bpago\b|\bpresupuesto\b/i)
    end

    return nil if filtered_lines.empty?

    filtered_lines.join(" · ")
  end

  def whatsapp_url_for_message(phone = nil, text = "")
    encoded = ERB::Util.url_encode(text.to_s)
    clean_phone = phone.to_s.gsub(/[^0-9]/, '')
    if clean_phone.present?
      "https://wa.me/#{clean_phone}?text=#{encoded}"
    else
      "https://web.whatsapp.com/send?text=#{encoded}"
    end
  end

  def profit_health_badge_tag(gig)
    status = gig.profit_health_status
    margin = gig.projected_profit_margin

    case status
    when :excellent
      content_tag(:span, "💎 #{margin}% Margen VIP", style: "background: #dcfce7; color: #15803d; border: 1px solid #86efac; padding: 3px 9px; border-radius: 99px; font-weight: 800; font-size: 0.78em; display: inline-flex; align-items: center; gap: 4px;")
    when :healthy
      content_tag(:span, "✨ #{margin}% Margen Óptimo", style: "background: #f0fdf4; color: #166534; border: 1px solid #bbf7d0; padding: 3px 9px; border-radius: 99px; font-weight: 800; font-size: 0.78em; display: inline-flex; align-items: center; gap: 4px;")
    when :tight
      content_tag(:span, "⚠️ #{margin}% Margen Ajustado", style: "background: #fefce8; color: #854d0e; border: 1px solid #fef08a; padding: 3px 9px; border-radius: 99px; font-weight: 800; font-size: 0.78em; display: inline-flex; align-items: center; gap: 4px;")
    else
      content_tag(:span, "🚨 #{margin}% En Déficit", style: "background: #fef2f2; color: #991b1b; border: 1px solid #fecaca; padding: 3px 9px; border-radius: 99px; font-weight: 800; font-size: 0.78em; display: inline-flex; align-items: center; gap: 4px;")
    end
  end

  def time_until_gig_in_words(gig)
    return "" unless gig.date.present?
    today = Date.today
    days = (gig.date - today).to_i

    if days == 0
      "🔥 ¡HOY ES EL DÍA DEL SHOW!"
    elsif days == 1
      "⏳ Mañana es el evento"
    elsif days > 1
      "⏳ Faltan #{days} días"
    elsif days == -1
      "✅ Evento realizado ayer"
    else
      "✅ Evento pasado hace #{days.abs} días"
    end
  end
end
