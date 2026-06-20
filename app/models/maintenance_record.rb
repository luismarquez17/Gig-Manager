class MaintenanceRecord < ApplicationRecord
  belongs_to :item
  belongs_to :gig, optional: true

  enum status: { pending: 0, in_repair: 1, fixed: 2, discarded: 3 }

  validates :description, presence: true
  validates :cost, presence: true, numericality: { greater_than_or_equal_to: 0 }

  after_save :update_item_status_and_quantity

  private

  def update_item_status_and_quantity
    # Si pasa a descartado (y ha cambiado el estado), restamos 1 del inventario maestro
    if saved_change_to_status? && status == 'discarded'
      item.update!(quantity: [item.quantity - 1, 0].max)
    end

    # Determinamos si el equipo tiene reparaciones activas pendientes
    has_active_repairs = item.maintenance_records.where(status: [:pending, :in_repair]).any?

    if has_active_repairs
      item.update!(status: 'Dañado')
    else
      # Si ya no tiene reparaciones pendientes y el ítem estaba dañado, vuelve a Excelente
      if item.status == 'Dañado'
        item.update!(status: 'Excelente')
      end
    end
  end
end
