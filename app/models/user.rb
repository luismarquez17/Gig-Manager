class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum role: { client: 0, staff: 1, leader: 2, musician: 3, superadmin: 4 }

  scope :workers, -> { where(role: [:staff, :leader, :musician, :superadmin]) }

  def leader?
    super || superadmin?
  end

  def musician?
    super || superadmin?
  end

  def staff?
    super || superadmin?
  end



  belongs_to :company, optional: true
  belongs_to :client, optional: true

  before_validation :assign_default_company, on: :create

  has_one_attached :avatar

  has_many :staff_assignments, dependent: :destroy
  has_many :assigned_gigs, through: :staff_assignments, source: :gig
  has_many :employee_payments, dependent: :nullify

  after_create :associate_and_claim_gigs

  def avatar_attached?
    avatar_base64.present? || avatar.attached?
  end

  def avatar_url_or_data
    if avatar_base64.present?
      avatar_base64
    elsif avatar.attached?
      avatar
    else
      nil
    end
  end

  def display_name
    name.presence || email.split('@').first.capitalize
  end

  def total_agreed_amount
    assignment_total = staff_assignments.sum(:agreed_amount).to_f
    assigned_gig_ids = staff_assignments.pluck(:gig_id)

    unassigned_payments_total = if assigned_gig_ids.empty?
      employee_payments.approved.sum(:expected_amount).to_f
    else
      employee_payments.approved.where("gig_id IS NULL OR gig_id NOT IN (?)", assigned_gig_ids).sum(:expected_amount).to_f
    end

    assignment_total + unassigned_payments_total
  end

  def total_paid_amount
    employee_payments.approved.sum(:amount).to_f
  end

  def total_pending_approval_amount
    employee_payments.pending_approval.sum(:amount).to_f
  end

  def pending_balance
    total_agreed_amount - total_paid_amount
  end

  def worker_payment_items
    items = []
    assigned_gig_ids = staff_assignments.pluck(:gig_id)

    # 1. Shows asignados vía StaffAssignment
    staff_assignments.includes(gig: :client).each do |sa|
      paid = employee_payments.approved.where(gig_id: sa.gig_id).sum(:amount).to_f
      pending_approval = employee_payments.pending_approval.where(gig_id: sa.gig_id).sum(:amount).to_f
      expected = sa.agreed_amount.to_f
      items << {
        gig: sa.gig,
        title: sa.gig&.client&.name || "Show del #{sa.gig&.date}",
        date: sa.gig&.date,
        expected_amount: expected,
        paid_amount: paid,
        pending_approval_amount: pending_approval,
        pending_amount: expected - paid,
        type: :assignment,
        assignment: sa
      }
    end

    # 2. Pagos independientes (sin gig asignado)
    standalone_payments = if assigned_gig_ids.empty?
      employee_payments.includes(:gig)
    else
      employee_payments.includes(:gig).where("gig_id IS NULL OR gig_id NOT IN (?)", assigned_gig_ids)
    end

    standalone_payments.group_by(&:gig_id).each do |_gig_id, payments|
      gig = payments.first.gig
      paid = payments.select(&:approved?).sum { |p| p.amount.to_f }
      pending_approval = payments.select(&:pending_approval?).sum { |p| p.amount.to_f }
      expected = payments.map { |p| p.expected_amount.to_f }.max || paid
      items << {
        gig: gig,
        title: gig ? (gig.client&.name || "Show del #{gig.date}") : "Pago Directo",
        date: gig&.date || payments.first.date_paid || payments.first.created_at.to_date,
        expected_amount: expected,
        paid_amount: paid,
        pending_approval_amount: pending_approval,
        pending_amount: expected - paid,
        type: :payment,
        payments: payments
      }
    end

    items.sort_by { |i| i[:date] || Date.today }.reverse
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
        phone: "0000000000", # Teléfono por defecto para pasar la validación
        company_id: company_id
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

  private

  def assign_default_company
    return if superadmin? || company_id.present?

    self.company_id = Current.company&.id || Company.first&.id
  end
end

