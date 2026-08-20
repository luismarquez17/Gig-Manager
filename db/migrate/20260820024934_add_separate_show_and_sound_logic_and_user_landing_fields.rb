class AddSeparateShowAndSoundLogicAndUserLandingFields < ActiveRecord::Migration[7.1]
  def change
    # Campos para controlar qué músicos/trabajadores se muestran en la Landing
    add_column :users, :show_on_landing, :boolean, default: true, null: false
    add_column :users, :landing_position, :integer, default: 0

    # Campos de lógica separada: Shows/Pases en Vivo vs Horas de Sonido/DJ
    add_column :companies, :landing_calculator_base_shows, :integer, default: 1
    add_column :companies, :landing_calculator_extra_show_price, :decimal, precision: 10, scale: 2, default: 250.0
    add_column :companies, :landing_calculator_base_sound_hours, :integer, default: 4
    add_column :companies, :landing_calculator_extra_sound_hour_price, :decimal, precision: 10, scale: 2, default: 60.0
  end
end
