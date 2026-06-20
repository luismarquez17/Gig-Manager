class GigItem < ApplicationRecord
  belongs_to :gig
  belongs_to :item

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :loaded_quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :returned_quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :loaded_quantity_cannot_exceed_requested
  validate :returned_quantity_cannot_exceed_loaded

  def discrepancy?
    loaded_quantity != returned_quantity
  end

  def returned_all?
    loaded_quantity > 0 && loaded_quantity == returned_quantity
  end

  private

  def loaded_quantity_cannot_exceed_requested
    if loaded_quantity.present? && quantity.present? && loaded_quantity > quantity
      errors.add(:loaded_quantity, "no puede ser mayor que la cantidad solicitada (#{quantity})")
    end
  end

  def returned_quantity_cannot_exceed_loaded
    if returned_quantity.present? && loaded_quantity.present? && returned_quantity > loaded_quantity
      errors.add(:returned_quantity, "no puede ser mayor que la cantidad cargada (#{loaded_quantity})")
    end
  end
end
