# frozen_string_literal: true

class GoalSavingsContribution < ApplicationRecord
  include TenantScoped

  belongs_to :reinvestment_goal
  belongs_to :gig, optional: true
  belongs_to :user, optional: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validates :currency, inclusion: { in: %w[USD] }

  before_validation { self.currency = 'USD' if currency.blank? }
  before_validation { self.date ||= Date.today }

  after_save :update_goal_saved_amount!
  after_destroy :update_goal_saved_amount!

  scope :recent_first, -> { order(date: :desc, created_at: :desc) }

  def source_label
    if gig.present?
      "Show: #{gig.client_display_name} (#{gig.date&.strftime('%d/%m/%Y') || 'Sin fecha'})"
    else
      "Aporte Directo de Caja / Ahorro"
    end
  end

  private

  def update_goal_saved_amount!
    return unless reinvestment_goal.present?
    total = reinvestment_goal.goal_savings_contributions.sum(:amount).to_f.round(2)
    reinvestment_goal.update_columns(saved_amount: total)
    reinvestment_goal.check_auto_completion!
  end
end
