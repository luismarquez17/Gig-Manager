class AppModule
  MODULES = {
    gigs: {
      key: 'gigs',
      name: 'Eventos & Shows (Gigs)',
      icon: '🎸',
      category: 'Operaciones',
      description: 'Gestión integral de fechas, contratos, horarios, hojas de ruta y músicos asignados.',
      features: [
        'Calendario y Agenda de Shows en Vivo',
        'Asignación de Músicos & Staff con Roles',
        'Control de Anticipos y Pagos de Eventos',
        'Hojas de Ruta con Locación GPS y Horarios'
      ],
      default_enabled: true
    },
    inventory: {
      key: 'inventory',
      name: 'Inventario, Kits & Taller QR',
      icon: '📦',
      category: 'Logística',
      description: 'Control de equipos con códigos QR, plantillas de tarima (kits), reparaciones y conflictos de disponibilidad.',
      features: [
        'Inventario con Códigos QR y Seriales',
        'Plantillas de Tarima (Kits de Sonido, Luces y Backline)',
        'Taller de Reparaciones y Mantenimiento Preventivo',
        'Detección Inteligente de Conflictos en Calendario'
      ],
      default_enabled: true
    },
    clients_crm: {
      key: 'clients_crm',
      name: 'CRM, Presupuestos & Cotizador Web',
      icon: '👥',
      category: 'Comercial',
      description: 'CRM de clientes, presupuestos base, cotizaciones públicas con enlace de WhatsApp y venta de adicionales (upselling).',
      features: [
        'Directorio de Clientes y Cuentas por Cobrar',
        'Presupuestos Base y Paquetes de Shows Reutilizables',
        'Cotizaciones Públicas con Aprobación Web (/q/:token)',
        'Catálogo de Adicionales & Upselling (Luces, Horas extra)',
        'Cuentas Bancarias y Métodos de Pago Oficiales'
      ],
      default_enabled: true
    },
    finances: {
      key: 'finances',
      name: 'Finanzas, Fondo de la Banda & Inversiones',
      icon: '🏦',
      category: 'Finanzas',
      description: 'Libro de caja general, balance del Fondo de la Banda, registro de inversiones y métricas de rentabilidad.',
      features: [
        'Caja General / Fondo de la Banda en Vivo',
        'Flujo de Caja Real (Ingresos vs Gastos Operativos)',
        'Registro y Control de Inversiones en Equipos',
        'Métricas de Rentabilidad y Utilidad Neta'
      ],
      default_enabled: true
    },
    payroll: {
      key: 'payroll',
      name: 'Nómina & Pagos a Trabajadores',
      icon: '💰',
      category: 'Finanzas',
      description: 'Cálculo de honorarios, balances pendientes con músicos/staff y confirmación de reportes de pago.',
      features: [
        'Liquidación Automática por Bolo o Porcentaje',
        'Control de Deudas y Balances con Cada Músico',
        'Revisión y Aprobación de Recibos de Pago',
        'Portal Privado para Músicos y Técnicos'
      ],
      default_enabled: true
    },
    shopping_list: {
      key: 'shopping_list',
      name: 'Lista de Compras & Suministros',
      icon: '🛒',
      category: 'Logística',
      description: 'Planificación de compras de consumibles y conversión directa de artículos comprados al inventario.',
      features: [
        'Control de Consumibles (Cables, Baterías, Repuestos)',
        'Presupuesto y Estimación de Compras',
        'Conversión Directa a Inventario con 1 Clic'
      ],
      default_enabled: true
    },
    songs_repertoire: {
      key: 'songs_repertoire',
      name: 'Repertorio Musical & Normativas',
      icon: '🎵',
      category: 'Operaciones',
      description: 'Catálogo de canciones por género/tonalidad y normativas internas para músicos de la agrupación.',
      features: [
        'Cancionero Digital por Género y Tonalidad',
        'Hojas de Ruta y Setlists de Temas para Tarima',
        'Normativas Internas y Políticas de la Agrupación'
      ],
      default_enabled: true
    }
  }.freeze

  PACKAGES = {
    'banda' => {
      name: 'Paquete Bandas & Orquestas',
      icon: '🎸',
      price: 15.00,
      modules: ['gigs', 'payroll', 'songs_repertoire', 'finances']
    },
    'productora' => {
      name: 'Paquete Productoras & Audio',
      icon: '🎬',
      price: 18.00,
      modules: ['gigs', 'inventory', 'clients_crm', 'payroll', 'shopping_list']
    },
    'salon' => {
      name: 'Paquete Salones & Venues',
      icon: '🏛️',
      price: 15.00,
      modules: ['gigs', 'inventory', 'clients_crm', 'finances']
    },
    'negocio' => {
      name: 'Paquete Empresas & Negocios',
      icon: '💼',
      price: 14.00,
      modules: ['clients_crm', 'finances', 'payroll']
    },
    'full' => {
      name: 'Paquete Full Suite Total',
      icon: '👑',
      price: 22.00,
      modules: ['gigs', 'inventory', 'clients_crm', 'finances', 'payroll', 'shopping_list', 'songs_repertoire']
    },
    'starter' => {
      name: 'Plan Base',
      icon: '🚀',
      price: 10.00,
      modules: ['gigs', 'inventory', 'clients_crm', 'finances', 'payroll', 'shopping_list', 'songs_repertoire']
    },
    'pro' => {
      name: 'Plan Pro',
      icon: '✨',
      price: 20.00,
      modules: ['gigs', 'inventory', 'clients_crm', 'finances', 'payroll', 'shopping_list', 'songs_repertoire']
    }
  }.freeze

  def self.all
    MODULES.values
  end

  def self.keys
    MODULES.keys.map(&:to_s)
  end

  def self.find(key)
    return nil if key.blank?
    MODULES[key.to_sym]
  end

  def self.name_for(key)
    find(key)&.dig(:name) || key.to_s.humanize
  end

  def self.icon_for(key)
    find(key)&.dig(:icon) || '⚡'
  end

  def self.features_for(key)
    find(key)&.dig(:features) || []
  end

  def self.modules_for_package(pkg_key)
    PACKAGES.dig(pkg_key.to_s, :modules)
  end

  def self.package_info(pkg_key)
    PACKAGES[pkg_key.to_s]
  end

  def self.default_hash
    MODULES.transform_values { |m| m[:default_enabled] }.stringify_keys
  end

  def self.build_modules_hash(enabled_keys)
    keys_array = if enabled_keys.is_a?(String)
                   enabled_keys.split(',').map(&:strip).reject(&:blank?)
                 else
                   Array(enabled_keys).flatten.map(&:to_s).map(&:strip).reject(&:blank?)
                 end
    return default_hash if keys_array.empty?

    MODULES.keys.each_with_object({}) do |key, h|
      h[key.to_s] = keys_array.include?(key.to_s)
    end
  end

  def self.by_category
    all.group_by { |m| m[:category] }
  end
end
