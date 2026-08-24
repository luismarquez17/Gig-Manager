class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum role: { client: 0, staff: 1, leader: 2, musician: 3, superadmin: 4 }

  scope :workers, -> {
    tenant = ::ActsAsTenant.current_tenant || Current.company
    base_scope = where(role: [:staff, :leader, :musician, :superadmin])
    tenant.present? ? base_scope.where(company_id: tenant.id) : base_scope
  }

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
    return unless company_id.present?

    # 1. Buscar un Client existente por email dentro de la MISMA empresa (match directo)
    existing_client = Client.where(company_id: company_id).find_by(email: email)

    # 2. Si no hay match por email en Client, buscar a través de gigs de la misma empresa
    if existing_client.nil?
      gig_with_client = Gig.where(company_id: company_id, client_email: email).where.not(client_id: nil).first
      existing_client = gig_with_client&.client
    end

    if existing_client
      # Vinculamos al cliente existente y actualizamos su email si no lo tenía
      existing_client.update(email: email) if existing_client.email.blank?
      self.update_column(:client_id, existing_client.id) unless client_id == existing_client.id
    else
      # Último recurso: crear un nuevo Client para esta empresa
      new_client = Client.create!(
        email: email,
        name: display_name,
        phone: "0000000000", # Teléfono por defecto para pasar la validación
        company_id: company_id
      )
      self.update_column(:client_id, new_client.id)
    end

    # 3. Reclamar los Gigs con este correo dentro de la misma empresa
    claim_gigs
  end

  def claim_gigs
    return unless company_id.present? && client_id.present?
    Gig.where(company_id: company_id, client_email: email).update_all(client_id: client_id)
  end

  private

  def assign_default_company
    return if superadmin? || company_id.present?

    # Garantiza aislamiento total: Si un usuario se registra de forma independiente,
    # se le crea su propia empresa única con 30 días de prueba gratuita y se le asigna como Líder.
    user_name = name.presence || email.split('@').first.capitalize
    new_company = Company.create!(
      name: "Agrupación #{user_name}",
      monthly_fee: 0.0,
      status: :active,
      trial_started_at: Time.current,
      trial_ends_at: 30.days.from_now,
      subscription_status: 'trialing',
      plan_tier: 'starter'
    )
    self.company_id = new_company.id
    self.role = :leader if role.blank? || client?
  end
end

