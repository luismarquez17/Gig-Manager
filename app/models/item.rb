class Item < ApplicationRecord
  has_many :gig_items, dependent: :destroy
  has_many :gigs, through: :gig_items
  has_many :maintenance_records, dependent: :destroy

  def active_maintenance?
    maintenance_records.where(status: [:pending, :in_repair]).any?
  end

  def repair_history
    maintenance_records.order(created_at: :desc)
  end

  # LISTA MAESTRA DE CATEGORÍAS
  CATEGORIES = ["Cornetas", "Cables", "Estructuras", "Pantallas", "Consolas", "Microfonos", "Luces", "Accesorios"]

  # LISTA MAESTRA DE SUB-CABLES
  CABLE_TYPES = ["Micrófono (XLR)", "RCA", "HDMI", "Plug (3.5mm)", "Plug (6.3mm)", "USB C", ]

  # Verifica que los términos aquí coincidan EXACTAMENTE con los del formulario
  validates :status, presence: true, inclusion: { in: ["Excelente", "Operativo", "Dañado"] }
  validates :name, presence: true
end