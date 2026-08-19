class CreateCompanyMediaItemsAndAddLandingFieldsToCompanies < ActiveRecord::Migration[7.1]
  def change
    # Campos de personalización de la Landing en Company
    add_column :companies, :tagline, :string
    add_column :companies, :bio, :text
    add_column :companies, :whatsapp_number, :string
    add_column :companies, :instagram_url, :string
    add_column :companies, :youtube_url, :string
    add_column :companies, :tiktok_url, :string

    # Tabla para galería multimedia administrable por cada Agrupación
    create_table :company_media_items do |t|
      t.references :company, null: false, foreign_key: true
      t.string :title, null: false
      t.string :category, default: "live_show", null: false # live_show, instruments, effects, backstage
      t.string :media_type, default: "video", null: false # video, photo, youtube
      t.string :video_url
      t.text :description
      t.integer :position, default: 0
      t.boolean :featured, default: false
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :company_media_items, [:company_id, :position]
    add_index :company_media_items, [:company_id, :category]
  end
end
