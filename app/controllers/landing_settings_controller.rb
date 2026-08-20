class LandingSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_leader_or_admin!
  before_action :set_company

  def show
    @media_items = @company.company_media_items.ordered
    @new_media_item = @company.company_media_items.build
    @upsells = @company.standard_upsells.order(landing_position: :asc, created_at: :asc)
    @calculator_formats = @company.effective_calculator_formats
    @staff_members = @company.all_staff_members
  end

  def update
    # 1. Procesar configuración de secciones (checkboxes booleanos)
    if params[:company][:landing_sections_config].present? || params[:company].key?(:landing_sections_config)
      sections_data = {}
      cfg = params[:company][:landing_sections_config] || {}
      %w[show_metrics show_packages show_calculator show_media show_team show_reviews show_faq].each do |sec|
        sections_data[sec] = cfg[sec] == "1" || cfg[sec] == true || cfg[sec] == "true"
      end
      @company.landing_sections_config = sections_data
    end

    # 2. Procesar formatos de la calculadora en vivo
    if params[:company][:landing_calculator_formats].present?
      formats_array = []
      params[:company][:landing_calculator_formats].each do |_idx, fmt|
        if fmt[:name].present? && fmt[:price].present?
          formats_array << {
            "key" => fmt[:key].presence || fmt[:name].to_s.parameterize.underscore,
            "name" => fmt[:name].to_s.strip,
            "musicians" => fmt[:musicians].to_s.strip,
            "price" => fmt[:price].to_f,
            "emoji" => fmt[:emoji].presence || "🎵"
          }
        end
      end
      @company.landing_calculator_formats = formats_array if formats_array.any?
    end

    # 3. Procesar FAQs si se enviaron
    if params[:company][:landing_faqs].present?
      faqs_array = []
      params[:company][:landing_faqs].each do |_idx, item|
        if item[:q].present? && item[:a].present?
          faqs_array << { "q" => item[:q].to_s.strip, "a" => item[:a].to_s.strip }
        end
      end
      @company.landing_faqs = faqs_array if faqs_array.any?
    end

    # 4. Actualización en lote de adicionales/upsells para la landing
    if params[:upsells].present?
      params[:upsells].each do |upsell_id, upsell_params|
        upsell = @company.standard_upsells.find_by(id: upsell_id)
        if upsell
          upsell.update(
            show_on_landing: upsell_params[:show_on_landing] == "1",
            price: upsell_params[:price].presence || upsell.price,
            emoji: upsell_params[:emoji].presence || upsell.emoji,
            title: upsell_params[:title].presence || upsell.title
          )
        end
      end
    end

    # 5. Actualización de Trabajadores / Músicos (Fotos, roles, bio y visibilidad en landing)
    if params[:staff_members].present?
      params[:staff_members].each do |user_id, staff_params|
        user = @company.users.find_by(id: user_id)
        if user
          # Subida de foto de perfil / avatar
          avatar_file = params.dig(:staff_avatars, user_id.to_s)
          if avatar_file.respond_to?(:read)
            content_type = avatar_file.content_type.presence || 'image/jpeg'
            encoded = Base64.strict_encode64(avatar_file.read)
            user.avatar_base64 = "data:#{content_type};base64,#{encoded}"
            user.avatar.attach(avatar_file)
            avatar_file.rewind if avatar_file.respond_to?(:rewind)
          end

          user.update(
            name: staff_params[:name].presence || user.name,
            specialty: staff_params[:specialty].presence || user.specialty,
            bio: staff_params[:bio].presence || user.bio,
            show_on_landing: staff_params[:show_on_landing] == "1"
          )
        end
      end
    end

    # 6. Asignar todos los parámetros de personalización
    @company.assign_attributes(company_landing_params)

    if @company.save
      redirect_to landing_settings_path, notice: "¡Diseño, calculadora separada (shows vs sonido), músicos y adicionales guardados con éxito!"
    else
      @media_items = @company.company_media_items.ordered
      @new_media_item = @company.company_media_items.build
      @upsells = @company.standard_upsells.order(landing_position: :asc, created_at: :asc)
      @calculator_formats = @company.effective_calculator_formats
      @staff_members = @company.all_staff_members
      flash.now[:alert] = "Error al guardar cambios: #{@company.errors.full_messages.join(', ')}"
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
      @upsells = @company.standard_upsells.order(landing_position: :asc, created_at: :asc)
      @calculator_formats = @company.effective_calculator_formats
      @staff_members = @company.all_staff_members
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
    redirect_to landing_settings_path, notice: "Visibilidad de '#{@media_item.title}': #{@media_item.active? ? 'Visible en la Web' : 'Oculto'}."
  end

  def toggle_upsell_landing
    @upsell = @company.standard_upsells.find(params[:upsell_id])
    @upsell.update(show_on_landing: !@upsell.show_on_landing)
    redirect_to landing_settings_path, notice: "Visibilidad del adicional '#{@upsell.title}' en la Landing: #{@upsell.show_on_landing? ? 'Visible' : 'Oculto'}."
  end

  def toggle_staff_landing
    @user = @company.users.find(params[:user_id])
    @user.update(show_on_landing: !@user.show_on_landing)
    redirect_to landing_settings_path(anchor: 'integrantes'), notice: "Visibilidad de #{@user.display_name} en la Landing: #{@user.show_on_landing? ? 'Visible' : 'Oculto'}."
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
      :landing_template,
      :landing_font_family,
      :landing_theme_color,
      :landing_accent_color,
      :landing_gradient_style,
      :landing_bg_style,
      :landing_hero_title,
      :landing_hero_subtitle,
      :landing_hero_cta_text,
      :landing_calculator_title,
      :landing_calculator_subtitle,
      :landing_calculator_base_shows,
      :landing_calculator_extra_show_price,
      :landing_calculator_base_sound_hours,
      :landing_calculator_extra_sound_hour_price,
      :landing_calculator_base_hours,
      :landing_calculator_extra_hour_price,
      :landing_calculator_currency,
      :tagline,
      :bio,
      :whatsapp_number,
      :instagram_url,
      :youtube_url,
      :tiktok_url,
      :landing_logo,
      :landing_hero_video,
      landing_template_prices: {}
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
