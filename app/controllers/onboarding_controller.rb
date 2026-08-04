class OnboardingController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_tenant

  before_action :set_company_from_token

  def show
    if user_signed_in?
      flash[:notice] = "Ya tienes sesión iniciada en #{@company.name}."
      redirect_to root_path and return
    end

    @user = User.new
  end

  def process_join
    if user_signed_in?
      redirect_to root_path and return
    end

    @user = User.new(user_params)
    @user.company = @company

    # If the company has no leader yet, the first user registering via token gets the Leader role!
    if @company.leaders.empty?
      @user.role = :leader
    else
      @user.role ||= :staff
    end

    if @user.save
      sign_in(@user)
      redirect_to root_path, notice: "🎉 ¡Bienvenido a Gig Manager! Te has unido exitosamente a #{@company.name} como #{@user.role.capitalize}."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_company_from_token
    @company = Company.find_by(slug: params[:slug])

    if @company.nil? || (params[:token].present? && @company.invitation_token != params[:token])
      redirect_to root_path, alert: "El enlace de invitación es inválido o ha caducado."
    end
  end

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :specialty)
  end
end
