class InventoryItem < ApplicationRecord
  belongs_to :item, touch: true
  has_many :maintenance_records, dependent: :nullify

  enum :status, {
    available: 'available',
    damaged: 'damaged',
    maintenance: 'maintenance'
  }, default: :available

  validates :status, presence: true

  after_save :sync_parent_status
  after_destroy :sync_parent_status

  private

  def sync_parent_status
    item.sync_status_from_inventory!
  end
end
