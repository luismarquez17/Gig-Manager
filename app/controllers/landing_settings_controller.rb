class LandingSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_leader_or_admin!
  before_action :set_company

  def show
    @media_items = @company.company_media_items.ordered
    @new_media_item = @company.company_media_items.build
  end

  def update
    # Procesar configuración de secciones
    if params[:company][:landing_sections_config].present?
      sections_data = {}
      %w[show_metrics show_packages show_calculator show_media show_team show_reviews show_faq].each do |sec|
        sections_data[sec] = params[:company][:landing_sections_config][sec] == "1" || params[:company][:landing_sections_config][sec] == true
      end
      @company.landing_sections_config = sections_data
    end

    # Procesar FAQs si se enviaron
    if params[:company][:landing_faqs].present?
      faqs_array = []
      params[:company][:landing_faqs].each do |_idx, item|
        if item[:q].present? && item[:a].present?
          faqs_array << { "q" => item[:q].to_s.strip, "a" => item[:a].to_s.strip }
        end
      end
      @company.landing_faqs = faqs_array if faqs_array.any?
    end

    if @company.update(company_landing_params)
      redirect_to landing_settings_path, notice: "¡Configuración y diseño de tu Landing Page guardados con éxito!"
    else
      @media_items = @company.company_media_items.ordered
      @new_media_item = @company.company_media_items.build
      render :show, status: :unprocessable_entity
    end
  end

  def create_media
    @media_item = @company.company_media_items.build(media_item_params)
    @media_item.active = true if @media_item.active.nil?
    
    if @media_item.save
      redirect_to landing_settings_path, notice: "¡Material multimedia publicado en tu Landing con éxito!"
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
    redirect_to landing_settings_path, notice: "Visibilidad del video '#{@media_item.title}' actualizada: #{@media_item.active? ? 'Visible' : 'Oculto'}."
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
      :landing_enabled,
      :landing_plan,
      :landing_theme_color,
      :landing_accent_color,
      :landing_bg_style,
      :landing_hero_title,
      :landing_hero_subtitle,
      :landing_hero_cta_text,
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
