class SongsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_leader_or_admin!
  before_action :set_song, only: [:destroy]

  def index
    @genres = Song::DEFAULT_GENRES
    @selected_genre = params[:genre]
    @songs = current_company.songs.by_genre(@selected_genre).order(:genre, :title)
    @new_song = Song.new
  end

  def create
    @song = current_company.songs.build(song_params)
    if @song.save
      redirect_to songs_path(genre: @song.genre), notice: "Canción \"#{@song.title}\" agregada al repertorio."
    else
      @genres = Song::DEFAULT_GENRES
      @songs = current_company.songs.order(:genre, :title)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @song.destroy
    redirect_to songs_path(genre: params[:genre]), notice: "Canción eliminada del repertorio."
  end

  def seed_defaults
    current_company.songs.destroy_all if params[:replace] == 'true'

    sample_songs = [
      # Rock / Pop en Español
      { title: "De Música Ligera", artist: "Soda Stereo", genre: "Rock / Pop en Español" },
      { title: "Lamento Boliviano", artist: "Enanitos Verdes", genre: "Rock / Pop en Español" },
      { title: "Mil Horas", artist: "Los Abuelos de la Nada", genre: "Rock / Pop en Español" },
      { title: "Rayando el Sol", artist: "Maná", genre: "Rock / Pop en Español" },
      { title: "La Flaca", artist: "Jarabe de Palo", genre: "Rock / Pop en Español" },
      { title: "Persiana Americana", artist: "Soda Stereo", genre: "Rock / Pop en Español" },
      
      # Pop / Disco Internacional
      { title: "Uptown Funk", artist: "Bruno Mars & Mark Ronson", genre: "Pop / Disco Internacional" },
      { title: "Don't Stop Believin'", artist: "Journey", genre: "Pop / Disco Internacional" },
      { title: "Billie Jean", artist: "Michael Jackson", genre: "Pop / Disco Internacional" },
      { title: "Can't Stop the Feeling!", artist: "Justin Timberlake", genre: "Pop / Disco Internacional" },
      { title: "I Wanna Dance with Somebody", artist: "Whitney Houston", genre: "Pop / Disco Internacional" },
      { title: "Sweet Child O' Mine", artist: "Guns N' Roses", genre: "Pop / Disco Internacional" },

      # Bailable / Tropical / Salsa / Merengue
      { title: "La Bilirrubina", artist: "Juan Luis Guerra", genre: "Bailable / Tropical / Salsa / Merengue" },
      { title: "Vivir Mi Vida", artist: "Marc Anthony", genre: "Bailable / Tropical / Salsa / Merengue" },
      { title: "Suavemente", artist: "Elvis Crespo", genre: "Bailable / Tropical / Salsa / Merengue" },
      { title: "Pedro Navaja", artist: "Rubén Blades", genre: "Bailable / Tropical / Salsa / Merengue" },
      { title: "Procura", artist: "Chichi Peralta", genre: "Bailable / Tropical / Salsa / Merengue" },
      { title: "El Niágara en Bicicleta", artist: "Juan Luis Guerra", genre: "Bailable / Tropical / Salsa / Merengue" },

      # Reggaetón / Urbano
      { title: "Gasolina", artist: "Daddy Yankee", genre: "Reggaetón / Urbano" },
      { title: "Danza Kuduro", artist: "Don Omar", genre: "Reggaetón / Urbano" },
      { title: "Pepas", artist: "Farruko", genre: "Reggaetón / Urbano" },
      { title: "Tití Me Preguntó", artist: "Bad Bunny", genre: "Reggaetón / Urbano" },

      # Baladas / Románticas / Primer Baile
      { title: "Perfect", artist: "Ed Sheeran", genre: "Baladas / Románticas / Primer Baile" },
      { title: "All of Me", artist: "John Legend", genre: "Baladas / Románticas / Primer Baile" },
      { title: "Entra en Mi Vida", artist: "Sin Bandera", genre: "Baladas / Románticas / Primer Baile" },
      { title: "Stand by Me", artist: "Ben E. King", genre: "Baladas / Románticas / Primer Baile" },
      { title: "Bésame Mucho", artist: "Clásico Bolero", genre: "Baladas / Románticas / Primer Baile" }
    ]

    sample_songs.each do |song_attrs|
      current_company.songs.find_or_create_by!(title: song_attrs[:title], artist: song_attrs[:artist]) do |s|
        s.genre = song_attrs[:genre]
        s.active = true
      end
    end

    redirect_to songs_path, notice: "🎉 Se cargó el repertorio base exitosamente."
  end

  private

  def set_song
    @song = current_company.songs.find(params[:id])
  end

  def song_params
    params.require(:song).permit(:title, :artist, :genre, :active)
  end

  def require_leader_or_admin!
    unless current_user.leader? || current_user.superadmin?
      redirect_to root_path, alert: "Acceso no autorizado."
    end
  end
end
