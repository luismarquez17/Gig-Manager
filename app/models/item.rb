class Item < ApplicationRecord
  include TenantScoped

  has_many :gig_items, dependent: :destroy
  has_many :gigs, through: :gig_items
  has_many :maintenance_records, dependent: :destroy
  has_many :inventory_items, dependent: :destroy

  after_save :sync_inventory_items_quantity

  def available_count
    inventory_items.loaded? ? inventory_items.select(&:available?).size : inventory_items.where(status: 'available').count
  end

  def damaged_count
    inventory_items.loaded? ? inventory_items.select(&:damaged?).size : inventory_items.where(status: 'damaged').count
  end

  def maintenance_count
    inventory_items.loaded? ? inventory_items.select(&:maintenance?).size : inventory_items.where(status: 'maintenance').count
  end

  def total_count
    inventory_items.loaded? ? inventory_items.size : inventory_items.count
  end

  def active_maintenance?
    maintenance_records.where(status: [:pending, :in_repair]).any?
  end

  def repair_history
    maintenance_records.order(created_at: :desc)
  end

  # LISTA MAESTRA DE CATEGORÍAS BASE (inmutables)
  CATEGORIES = ["Cornetas", "Cables", "Estructuras", "Pantallas", "Consolas", "Microfonos", "Luces", "Bajos", "Accesorios"]

  # Retorna todas las categorías: las base + las creadas por el usuario
  def self.categories
    (CATEGORIES + Category.pluck(:name)).uniq
  end

  # LISTA MAESTRA DE SUB-CABLES Y LUCES BASE
  CABLE_TYPES = ["Micrófono (XLR)", "RCA", "HDMI", "Plug (3.5mm)", "Plug (6.3mm)", "USB C"]
  LIGHT_TYPES = ["Cabezal Móvil", "Par Led", "Estrobo", "Láser", "Máquina de Humo"]

  # Retorna todos los tipos de cable: base + custom (SubCategory + items guardados)
  def self.cable_types
    sub_categories_for("Cables")
  end

  # Retorna todos los tipos de luces: base + custom
  def self.light_types
    sub_categories_for("Luces")
  end

  def self.sub_categories_for(category_name)
    return [] if category_name.blank?

    base = case category_name
           when "Cables" then CABLE_TYPES
           when "Luces" then LIGHT_TYPES
           else []
           end
    custom_subcats = SubCategory.where(category: category_name).pluck(:name)
    item_subcats = Item.where(category: category_name).pluck(:sub_category)
    (base + custom_subcats + item_subcats).compact.reject(&:blank?).uniq.sort
  end

  def self.sub_categories_grouped
    categories.each_with_object({}) do |cat, hash|
      hash[cat] = sub_categories_for(cat)
    end
  end

  # Verifica que los términos aquí coincidan EXACTAMENTE con los del formulario
  validates :status, presence: true, inclusion: { in: ["Excelente", "Operativo", "Dañado"] }
  validates :name, presence: true

  def sync_status_from_inventory!
    total_copies = inventory_items.count
    damaged_copies = inventory_items.damaged.count
    maintenance_copies = inventory_items.maintenance.count

    new_status = if total_copies > 0 && damaged_copies == total_copies
                   "Dañado"
                 elsif damaged_copies > 0 || maintenance_copies > 0
                   "Operativo"
                 else
                   "Excelente"
                 end
    update_column(:status, new_status)
  end

  private

  def sync_inventory_items_quantity
    current_count = inventory_items.count
    target_count = quantity || 0

    if target_count > current_count
      (target_count - current_count).times do
        inventory_items.create!(status: :available)
      end
    elsif target_count < current_count
      # Destruimos los disponibles primero
      availables = inventory_items.where(status: :available).limit(current_count - target_count)
      availables.destroy_all

      # Si todavía necesitamos destruir más (porque no había suficientes disponibles),
      # destruimos de los otros estados
      remaining_to_destroy = target_count - inventory_items.count
      if remaining_to_destroy < 0
        inventory_items.limit(remaining_to_destroy.abs).destroy_all
      end
    end

    sync_status_from_inventory!
  end
end