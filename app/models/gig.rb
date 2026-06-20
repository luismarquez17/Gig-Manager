class Gig < ApplicationRecord
  belongs_to :client
  has_many :gig_items, dependent: :destroy
  has_many :items, through: :gig_items
  validates :amount, presence: true

  # Se ejecuta al crear, editar o borrar un show
  after_save :refresh_client_priority
  after_destroy :refresh_client_priority

  private

  def refresh_client_priority
    # Usamos &. para evitar errores si por alguna razón el cliente es nil
    client&.update_priority!
  end
end