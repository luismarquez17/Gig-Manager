class Item < ApplicationRecord
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

  # LISTA MAESTRA DE CATEGORÍAS
  CATEGORIES = ["Cornetas", "Cables", "Estructuras", "Pantallas", "Consolas", "Microfonos", "Luces", "Bajos", "Accesorios"]

  # LISTA MAESTRA DE SUB-CABLES
  CABLE_TYPES = ["Micrófono (XLR)", "RCA", "HDMI", "Plug (3.5mm)", "Plug (6.3mm)", "USB C", ]

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