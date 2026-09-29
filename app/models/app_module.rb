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
      key: 'banda',
      name: 'Paquete Bandas & Orquestas',
      icon: '🎸',
      badge: 'Más Popular',
      price: 15.00,
      savings: '$2 USD/mes',
      description: 'Ideal para agrupaciones, directores, orquestas y bandas en vivo: Agenda de shows, nóminas por bolo/porcentaje, repertorio y caja.',
      modules: ['gigs', 'payroll', 'songs_repertoire', 'finances']
    },
    'productora' => {
      key: 'productora',
      name: 'Paquete Productoras & Audio',
      icon: '🎬',
      badge: 'Productoras',
      price: 18.00,
      savings: '$2 USD/mes',
      description: 'Optimizado para empresas de producción técnica, alquiler de audio, tarimas, luces e iluminación con inventario QR y cotizaciones.',
      modules: ['gigs', 'inventory', 'clients_crm', 'payroll', 'shopping_list']
    },
    'salon' => {
      key: 'salon',
      name: 'Paquete Salones & Venues',
      icon: '🏛️',
      badge: 'Salones & Academia',
      price: 15.00,
      savings: '$2 USD/mes',
      description: 'Pensado para salones de fiesta, quintas, venues y academias: Gestión de eventos, combos y cotizaciones públicas, finanzas y nómina de personal.',
      modules: ['gigs', 'clients_crm', 'finances', 'payroll']
    },
    'negocio' => {
      key: 'negocio',
      name: 'Paquete Empresas & Negocios',
      icon: '💼',
      badge: 'Pymes',
      price: 14.00,
      savings: '$3 USD/mes',
      description: 'Diseñado para pymes, comercios y prestadores de servicios: Gestión de clientes, presupuestos por WhatsApp, finanzas y nómina.',
      modules: ['clients_crm', 'finances', 'payroll']
    },
    'full' => {
      key: 'full',
      name: 'Paquete Full Suite Total',
      icon: '👑',
      badge: '⭐ Acceso Total',
      price: 22.00,
      savings: '$4 USD/mes',
      featured: true,
      description: 'Acceso total e ilimitado a todas las herramientas actuales y futuras del ecosistema GigManager con soporte prioritario.',
      modules: ['gigs', 'inventory', 'clients_crm', 'finances', 'payroll', 'shopping_list', 'songs_repertoire']
    }
  }.freeze

  def self.packages
    PACKAGES.values
  end

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
    package_info(pkg_key)&.dig(:modules) || PACKAGES['banda'][:modules]
  end

  def self.package_info(pkg_key)
    k = pkg_key.to_s
    PACKAGES[k] || PACKAGES['banda']
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

  EXTRA_MODULE_PRICE = 3.00

  def self.extra_module_price
    EXTRA_MODULE_PRICE
  end

  def self.calculate_pricing(pkg_key, enabled_keys)
    clean_key = (PACKAGES.key?(pkg_key.to_s)) ? pkg_key.to_s : 'banda'
    pkg = package_info(clean_key)
    pkg_modules = pkg[:modules] || []
    base_price = pkg[:price].to_f

    enabled_array = if enabled_keys.is_a?(Hash)
                      enabled_keys.select { |_, v| v == true || v == "1" || v == 1 || v == "true" }.keys.map(&:to_s)
                    else
                      Array(enabled_keys).flatten.map(&:to_s).reject(&:blank?)
                    end

    included_keys = enabled_array & pkg_modules
    extra_keys = enabled_array - pkg_modules
    extra_cost = extra_keys.count * EXTRA_MODULE_PRICE
    subtotal = base_price + extra_cost

    full_suite_pkg = package_info('full')
    full_suite_price = full_suite_pkg ? full_suite_pkg[:price].to_f : 22.00
    suggests_full_suite = (subtotal >= full_suite_price) && (clean_key != 'full')
    effective_total = suggests_full_suite ? full_suite_price : subtotal

    custom_plan_name = if clean_key == 'full'
                         pkg[:name]
                       elsif extra_keys.any?
                         "#{pkg[:name]} + #{extra_keys.count} Adicional(es) (Personalizado)"
                       else
                         pkg[:name]
                       end

    {
      package_key: pkg[:key],
      package_name: pkg[:name],
      custom_plan_name: custom_plan_name,
      package_icon: pkg[:icon],
      package_badge: pkg[:badge],
      base_price: base_price,
      pkg_modules: pkg_modules,
      enabled_keys: enabled_array,
      included_keys: included_keys,
      extra_keys: extra_keys,
      extra_module_price: EXTRA_MODULE_PRICE,
      extra_cost: extra_cost,
      difference_amount: extra_cost,
      subtotal: subtotal,
      total_price: effective_total,
      suggests_full_suite: suggests_full_suite,
      full_suite_price: full_suite_price,
      savings_with_full_suite: suggests_full_suite ? (subtotal - full_suite_price).round(2) : 0.0,
      included_modules_details: included_keys.map { |k| find(k) }.compact,
      extra_modules_details: extra_keys.map { |k| find(k) }.compact,
      total_modules_count: enabled_array.count,
      has_extras: extra_keys.any?
    }
  end

  def self.by_category
    all.group_by { |m| m[:category] }
  end
end
