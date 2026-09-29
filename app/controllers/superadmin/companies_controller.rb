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
      default_pkg = AppModule.package_info('banda')
      @company = Company.new(
        monthly_fee: default_pkg[:price],
        currency: "USD",
        status: :active,
        subscription_status: "active",
        plan_tier: "banda",
        trial_ends_at: 1.month.from_now
      )
      @company.enabled_modules = AppModule.build_modules_hash(default_pkg[:modules])
    end

    def create
      @company = Company.new(company_params)

      if params[:company][:enabled_modules].present?
        modules_hash = {}
        AppModule.keys.each do |k|
          val = params[:company][:enabled_modules][k]
          modules_hash[k] = (val == "1" || val == true || val == "true")
        end
        @company.enabled_modules = modules_hash
      elsif @company.plan_tier.present?
        @company.enabled_modules = AppModule.build_modules_hash(AppModule.modules_for_package(@company.plan_tier))
      end

      if @company.subscription_status == 'active' && @company.trial_ends_at.blank?
        @company.trial_ends_at = 1.month.from_now
      elsif @company.subscription_status == 'trialing' && @company.trial_ends_at.blank?
        @company.trial_ends_at = 30.days.from_now
      end

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

          redirect_to superadmin_company_path(@company), notice: "🎉 Empresa '#{@company.name}' creada exitosamente con Plan #{@company.effective_plan_tier.titleize}."
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
      if params[:company][:enabled_modules].present?
        modules_hash = {}
        AppModule.keys.each do |k|
          modules_hash[k] = (params[:company][:enabled_modules][k] == "1" || params[:company][:enabled_modules][k] == true)
        end
        @company.enabled_modules = modules_hash
      end

      if @company.update(company_params)
        redirect_to superadmin_company_path(@company), notice: "✅ Empresa '#{@company.name}' actualizada correctamente."
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
      params.require(:company).permit(
        :name, :slug, :status, :monthly_fee, :currency, :billing_day,
        :contact_email, :contact_phone, :notes, :subscription_status,
        :plan_tier, :business_type, :trial_started_at, :trial_ends_at
      )
    end
  end
end
