module Superadmin
  class DashboardController < BaseController
    def index
      @companies_count = Company.count
      @active_companies_count = Company.active.count
      @total_mrr = Company.active.sum(:monthly_fee).to_f
      @past_due_count = Company.past_due.count
      @suspended_count = Company.suspended.count

      @total_universe_gigs = Gig.count
      @total_universe_users = User.where.not(role: :superadmin).count
      @total_universe_clients = Client.count

      @companies = Company.order(created_at: :desc)
    end
  end
end
