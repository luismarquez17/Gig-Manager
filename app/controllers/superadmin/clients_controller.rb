module Superadmin
  class ClientsController < BaseController
    def index
      # Métricas globales del universo
      @total_clients = Client.count
      @clients_with_user = Client.with_user_account.distinct.count
      @clients_without_user = [@total_clients - @clients_with_user, 0].max
      @clients_active = Client.with_gigs.count
      @adoption_rate = @total_clients.positive? ? ((@clients_with_user.to_f / @total_clients) * 100).round(1) : 0.0

      # Empresas para el selector de filtro
      @companies = Company.order(:name)

      # Consulta filtrable de clientes
      scope = Client.includes(:company, :client_user, :gigs)

      if params[:company_id].present?
        scope = scope.where(company_id: params[:company_id])
      end

      case params[:status]
      when 'with_user'
        scope = scope.with_user_account
      when 'without_user'
        scope = scope.without_user_account
      when 'with_gigs'
        scope = scope.with_gigs
      end

      if params[:query].present?
        terms = params[:query].to_s.strip.split(/\s+/)
        terms.each do |term|
          next if term.blank?
          query_term = "%#{term}%"
          scope = scope.where("unaccent(clients.name) ILIKE unaccent(?) OR clients.email ILIKE ? OR clients.phone ILIKE ?", query_term, query_term, query_term)
        end
      end

      @clients = scope.order(created_at: :desc)
    end
  end
end
