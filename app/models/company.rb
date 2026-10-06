class Company < ApplicationRecord
  enum status: { active: 0, suspended: 1, past_due: 2, trial: 3 }

  has_many :users, dependent: :destroy
  has_many :clients, dependent: :destroy
  has_many :gigs, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :kits, dependent: :destroy
  has_many :investments, dependent: :destroy
  has_many :preset_budgets, dependent: :destroy
  has_many :standard_upsells, dependent: :destroy
  has_many :shopping_items, dependent: :destroy
  has_many :finance_settings, dependent: :destroy
  has_many :employee_payments, dependent: :destroy
  has_many :subscription_payments, dependent: :destroy
  has_many :gig_upsell_requests, dependent: :destroy
  has_many :client_quotes, dependent: :destroy
  has_many :cash_adjustments, dependent: :destroy
  has_many :financial_audit_logs, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :invitation_token, uniqueness: true, allow_nil: true
  validates :monthly_fee, numericality: { greater_than_or_equal_to: 0 }

  attribute :business_type, :string, default: 'music_band'

  DEFAULT_TRIAL_DAYS = 30
  VALID_PLAN_TIERS = ['banda', 'productora', 'salon', 'negocio', 'personalizado', 'full'].freeze

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

  before_validation :generate_slug_and_token, on: :create
  before_create :set_default_trial_period

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

  def seed_venue_upsells!
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

  def set_default_trial_period
    self.trial_started_at ||= Time.current
    self.trial_ends_at ||= DEFAULT_TRIAL_DAYS.days.from_now
    self.subscription_status ||= "trialing"
    self.plan_tier ||= "banda"
    self.enabled_modules ||= AppModule.default_hash
  end

  def effective_plan_tier
    VALID_PLAN_TIERS.include?(plan_tier.to_s) ? plan_tier.to_s : 'banda'
  end

  # ==========================================
  # GESTIÓN DE MÓDULOS / FEATURE FLAGS
  # ==========================================

  def modules
    stored = (has_attribute?(:enabled_modules) && enabled_modules.is_a?(Hash)) ? enabled_modules : {}
    AppModule.default_hash.merge(stored)
  end

  def module_enabled?(module_key)
    return false if module_key.blank?
    key_str = module_key.to_s
    # Por defecto, si no está explícitamente en falso, está habilitado
    modules[key_str] != false && modules[key_str] != "false" && modules[key_str] != 0
  end

  def enable_module!(module_key)
    return if module_key.blank?
    cfg = modules.dup
    cfg[module_key.to_s] = true
    update!(enabled_modules: cfg)
  end

  def disable_module!(module_key)
    return if module_key.blank?
    cfg = modules.dup
    cfg[module_key.to_s] = false
    update!(enabled_modules: cfg)
  end

  def update_modules!(new_modules_hash)
    formatted = {}
    AppModule.keys.each do |key|
      val = new_modules_hash[key] || new_modules_hash[key.to_sym]
      formatted[key] = (val == true || val == "1" || val == "true" || val == 1)
    end
    update!(enabled_modules: formatted)
  end

  def enabled_module_keys
    AppModule.keys.select { |key| module_enabled?(key) }
  end

  def pricing_breakdown(simulated_tier = nil, simulated_modules = nil)
    target_tier = simulated_tier.presence || effective_plan_tier
    target_modules = simulated_modules.presence || enabled_module_keys
    AppModule.calculate_pricing(target_tier, target_modules)
  end

  def calculated_monthly_fee
    pricing_breakdown[:total_price]
  end

  def extra_modules
    pricing_breakdown[:extra_modules_details]
  end

  def has_extra_modules?
    pricing_breakdown[:extra_keys].any?
  end

  # ==========================================
  # ESTADOS DE SUSCRIPCIÓN & FREE TRIAL
  # ==========================================

  def in_trial?
    subscription_status == "trialing"
  end

  def trial_active?
    in_trial? && trial_ends_at.present? && trial_ends_at > Time.current
  end

  def trial_expired?
    in_trial? && trial_ends_at.present? && trial_ends_at <= Time.current
  end

  def days_left_in_trial
    return 0 unless trial_ends_at.present? && trial_ends_at > Time.current
    ((trial_ends_at - Time.current) / 1.day).ceil
  end

  def active_subscription?
    subscription_status == "active"
  end

  def subscription_paid_and_active?
    active_subscription? && trial_ends_at.present? && trial_ends_at > Time.current
  end

  def days_left_in_subscription
    return 0 unless trial_ends_at.present? && trial_ends_at > Time.current
    ((trial_ends_at - Time.current) / 1.day).ceil
  end

  def subscription_expiration_date
    trial_ends_at
  end

  def access_granted?
    return false if suspended?
    return true if active_subscription? || trial_active?
    false
  end

  def plan_tier_name
    if effective_plan_tier == 'personalizado'
      "Plan Personalizado (#{enabled_module_keys.count} #{enabled_module_keys.count == 1 ? 'Módulo' : 'Módulos'})"
    else
      AppModule.package_info(effective_plan_tier)&.dig(:name) || 'Paquete Bandas & Orquestas'
    end
  end

  def subscription_label
    if suspended?
      "Suspendida"
    elsif active_subscription?
      "Suscripción Activa (#{plan_tier_name})"
    elsif trial_active?
      "Prueba Gratuita (#{days_left_in_trial} días restantes)"
    elsif trial_expired?
      "Prueba Gratuita Vencida"
    elsif past_due?
      "Pago Vencido"
    else
      subscription_status.to_s.titleize
    end
  end

  def leaders
    users.where(role: [:leader, :superadmin])
  end

  def primary_leader
    leaders.first
  end

  def regenerate_token!
    update!(invitation_token: SecureRandom.hex(12))
  end

  def status_badge_class
    case status.to_sym
    when :active
      "bg-emerald-500/10 text-emerald-400 border-emerald-500/20"
    when :suspended
      "bg-rose-500/10 text-rose-400 border-rose-500/20"
    when :past_due
      "bg-amber-500/10 text-amber-400 border-amber-500/20"
    when :trial
      "bg-blue-500/10 text-blue-400 border-blue-500/20"
    else
      "bg-slate-500/10 text-slate-400 border-slate-500/20"
    end
  end

  DEFAULT_PAYMENT_METHODS = {
    "zelle" => {
      "enabled" => true,
      "email" => "",
      "holder_name" => "",
      "bank" => "",
      "notes" => "Indicar el nombre del titular o evento en la descripción de Zelle."
    },
    "binance" => {
      "enabled" => true,
      "pay_id" => "",
      "email" => "",
      "network" => "USDT (TRC20 / BEP20)",
      "nickname" => "",
      "notes" => "Transferencia directa por Binance Pay sin comisiones."
    },
    "pago_movil" => {
      "enabled" => true,
      "bank" => "",
      "id_number" => "",
      "phone" => "",
      "holder_name" => "",
      "notes" => "Calcular al monto en Bolívares según la tasa del día."
    },
    "bank_transfer" => {
      "enabled" => false,
      "bank" => "",
      "account_number" => "",
      "account_type" => "Corriente",
      "id_number" => "",
      "holder_name" => "",
      "notes" => ""
    },
    "general_instructions" => "Una vez realizado tu pago o transferencia, sube tu comprobante en el botón 'Reportar Abono' para generar tu recibo oficial y actualizar tu saldo de inmediato."
  }.freeze

  def payment_methods
    cfg = (has_attribute?(:payment_methods_config) && payment_methods_config.is_a?(Hash)) ? payment_methods_config : {}
    DEFAULT_PAYMENT_METHODS.deep_merge(cfg)
  end

  def zelle_info
    payment_methods["zelle"] || {}
  end

  def binance_info
    payment_methods["binance"] || {}
  end

  def pago_movil_info
    payment_methods["pago_movil"] || {}
  end

  def bank_transfer_info
    payment_methods["bank_transfer"] || {}
  end

  def any_payment_method_enabled?
    zelle_enabled? || binance_enabled? || pago_movil_enabled? || bank_transfer_enabled?
  end

  def zelle_enabled?
    zelle_info["enabled"].to_s == "true" || zelle_info["enabled"] == true
  end

  def binance_enabled?
    binance_info["enabled"].to_s == "true" || binance_info["enabled"] == true
  end

  def pago_movil_enabled?
    pago_movil_info["enabled"].to_s == "true" || pago_movil_info["enabled"] == true
  end

  def bank_transfer_enabled?
    bank_transfer_info["enabled"].to_s == "true" || bank_transfer_info["enabled"] == true
  end

  private

  def generate_slug_and_token
    self.slug ||= name.to_s.parameterize.presence || SecureRandom.hex(4)
    self.invitation_token ||= SecureRandom.hex(12)
  end
end
