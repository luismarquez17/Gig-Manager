class AddLandingTemplatePricesAndSetBaseSoundHoursTo6 < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :landing_template_prices, :jsonb, default: {
      "classic_stage" => 0,
      "neon_festival" => 15,
      "royal_gala" => 29,
      "minimal_acoustic" => 19
    }
    change_column_default :companies, :landing_calculator_base_sound_hours, from: 4, to: 6
  end
end
