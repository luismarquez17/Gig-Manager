# frozen_string_literal: true

module Companies
  module BusinessProfiles
    extend ActiveSupport::Concern

    included do
      BUSINESS_TYPES = {
        'music_band' => {
          name: 'Banda u Orquesta Musical',
          icon: '🎸',
          badge: 'Músicos & Shows',
          description: 'Optimizado para orquestas, bandas, solistas y directores musicales.'
        },
        'venue_academy' => {
          name: 'Salón de Fiestas & Academia de Modelaje',
          icon: '🏛️',
          badge: 'Salones & Academia',
          description: 'Especializado en salones de eventos, fiestas, pasarelas de modelaje y protocolo.'
        },
        'party_hall' => {
          name: 'Salón de Eventos, Quintas & Venues',
          icon: '🎉',
          badge: 'Salones & Fiestas',
          description: 'Gestión integral de salones, reservas de fechas, mobiliario y eventos sociales.'
        },
        'production_company' => {
          name: 'Productora de Audio, Luces & Eventos',
          icon: '🎬',
          badge: 'Productoras',
          description: 'Sonido en vivo, iluminación, tarimas y logística técnica para eventos.'
        },
        'general_business' => {
          name: 'Empresa de Servicios / Comercial',
          icon: '💼',
          badge: 'Empresas',
          description: 'Gestión comercial de servicios, cotizaciones y caja general.'
        }
      }.freeze

      TERMINOLOGY = {
        'music_band' => {
          gig_singular: 'Gig / Show',
          gig_plural: 'Gigs / Eventos',
          event_singular: 'Show',
          event_plural: 'Eventos / Shows',
          gigs_history: 'Historial de Toques',
          new_gig_btn: '➕ Registrar Nuevo Toque',
          gigs_filter: 'Buscador & Filtros de Toques',
          event_sheet: '📸 Ficha de Show',
          in_this_gig: 'en este toque',
          assigned_workers_title: 'Trabajadores asignados',
          assign_worker_label: 'Seleccionar trabajador (Staff / Músico)',
          assign_worker_help: '¿Cuánto le vas a pagar a este personal? ($ USD)',
          assign_worker_btn: '➕ Asignar trabajador',
          assign_worker_tip: '¿No encuentras a tu músico o staff en la lista?',
          assign_worker_prompt: '-- Seleccionar personal --',
          band_fund: 'Fondo de la Banda',
          net_profit_label: 'Ganancia Neta Banda',
          payroll_title: 'Nómina del Show',
          musicians: 'Músicos & Artistas',
          musician_singular: 'Músico',
          musicians_timeline: 'Cronograma para Músicos',
          arrival_time: 'Llegada al Show / Tarima',
          soundcheck: 'Soundcheck / Prueba de Sonido',
          music_notes: 'Repertorio & Notas Musicales',
          music_notes_desc: 'Canciones especiales solicitadas por el cliente (vals, entrada, etc.)',
          gig_fee: 'Bolo / Honorario Musical',
          inventory_badge: 'Backline & Equipos',
          packages: 'Formatos de Show'
        },
        'venue_academy' => {
          gig_singular: 'Evento / Fiesta / Alquiler',
          gig_plural: 'Eventos & Fiestas',
          event_singular: 'Evento',
          event_plural: 'Eventos',
          gigs_history: 'Historial de Eventos',
          new_gig_btn: '➕ Registrar Nuevo Evento',
          gigs_filter: 'Buscador & Filtros de Eventos',
          event_sheet: '📸 Ficha del Evento',
          in_this_gig: 'en este evento',
          assigned_workers_title: 'Trabajadores y Proveedores asignados',
          assign_worker_label: 'Seleccionar trabajador o proveedor (Staff / Pasapalos / Protocolo / Sonido)',
          assign_worker_help: '¿Cuánto le vas a pagar a este trabajador o proveedor? ($ USD)',
          assign_worker_btn: '➕ Asignar trabajador / proveedor',
          assign_worker_tip: '¿No encuentras a tu trabajador o proveedor (ej. pasapalos, sonido, protocolo) en la lista?',
          assign_worker_prompt: '-- Seleccionar trabajador o proveedor --',
          band_fund: 'Fondo de la Empresa',
          net_profit_label: 'Ganancia Neta Evento',
          payroll_title: 'Nómina & Proveedores del Evento',
          musicians: 'Trabajadores, Proveedores & Modelos',
          musician_singular: 'Trabajador / Proveedor',
          musicians_timeline: 'Cronograma de Operaciones & Protocolo',
          arrival_time: 'Llegada al Salón / Montaje',
          soundcheck: 'Prueba Técnica & Ensayo de Pasarela',
          music_notes: 'Protocolo & Notas Especiales del Evento',
          music_notes_desc: 'Detalles del protocolo, temática, momentos clave y requerimientos especiales',
          gig_fee: 'Honorario / Pago de Servicio o Proveedor',
          inventory_badge: 'Mobiliario, Sonido & Pasarela',
          packages: 'Combos de Salón & Academia'
        },
        'party_hall' => {
          gig_singular: 'Evento / Fiesta',
          gig_plural: 'Eventos & Fiestas',
          event_singular: 'Evento',
          event_plural: 'Eventos',
          gigs_history: 'Historial de Eventos',
          new_gig_btn: '➕ Registrar Nuevo Evento',
          gigs_filter: 'Buscador & Filtros de Eventos',
          event_sheet: '📸 Ficha del Evento',
          in_this_gig: 'en este evento',
          assigned_workers_title: 'Trabajadores y Proveedores asignados',
          assign_worker_label: 'Seleccionar personal de salón o proveedor (Staff / Pasapalos / Decoración / Apoyo)',
          assign_worker_help: '¿Cuánto le vas a pagar a este trabajador o proveedor? ($ USD)',
          assign_worker_btn: '➕ Asignar personal / proveedor',
          assign_worker_tip: '¿No encuentras a tu personal o proveedor en la lista?',
          assign_worker_prompt: '-- Seleccionar personal o proveedor --',
          band_fund: 'Fondo del Salón',
          net_profit_label: 'Ganancia Neta Salón',
          payroll_title: 'Nómina & Proveedores del Evento',
          musicians: 'Personal de Salón, Staff & Proveedores',
          musician_singular: 'Personal / Proveedor',
          musicians_timeline: 'Cronograma de Operaciones',
          arrival_time: 'Llegada al Salón / Apertura',
          soundcheck: 'Prueba de Sonido & Luces',
          music_notes: 'Protocolo & Cronograma del Evento',
          music_notes_desc: 'Protocolo de la fiesta, vals, brindis, entrada y momentos clave',
          gig_fee: 'Honorario / Pago de Servicio o Proveedor',
          inventory_badge: 'Mobiliario & Equipos',
          packages: 'Combos de Salón'
        },
        'production_company' => {
          gig_singular: 'Producción / Montaje',
          gig_plural: 'Producciones & Montajes',
          event_singular: 'Producción',
          event_plural: 'Producciones',
          gigs_history: 'Historial de Producciones',
          new_gig_btn: '➕ Registrar Nueva Producción',
          gigs_filter: 'Buscador & Filtros de Producciones',
          event_sheet: '📸 Ficha de Producción',
          in_this_gig: 'en esta producción',
          assigned_workers_title: 'Equipo Técnico y Proveedores asignados',
          assign_worker_label: 'Seleccionar personal técnico o proveedor (Operador / Staff / Servicios / Pasapalos)',
          assign_worker_help: '¿Cuánto le vas a pagar a este personal técnico o proveedor? ($ USD)',
          assign_worker_btn: '➕ Asignar técnico / proveedor',
          assign_worker_tip: '¿No encuentras a tu técnico o proveedor en la lista?',
          assign_worker_prompt: '-- Seleccionar técnico o proveedor --',
          band_fund: 'Fondo de la Productora',
          net_profit_label: 'Margen Neto Producción',
          payroll_title: 'Nómina & Proveedores de Producción',
          musicians: 'Equipo Técnico, Staff & Proveedores',
          musician_singular: 'Técnico / Proveedor',
          musicians_timeline: 'Cronograma de Montaje y Desmontaje',
          arrival_time: 'Llegada al Venue / Carga',
          soundcheck: 'Alineación de Sistema & Prueba',
          music_notes: 'Rider Técnico & Notas del Evento',
          music_notes_desc: 'Requerimientos técnicos, canales, microfonía y especificaciones',
          gig_fee: 'Honorario Técnico / Proveedor',
          inventory_badge: 'Equipos & Cajas QR',
          packages: 'Paquetes de Producción'
        }
      }.freeze

      DEFAULT_VENUE_COMBOS = [
        {
          title: "Combo 15 Años & Bodas Glamour",
          badge_text: "Más Solicitado",
          featured: true,
          price: 850.00,
          description: "Alquiler del Salón Principal climatizado + Mobiliario completo con mantelería de gala + Sonido profesional con DJ + Iluminación Robótica & Decorativa + Entrada Triunfal / Pasarela iluminada + Coordinador de Protocolo y atención durante todo el evento."
        },
        {
          title: "Combo Cumpleaños & Fiestas Privadas",
          badge_text: "Ideal Fiestas",
          featured: false,
          price: 450.00,
          description: "Horas de Salón + Mesas y sillas vestidas + Sonido ambiental de alta fidelidad + Cabina de DJ + Luces rítmicas de fiesta + Personal de protocolo y apoyo."
        },
        {
          title: "Combo Desfile & Pasarela (Academia de Modelaje)",
          badge_text: "Pasarela Pro",
          featured: true,
          price: 650.00,
          description: "Estructura de Pasarela profesional elevada con alfombra + Iluminación blanca frontal y cenital de pasarela + Sonido para desfile de modas + Área de Vestuarios y Backstage + Guías de protocolo y logística."
        },
        {
          title: "Combo Graduaciones & Eventos Corporativos",
          badge_text: "Corporativo",
          featured: false,
          price: 550.00,
          description: "Salón acondicionado para conferencias, talleres o actos de grado + Sonido para oratoria y conferencias + 2 Micrófonos inalámbricos + Pantalla gigante / Video Beam + Podio y Mesa de Honor protocolar."
        },
        {
          title: "Mensualidad / Talleres de Modelaje e Imagen",
          badge_text: "Formación",
          featured: false,
          price: 60.00,
          description: "Membresía mensual de formación integral en la academia: Clases de Pasarela profesional, Fotopose, Oratoria, Etiqueta, Protocolo, Expresión corporal y Asesoría de Imagen."
        }
      ].freeze

      DEFAULT_VENUE_UPSELLS = [
        { key: "hora_extra_salon", title: "Hora Adicional de Salón", emoji: "⏰", price: 60.00, description: "Extensión del uso del salón y personal de apoyo por hora adicional." },
        { key: "pasarela_led", title: "Pasarela Iluminada LED", emoji: "✨", price: 120.00, description: "Módulos de pasarela con iluminación interna LED y efectos de color para desfiles o 15 años." },
        { key: "pantalla_led", title: "Pantalla LED Gigante / Proyector", emoji: "🖥️", price: 100.00, description: "Pantalla gigante para proyección de videos homenaje, desfiles o presentaciones corporativas." },
        { key: "humo_chispas", title: "Chispas Frías & Humo Bajo", emoji: "🎆", price: 70.00, description: "Efectos especiales de chispas frías (sin humo tóxico) para el vals, brindis o salida de pasarela." },
        { key: "staff_modelos", title: "Staff de Modelos de Protocolo", emoji: "👠", price: 80.00, description: "2 Modelos profesionales de la academia para bienvenida, entrega de reconocimientos y atención protocolar." }
      ].freeze
    end

    def business_type_info
      BUSINESS_TYPES[business_type.to_s] || BUSINESS_TYPES['music_band']
    end

    def business_type_name
      business_type_info[:name]
    end

    def business_type_icon
      business_type_info[:icon] || '🏛️'
    end

    def venue_mode?
      business_type.to_s.in?(['venue_academy', 'party_hall', 'production_company']) || effective_plan_tier == 'salon' || name.to_s.downcase.include?('gero') || slug.to_s.downcase.include?('gero')
    end

    def academy_mode?
      business_type.to_s == 'venue_academy' || (name.to_s.downcase.include?('gero') && business_type.to_s != 'music_band')
    end

    def music_mode?
      business_type.to_s == 'music_band' && effective_plan_tier != 'salon' && !name.to_s.downcase.include?('gero')
    end

    def term_for(key, fallback = nil)
      effective_type = if (name.to_s.downcase.include?('gero') || slug.to_s.downcase.include?('gero')) && business_type.to_s == 'music_band'
        'venue_academy'
      else
        business_type.to_s
      end
      dict = TERMINOLOGY[effective_type] || TERMINOLOGY['music_band']
      dict[key.to_sym] || fallback || TERMINOLOGY['music_band'][key.to_sym] || key.to_s.humanize
    end

    def apply_venue_academy_defaults!
      update!(
        business_type: 'venue_academy',
        plan_tier: 'salon',
        enabled_modules: {
          'gigs' => true,
          'clients_crm' => true,
          'finances' => true,
          'payroll' => true,
          'inventory' => false,
          'shopping_list' => false,
          'songs_repertoire' => false
        }
      )
      seed_venue_combos!
      seed_venue_upsells!
    end

    def seed_venue_combos!
      ActsAsTenant.with_tenant(self) do
        DEFAULT_VENUE_COMBOS.each_with_index do |combo, idx|
          preset_budgets.find_or_create_by!(title: combo[:title]) do |pb|
            pb.description = combo[:description]
            pb.price = combo[:price]
            pb.currency = 'USD'
            pb.badge_text = combo[:badge_text]
            pb.featured = combo[:featured]
            pb.position = idx + 1
            pb.show_on_landing = true
          end
        end
      end
    end

    def seed_venue_upsells!
      ActsAsTenant.with_tenant(self) do
        DEFAULT_VENUE_UPSELLS.each do |up|
          target_key = "#{slug}_#{up[:key]}".parameterize(separator: '_')
          standard_upsells.find_or_create_by!(key: target_key) do |su|
            su.title = up[:title]
            su.emoji = up[:emoji]
            su.price = up[:price]
            su.currency = 'USD'
            su.description = up[:description]
            su.active = true
            su.show_on_landing = true
          end
        end
      end
    end
  end
end
