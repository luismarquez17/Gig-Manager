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
      @total_universe_clients_with_user = Client.with_user_account.distinct.count
      @total_universe_clients_without_user = [@total_universe_clients - @total_universe_clients_with_user, 0].max
      @total_universe_active_clients = Client.with_gigs.count
      @universe_adoption_percentage = @total_universe_clients.positive? ? ((@total_universe_clients_with_user.to_f / @total_universe_clients) * 100).round(1) : 0.0

      @companies = Company.order(created_at: :desc)
      @client_counts_by_company = Client.group(:company_id).count
      @client_users_count_by_company = Client.joins("INNER JOIN users ON users.client_id = clients.id AND users.role = #{User.roles[:client]}").group("clients.company_id").count
    end
  end
end
