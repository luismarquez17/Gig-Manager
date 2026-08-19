class Company < ApplicationRecord
  enum status: { active: 0, suspended: 1, past_due: 2, trial: 3 }

  has_many :users, dependent: :destroy
  has_many :clients, dependent: :destroy
  has_many :gigs, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :kits, dependent: :destroy
  has_many :investments, dependent: :destroy
  has_many :preset_budgets, dependent: :destroy
  has_many :standard_upsells, dependent: :destroy
  has_many :shopping_items, dependent: :destroy
  has_many :finance_settings, dependent: :destroy
  has_many :employee_payments, dependent: :destroy
  has_many :songs, dependent: :destroy
  has_many :gig_reviews, through: :gigs

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :invitation_token, uniqueness: true, allow_nil: true
  validates :monthly_fee, numericality: { greater_than_or_equal_to: 0 }

  before_validation :generate_slug_and_token, on: :create

  def leaders
    users.where(role: [:leader, :superadmin])
  end


  def primary_leader
    leaders.first
  end

  def regenerate_token!
    update!(invitation_token: SecureRandom.hex(12))
  end

  def status_badge_class
    case status.to_sym
    when :active
      "bg-emerald-500/10 text-emerald-400 border-emerald-500/20"
    when :suspended
      "bg-rose-500/10 text-rose-400 border-rose-500/20"
    when :past_due
      "bg-amber-500/10 text-amber-400 border-amber-500/20"
    when :trial
      "bg-blue-500/10 text-blue-400 border-blue-500/20"
    else
      "bg-slate-500/10 text-slate-400 border-slate-500/20"
    end
  end

  def approved_reviews
    gig_reviews.where(gig_reviews: { approved: true })
  end

  def average_rating
    reviews = approved_reviews
    return 5.0 if reviews.empty?
    (reviews.average(:rating) || 5.0).to_f.round(1)
  end

  private

  def generate_slug_and_token
    self.slug ||= name.to_s.parameterize.presence || SecureRandom.hex(4)
    self.invitation_token ||= SecureRandom.hex(12)
  end
end
