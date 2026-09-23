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
  has_many :notification_reads, dependent: :destroy
  has_many :sent_notifications, class_name: 'AppNotification', foreign_key: 'sender_id', dependent: :nullify

  def app_notifications
    return AppNotification.none unless company_id.present?
    AppNotification.where(company_id: company_id).for_role(role).recent_first
  end

  def unread_notifications_count
    return 0 unless company_id.present?
    app_notifications.unread_by(self).count
  end

  after_create :associate_and_claim_gigs
  after_save :associate_and_claim_gigs, if: -> { client_id.blank? && company_id.present? }

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

  def phone_number
    client&.phone.presence || company&.whatsapp_number.presence || company&.contact_phone.presence
  end

  def formatted_phone_for_whatsapp
    raw_phone = phone_number
    return nil if raw_phone.blank?

    digits = raw_phone.to_s.gsub(/\D/, '')
    if digits.start_with?('0') && digits.length == 11
      "58#{digits[1..]}"
    elsif digits.length == 10 && digits.start_with?('4')
      "58#{digits}"
    else
      digits
    end
  end

  def whatsapp_url(text: nil)
    number = formatted_phone_for_whatsapp
    return nil if number.blank?

    url = "https://wa.me/#{number}"
    url += "?text=#{ERB::Util.url_encode(text)}" if text.present?
    url
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
    assignments = staff_assignments.includes(gig: :client)
    assigned_gig_ids = assignments.map(&:gig_id)

    # Pre-agregación en solo 2 queries SQL para eliminar N+1
    paid_by_gig = employee_payments.approved.where(gig_id: assigned_gig_ids).group(:gig_id).sum(:amount)
    pending_by_gig = employee_payments.pending_approval.where(gig_id: assigned_gig_ids).group(:gig_id).sum(:amount)

    # 1. Shows asignados vía StaffAssignment
    assignments.each do |sa|
      paid = paid_by_gig[sa.gig_id].to_f
      pending_approval = pending_by_gig[sa.gig_id].to_f
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

    if client_id.blank?
      # 1. Buscar un Client existente por email dentro de la MISMA empresa
      existing_client = Client.where(company_id: company_id).where.not(email: [nil, '']).find_by(email: email) if email.present?

      # 2. Buscar por coincidencia exacta de Nombre (solo si no está ya reclamado por otro usuario registrado)
      if existing_client.nil? && (name.present? || display_name.present?)
        target_name = (name.presence || display_name).downcase.strip
        name_candidates = Client.where(company_id: company_id).where("LOWER(TRIM(name)) = ?", target_name)
        
        # Excluir clientes que ya están vinculados a OTRA cuenta de usuario distinta
        unclaimed = name_candidates.reject do |c|
          User.where(company_id: company_id, client_id: c.id).where.not(id: id).exists?
        end

        # Elegir aquel cuyo correo esté en blanco o coincida con el del usuario
        existing_client = unclaimed.find { |c| c.email.blank? || (email.present? && c.email.downcase == email.downcase) }
      end

      # 3. Buscar a través de cotizaciones (ClientQuote) con el mismo email
      if existing_client.nil? && email.present?
        quote_match = ClientQuote.where(company_id: company_id, client_email: email)
                                 .where.not(client_id: nil)
                                 .first
        if quote_match&.client
          is_claimed = User.where(company_id: company_id, client_id: quote_match.client_id).where.not(id: id).exists?
          existing_client = quote_match.client unless is_claimed
        end
      end

      # 4. Buscar a través de gigs de la misma empresa con el mismo email
      if existing_client.nil? && email.present?
        gig_with_client = Gig.where(company_id: company_id, client_email: email).where.not(client_id: nil).first
        if gig_with_client&.client
          is_claimed = User.where(company_id: company_id, client_id: gig_with_client.client_id).where.not(id: id).exists?
          existing_client = gig_with_client.client unless is_claimed
        end
      end

      if existing_client
        # Vinculamos al cliente existente y actualizamos su email o nombre si estaban vacíos
        updates = {}
        updates[:email] = email if existing_client.email.blank? && email.present?
        updates[:name] = name if existing_client.name.blank? && name.present?
        existing_client.update(updates) if updates.any?
        
        self.update_column(:client_id, existing_client.id) unless client_id == existing_client.id
      else
        # Último recurso: crear un nuevo Client para esta empresa
        new_client = Client.create!(
          email: email,
          name: display_name,
          phone: "0000000000",
          company_id: company_id
        )
        self.update_column(:client_id, new_client.id)
      end
    end

    # 5. Reclamar los Gigs y Presupuestos con este correo dentro de la misma empresa
    claim_gigs
  end

  def claim_gigs
    return unless company_id.present? && client_id.present?
    Gig.where(company_id: company_id, client_email: email).update_all(client_id: client_id)
    ClientQuote.where(company_id: company_id, client_email: email).update_all(client_id: client_id)
  end

  def self.find_or_create_client_user(company:, client:, email: nil, name: nil)
    return nil if company.nil? || client.nil?

    # Buscar usuario existente vinculado a este cliente o a su email
    user = User.where(company_id: company.id, client_id: client.id).first
    user ||= User.where(company_id: company.id, email: client.email).first if client.email.present?

    if user.nil?
      user_email = client.email.presence || email.presence || "cliente_#{client.id}@#{company.slug.presence || 'app'}.com"
      user_name = client.name.presence || name.presence || "Cliente"

      user = User.find_by(email: user_email)
      if user.nil?
        random_pass = SecureRandom.hex(14)
        user = User.new(
          name: user_name,
          email: user_email,
          company: company,
          client: client,
          role: :client,
          password: random_pass,
          password_confirmation: random_pass
        )
        user.save!
      else
        user.update_column(:client_id, client.id) if user.client_id != client.id
      end
    else
      user.update_column(:client_id, client.id) if user.client_id != client.id
    end

    user
  rescue StandardError => e
    Rails.logger.error("Error en User.find_or_create_client_user: #{e.class}: #{e.message}")
    nil
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

