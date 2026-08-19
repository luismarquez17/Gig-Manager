class PortalsController < ApplicationController
  skip_before_action :authenticate_user!
  layout 'portal'

  before_action :set_gig

  def show
    @client = @gig.client
    @gig_payments = @gig.gig_payments.order(date_paid: :desc)
    @timeline_items = @gig.gig_timeline_items.for_client.order(:position, :time)
    @staff_members = @gig.staff_members.with_attached_avatar
    
    # Canciones disponibles de la agrupación / empresa
    @available_songs = @gig.company ? @gig.company.songs.active.order(:genre, :title) : Song.none
    @genres = @available_songs.map(&:genre).uniq

    # Preferencias musicales seleccionadas
    @music_preferences = @gig.music_preferences || {}
    @must_play_ids = @gig.must_play_ids.map(&:to_i)
    @do_not_play_ids = @gig.do_not_play_ids.map(&:to_i)
    @special_moments = @gig.special_moments
    @custom_requests = @gig.custom_song_requests

    # Muro de recuerdos y reseñas
    @gig_reviews = @gig.gig_reviews.approved.pinned_first
  end

  def worker_profile
    @worker = User.find(params[:worker_id])
    unless @gig.staff_members.include?(@worker)
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
      return
    end
  end

  def sign_contract
    if params[:signature_name].blank?
      render json: { success: false, error: "El nombre es obligatorio para firmar." }, status: :unprocessable_entity
      return
    end

    if @gig.update(
      contract_signed: true,
      contract_signed_at: Time.current,
      contract_signed_ip: request.remote_ip,
      contract_signed_name: params[:signature_name]
    )
      render json: { 
        success: true, 
        signed_at: @gig.contract_signed_at.strftime("%d/%m/%Y %I:%M %p"),
        ip: @gig.contract_signed_ip,
        name: @gig.contract_signed_name
      }
    else
      render json: { success: false, error: "No se pudo registrar la firma." }, status: :unprocessable_entity
    end
  end

  def update_music_preferences
    prefs = @gig.music_preferences || {}

    if params[:must_play].present?
      prefs['must_play'] = Array(params[:must_play]).map(&:to_i).uniq
    end

    if params[:do_not_play].present?
      prefs['do_not_play'] = Array(params[:do_not_play]).map(&:to_i).uniq
    end

    if params[:special_moments].present?
      prefs['special_moments'] = params[:special_moments].permit!.to_h rescue params[:special_moments]
    end

    if params[:custom_requests].present?
      prefs['custom_requests'] = Array(params[:custom_requests]).reject(&:blank?)
    end

    if @gig.update(music_preferences: prefs)
      render json: { 
        success: true, 
        message: "¡Preferencias de repertorio guardadas con éxito!",
        must_play_count: prefs['must_play']&.size || 0,
        do_not_play_count: prefs['do_not_play']&.size || 0
      }
    else
      render json: { success: false, error: "No se pudieron guardar las preferencias." }, status: :unprocessable_entity
    end
  end

  def submit_review
    review = @gig.gig_reviews.build(
      client_name: params[:client_name].presence || @gig.client&.name || "Invitado",
      rating: params[:rating].to_i.clamp(1, 5),
      comment: params[:comment],
      is_client: params[:is_client] == 'true' || params[:is_client] == true,
      approved: true
    )

    if params[:photo].present?
      review.photos.attach(params[:photo])
    end

    if review.save
      render json: {
        success: true,
        message: "¡Gracias por tu reseña y compartir tu experiencia!",
        review: {
          id: review.id,
          name: review.client_name,
          rating: review.rating,
          comment: review.comment,
          stars: review.stars_display,
          date: review.created_at.strftime("%d/%m/%Y")
        }
      }
    else
      render json: { success: false, error: review.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  private

  def set_gig
    @gig = Gig.find_by(portal_token: params[:token])
    if @gig.nil?
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
    end
  end
end
