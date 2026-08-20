class AddCalculatorCustomizationAndUpsellsLandingFlags < ActiveRecord::Migration[7.1]
  def change
    # Campos para decidir qué upsells mostrar en la Landing
    add_column :standard_upsells, :show_on_landing, :boolean, default: true, null: false
    add_column :standard_upsells, :landing_position, :integer, default: 0

    # Campos de personalización total de la Calculadora / Simulador en Vivo
    add_column :companies, :landing_calculator_title, :string, default: "Simula tu Presupuesto al Instante"
    add_column :companies, :landing_calculator_subtitle, :string, default: "Juega con las opciones y calcula el valor estimado de tu evento en tiempo real."
    add_column :companies, :landing_calculator_base_hours, :integer, default: 2
    add_column :companies, :landing_calculator_extra_hour_price, :decimal, precision: 10, scale: 2, default: 100.0
    add_column :companies, :landing_calculator_currency, :string, default: "USD"
    add_column :companies, :landing_calculator_formats, :jsonb, default: [
      { "key" => "acoustic", "name" => "Acústico", "musicians" => "Dúo / Trío", "price" => 400, "emoji" => "🎻" },
      { "key" => "full_band", "name" => "Banda Completa", "musicians" => "5 Músicos", "price" => 750, "emoji" => "🎸" },
      { "key" => "big_band", "name" => "Big Band", "musicians" => "Metales & Show (8+ Músicos)", "price" => 1200, "emoji" => "🎺" }
    ]
  end
end
