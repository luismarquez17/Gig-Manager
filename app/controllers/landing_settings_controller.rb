class LandingSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_leader_or_admin!
  before_action :set_company

  def show
    @media_items = @company.company_media_items.ordered
    @new_media_item = @company.company_media_items.build
  end

  def update
    if @company.update(company_landing_params)
      redirect_to landing_settings_path, notice: "¡Identidad y enlaces de la Landing Page actualizados con éxito!"
    else
      @media_items = @company.company_media_items.ordered
      @new_media_item = @company.company_media_items.build
      render :show, status: :unprocessable_entity
    end
  end

  def create_media
    @media_item = @company.company_media_items.build(media_item_params)
    
    if @media_item.save
      redirect_to landing_settings_path, notice: "¡Material multimedia agregado a tu Landing con éxito!"
    else
      @media_items = @company.company_media_items.ordered
      @new_media_item = @media_item
      flash.now[:alert] = "Error al agregar multimedia: #{@media_item.errors.full_messages.join(', ')}"
      render :show, status: :unprocessable_entity
    end
  end

  def destroy_media
    @media_item = @company.company_media_items.find(params[:media_id])
    @media_item.destroy
    redirect_to landing_settings_path, notice: "Material eliminado de la Landing."
  end

  def toggle_media_active
    @media_item = @company.company_media_items.find(params[:media_id])
    @media_item.update(active: !@media_item.active)
    redirect_to landing_settings_path, notice: "Estado del material actualizado."
  end

  private

  def set_company
    @company = current_company
    unless @company
      redirect_to root_path, alert: "No se encontró la empresa actual."
    end
  end

  def ensure_leader_or_admin!
    unless current_user.leader? || current_user.superadmin?
      redirect_to root_path, alert: "Acceso reservado para administradores o líderes."
    end
  end

  def company_landing_params
    params.require(:company).permit(
      :tagline,
      :bio,
      :whatsapp_number,
      :instagram_url,
      :youtube_url,
      :tiktok_url,
      :landing_logo,
      :landing_hero_video
    )
  end

  def media_item_params
    params.require(:company_media_item).permit(
      :title,
      :category,
      :media_type,
      :video_url,
      :description,
      :media_file,
      :thumbnail,
      :featured,
      :active
    )
  end
end
