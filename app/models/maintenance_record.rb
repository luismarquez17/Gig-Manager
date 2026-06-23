class MaintenanceRecord < ApplicationRecord
  belongs_to :item
  belongs_to :gig, optional: true
  belongs_to :inventory_item, optional: true

  enum status: { pending: 0, in_repair: 1, fixed: 2, discarded: 3 }

  validates :description, presence: true
  validates :cost, presence: true, numericality: { greater_than_or_equal_to: 0 }

  after_save :update_item_status_and_quantity

  # Intenta cargar el costo de la reparación desde el fondo de 'repairs'
  # Si allow_cross_fund es true, puede usar fondos de otros tipos en orden de prioridad
  def charge_from_funds!(allow_cross_fund: false, fallback_order: %w[savings capital other])
    amount = cost.to_f
    created = []

    ActiveRecord::Base.transaction do
      types = ['repairs'] + (allow_cross_fund ? fallback_order : [])
      types.each do |ft|
        break if amount <= 0
        allocs = FundAllocation.where(fund_type: ft).order(:created_at).lock
        allocs.each do |alloc|
          break if amount <= 0
          avail = alloc.remaining
          next if avail <= 0
          take = [avail, amount].min
          exp = alloc.fund_expenses.create!(amount: take, currency: alloc.currency, notes: "Reparación ##{id}", maintenance_record: self)
          created << exp
          amount -= take
        end
      end

      if amount > 0
        raise ActiveRecord::Rollback, "Fondos insuficientes: faltan #{amount}" 
      end
    end

    { success: (amount <= 0), expenses: created }
  end

  private

  def update_item_status_and_quantity
    if saved_change_to_status? || previously_new_record?
      case status
      when 'discarded'
        target_ii = inventory_item || item.inventory_items.first
        if target_ii
          target_ii.destroy
          item.update!(quantity: [item.quantity - 1, 0].max)
        end
      when 'fixed'
        if inventory_item
          inventory_item.update!(status: :available)
        end
      when 'pending', 'in_repair'
        unless inventory_item
          # Buscamos un inventory_item disponible para asociar
          ii = item.inventory_items.where(status: :available).first || item.inventory_items.first
          if ii
            update_column(:inventory_item_id, ii.id)
            ii.update!(status: :maintenance)
          end
        end
      end
    end

    # Sincronizamos el estado de Item basándonos en sus InventoryItems
    item.sync_status_from_inventory!
  end
end
