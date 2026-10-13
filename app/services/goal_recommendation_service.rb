# frozen_string_literal: true

class GoalRecommendationService
  attr_reader :company, :gig, :goal, :available_cash

  def initialize(company:, gig: nil, goal: nil, custom_cash: nil)
    @company = company
    @gig = gig
    @goal = goal || company.reinvestment_goals.active.by_priority.first
    @custom_cash = custom_cash
    @available_cash = compute_available_cash
  end

  def compute_available_cash
    if @custom_cash.present?
      @custom_cash.to_f
    elsif @gig.present?
      # Si hay gig, tomamos el dinero neto libre no asignado del show
      [@gig.net_free_money_unallocated, 0.0].max
    elsif @goal.present?
      @goal.saved_amount.to_f
    else
      0.0
    end
  end

  # Total pool combinando el show actual + fondo ya ahorrado en la meta
  def total_purchasing_power
    saved = goal ? goal.saved_amount.to_f : 0.0
    gig_cash = gig ? [gig.net_free_money_unallocated, 0.0].max : 0.0
    (saved + gig_cash).round(2)
  end

  def pending_items
    if goal.present?
      goal.shopping_items.pending.order(priority: :desc, created_at: :asc)
    else
      company.shopping_items.pending.order(priority: :desc, created_at: :asc)
    end
  end

  # Ítems que se pueden comprar al 100% con el dinero disponible
  def fully_affordable_items(cash = available_cash)
    pending_items.select do |item|
      cost = item.total_price
      cost > 0 && cost <= cash
    end
  end

  # Desglose de asequibilidad de cada ítem, incluyendo compra parcial de unidades (ej. 2 de 4 luces)
  def items_breakdown(cash = available_cash)
    pending_items.map do |item|
      total_cost = item.total_price
      unit_cost = item.effective_unit_price
      qty = item.quantity.to_i > 0 ? item.quantity.to_i : 1

      can_buy_all = total_cost > 0 && total_cost <= cash
      units_affordable = if unit_cost > 0
                           [(cash / unit_cost).floor, qty].min
                         else
                           0
                         end

      percent_covered = total_cost > 0 ? [(cash / total_cost * 100.0).round(1), 100.0].min : 0.0
      missing_amount = [total_cost - cash, 0.0].max.round(2)

      {
        item: item,
        name: item.name,
        quantity: qty,
        unit_price: unit_cost,
        total_price: total_cost,
        can_buy_all: can_buy_all,
        units_affordable: units_affordable,
        partial_cost: (units_affordable * unit_cost).round(2),
        percent_covered: percent_covered,
        missing_amount: missing_amount,
        image_url: item.image_url_or_data
      }
    end
  end

  # Ítems que faltan para la meta final
  def missing_items_for_goal
    pending_items.map do |item|
      {
        item: item,
        name: item.name,
        quantity: item.quantity,
        unit_price: item.effective_unit_price,
        total_price: item.total_price,
        reason: item.reason,
        purpose: item.purpose,
        image_url: item.image_url_or_data
      }
    end
  end

  def total_deficit_for_goal
    if goal.present?
      goal.pending_amount
    else
      pending_items.sum(&:total_price).round(2)
    end
  end

  # Estimación de toques/shows necesarios para completar la meta
  def estimated_gigs_needed
    deficit = total_deficit_for_goal
    return 0 if deficit <= 0

    # Promedio de ganancia neta por show en los últimos 10 shows de la empresa
    recent_gigs = company.gigs.where("amount > 0").order(date: :desc).limit(10)
    avg_profit = if recent_gigs.any?
                   profits = recent_gigs.map(&:actual_cash_profit).select { |p| p > 0 }
                   profits.any? ? (profits.sum / profits.size.to_f) : 250.0
                 else
                   250.0
                 end

    avg_profit = 100.0 if avg_profit <= 0
    (deficit / avg_profit).ceil
  end

  # Genera sugerencias textuales e inteligentes
  def smart_recommendations
    recommendations = []
    breakdown = items_breakdown(available_cash)

    # 1. Ítems que ya se pueden comprar completos
    affordable_now = breakdown.select { |b| b[:can_buy_all] }
    if affordable_now.any?
      affordable_now.each do |b|
        remainder = (available_cash - b[:total_price]).round(2)
        recommendations << {
          type: :ready_to_buy,
          emoji: '🎉',
          title: "¡Ya te alcanza para comprar #{b[:name]}!",
          message: "Del dinero libre disponible ($#{sprintf('%.2f', available_cash)}), puedes comprar #{b[:quantity] > 1 ? "#{b[:quantity]} unidades de " : ''}#{b[:name]} por $#{sprintf('%.2f', b[:total_price])}. Te quedarían $#{sprintf('%.2f', remainder)} libres.",
          item: b[:item],
          item_id: b[:item].id,
          cost: b[:total_price],
          remainder: remainder
        }
      end
    end

    # 2. Ítems de varias unidades costosas donde alcanza para parte de ellas (ej. 4 luces)
    partial_affordable = breakdown.select { |b| !b[:can_buy_all] && b[:quantity] > 1 && b[:units_affordable] > 0 }
    partial_affordable.each do |b|
      remainder = (available_cash - b[:partial_cost]).round(2)
      recommendations << {
        type: :partial_units,
        emoji: '💡',
        title: "Compra parcial recomendada: #{b[:units_affordable]} de #{b[:quantity]} #{b[:name]}",
        message: "Las #{b[:quantity]} unidades cuestan $#{sprintf('%.2f', b[:total_price])}, pero con tu dinero disponible hoy puedes asegurar ya #{b[:units_affordable]} #{b[:units_affordable] == 1 ? 'unidad' : 'unidades'} por $#{sprintf('%.2f', b[:partial_cost])}. Te faltarían solo #{b[:quantity] - b[:units_affordable]} para completar.",
        item: b[:item],
        item_id: b[:item].id,
        cost: b[:partial_cost],
        remainder: remainder
      }
    end

    # 3. Ítem más cercano si ninguno alcanza completo
    if affordable_now.empty? && partial_affordable.empty? && breakdown.any?
      closest = breakdown.max_by { |b| b[:percent_covered] }
      if closest
        recommendations << {
          type: :close_to_goal,
          emoji: '🎯',
          title: "Estás al #{closest[:percent_covered]}% de conseguir #{closest[:name]}",
          message: "Tienes $#{sprintf('%.2f', available_cash)}. Solo te faltan $#{sprintf('%.2f', closest[:missing_amount])} para comprar #{closest[:name]} ($#{sprintf('%.2f', closest[:total_price])}). ¡Con un pequeño abono o el próximo show lo logras!",
          item: closest[:item],
          item_id: closest[:item].id,
          missing: closest[:missing_amount]
        }
      end
    end

    # 4. Resumen del objetivo final
    if goal.present?
      missing_count = goal.pending_items_count
      deficit = total_deficit_for_goal
      gigs_est = estimated_gigs_needed

      if deficit <= 0 && missing_count.zero?
        recommendations << {
          type: :final_goal_summary,
          emoji: '🎉',
          title: "¡Meta cumplida: #{goal.title}!",
          message: "¡Felicitaciones! Has adquirido todos los equipos y cubierto el 100% del presupuesto de esta meta ($#{sprintf('%.2f', goal.effective_target_amount)} USD).",
          deficit: 0.0,
          gigs_needed: 0
        }
      elsif missing_count.zero? && deficit > 0
        recommendations << {
          type: :final_goal_summary,
          emoji: '🚀',
          title: "Objetivo en Marcha: #{goal.title}",
          message: "Has comprado todos los ítems registrados hasta ahora ($#{sprintf('%.2f', goal.purchased_items_cost)} USD), pero aún restan $#{sprintf('%.2f', deficit)} USD de tu presupuesto meta ($#{sprintf('%.2f', goal.effective_target_amount)} USD). Agrega los demás ítems o sigue ahorrando (~#{gigs_est} #{gigs_est == 1 ? 'show' : 'shows'} estimados).",
          deficit: deficit,
          gigs_needed: gigs_est
        }
      else
        recommendations << {
          type: :final_goal_summary,
          emoji: '🚀',
          title: "Objetivo Final: #{goal.title}",
          message: "Para completar toda la meta te faltan #{missing_count} #{missing_count == 1 ? 'ítem' : 'ítems'} ($#{sprintf('%.2f', deficit)} USD). Estimamos que en aproximadamente #{gigs_est} #{gigs_est == 1 ? 'show' : 'shows'} lo habrás conseguido.",
          deficit: deficit,
          gigs_needed: gigs_est
        }
      end
    end

    recommendations
  end
end
