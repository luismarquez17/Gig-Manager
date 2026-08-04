module Superadmin
  class CompaniesController < BaseController
    before_action :set_company, only: [:show, :edit, :update, :destroy, :toggle_status, :regenerate_token]

    def index
      @companies = Company.order(created_at: :desc)
    end

    def show
      @users = @company.users.order(role: :asc, created_at: :desc)
      @gigs = @company.gigs.order(date: :desc).limit(10)
    end

    def new
      @company = Company.new(monthly_fee: 50.0, currency: "USD", status: :active)
    end

    def create
      @company = Company.new(company_params)

      ActiveRecord::Base.transaction do
        if @company.save
          # If leader details are provided, create the leader user directly
          if params[:leader_email].present? && params[:leader_password].present?
            leader_user = @company.users.create!(
              email: params[:leader_email],
              password: params[:leader_password],
              name: params[:leader_name].presence || "Jefe #{@company.name}",
              role: :leader
            )
          end

          redirect_to superadmin_company_path(@company), notice: "🎉 Empresa '#{@company.name}' creada exitosamente."
        else
          render :new, status: :unprocessable_entity
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = "Error al crear la empresa/jefe: #{e.message}"
      render :new, status: :unprocessable_entity
    end

    def edit
    end

    def update
      if @company.update(company_params)
        redirect_to superadmin_company_path(@company), notice: "✅ Empresa '#{@company.name}' actualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      name = @company.name
      @company.destroy
      redirect_to superadmin_companies_path, notice: "🗑️ Empresa '#{name}' eliminada del universo."
    end

    def toggle_status
      new_status = @company.active? ? :suspended : :active
      @company.update!(status: new_status)
      redirect_to superadmin_company_path(@company), notice: "Estado de la empresa actualizado a '#{new_status.capitalize}'."
    end

    def regenerate_token
      @company.regenerate_token!
      redirect_to superadmin_company_path(@company), notice: "🔑 Enlace de invitación/registro actualizado."
    end

    def switch_tenant
      if params[:id] == "all" || params[:id].blank?
        session.delete(:superadmin_company_id)
        redirect_to superadmin_dashboard_path, notice: "Visión global restaurada (Modo Universo Superadmin)."
      else
        target = Company.find(params[:id])
        if target.leaders.any? && target.id != current_user.company_id
          redirect_to superadmin_company_path(target), alert: "🔒 Privacidad Protegida: Esta empresa ya tiene un jefe asignado. Por privacidad de sus clientes, datos e inventario, no es posible acceder a su entorno interno."
          return
        end
        session[:superadmin_company_id] = target.id
        redirect_to root_path, notice: "👁️ Vista conmutada a la empresa inicial: '#{target.name}'."
      end
    end


    private

    def set_company
      @company = Company.find(params[:id])
    end

    def company_params
      params.require(:company).permit(:name, :slug, :status, :monthly_fee, :currency, :billing_day, :contact_email, :contact_phone, :notes)
    end
  end
end
