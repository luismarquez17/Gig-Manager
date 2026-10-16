# frozen_string_literal: true

class ReassignVenuePresetsFromMarquezMusica < ActiveRecord::Migration[7.1]
  def up
    marquez = Company.find_by(slug: 'marquez-musica') ||
              Company.where("LOWER(name) LIKE ?", "%marquez%").first

    venue_titles = [
      "Combo 15 Años & Bodas Glamour",
      "Combo Cumpleaños & Fiestas Privadas",
      "Combo Desfile & Pasarela (Academia de Modelaje)",
      "Combo Graduaciones & Eventos Corporativos",
      "Mensualidad / Talleres de Modelaje e Imagen"
    ]

    # Clean up Marquez Musica from any leaked venue combos and upsells
    if marquez.present?
      PresetBudget.where(company_id: marquez.id, title: venue_titles).delete_all
      StandardUpsell.where(company_id: marquez.id).where("key LIKE ? OR key LIKE ?", "gero%", "jero%").delete_all
    end

    # Ensure venue companies have their combos and upsells properly seeded under their own tenant
    Company.where(business_type: 'venue_academy').or(Company.where("LOWER(name) LIKE ?", "%gero%")).find_each do |vc|
      next if marquez.present? && vc.id == marquez.id
      vc.seed_venue_combos! rescue nil
      vc.seed_venue_upsells! rescue nil
    end
  end

  def down
    # reversible no-op
  end
end
