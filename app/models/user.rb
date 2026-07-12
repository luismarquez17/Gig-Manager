class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum role: { client: 0, staff: 1, leader: 2, musician: 3 }

  scope :workers, -> { where(role: [:staff, :leader, :musician]) }

  belongs_to :client, optional: true

  has_one_attached :avatar

  has_many :staff_assignments, dependent: :destroy
  has_many :assigned_gigs, through: :staff_assignments, source: :gig
  has_many :employee_payments, dependent: :nullify

  after_create :associate_and_claim_gigs

  def display_name
    name.presence || email.split('@').first.capitalize
  end

  def associate_and_claim_gigs
    # 1. Buscar un Client existente por email (match directo)
    existing_client = Client.find_by(email: email)

    # 2. Si no hay match por email en Client, buscar a través de gigs existentes
    #    que usen este correo y que ya estén asociados a un cliente
    if existing_client.nil?
      gig_with_client = Gig.where(client_email: email).where.not(client_id: nil).first
      existing_client = gig_with_client&.client
    end

    if existing_client
      # Vinculamos al cliente existente y actualizamos su email si no lo tenía
      existing_client.update(email: email) if existing_client.email.blank?
      self.update(client_id: existing_client.id) unless client_id == existing_client.id
    else
      # Último recurso: crear un nuevo Client
      new_client = Client.create!(
        email: email,
        name: email.split('@').first.capitalize,
        phone: "0000000000" # Teléfono por defecto para pasar la validación
      )
      self.update(client_id: new_client.id)
    end

    # 3. Reclamar los Gigs con este correo
    claim_gigs
  end

  def claim_gigs
    if client_id.present?
      Gig.where(client_email: email).update_all(client_id: client_id)
    end
  end
end
