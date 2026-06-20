# Script de prueba para validar las nuevas funcionalidades

ActiveRecord::Base.transaction do
  puts "=== Iniciando Pruebas de Modelos ==="

  # 1. Creación de registros de prueba
  item = Item.create!(name: "Test Cable XLR", category: "Cables", status: "Excelente", quantity: 10)
  puts "✓ Item creado: #{item.name} (Stock: #{item.quantity}, Estado: #{item.status})"

  client = Client.create!(name: "Cliente de Prueba", phone: "12345678")
  gig = Gig.create!(client: client, amount: 150.0, date: Date.today, location: "Hotel Intercontinental", currency: "USD")
  puts "✓ Gig creado para #{client.name} por $#{gig.amount}"

  gig_item = GigItem.create!(gig: gig, item: item, quantity: 5)
  puts "✓ GigItem creado: #{gig_item.quantity} unidades de #{item.name}"
  puts "  Valores iniciales - Cargado: #{gig_item.loaded_quantity}, Retornado: #{gig_item.returned_quantity}"

  # 2. Modificaciones de Carga/Descarga
  gig_item.update!(loaded_quantity: 5, returned_quantity: 4)
  puts "✓ GigItem actualizado: Cargado: #{gig_item.loaded_quantity}, Retornado: #{gig_item.returned_quantity}"
  puts "  ¿Tiene discrepancia?: #{gig_item.discrepancy? ? 'SÍ' : 'NO'}"

  # 3. Reporte de Daños (Simulación de Taller)
  puts "\n=== Test Taller de Mantenimiento ==="
  record = MaintenanceRecord.create!(
    item: item,
    gig: gig,
    description: "Conector XLR roto durante el desmontaje",
    status: :pending,
    cost: 0.0
  )
  puts "✓ Ticket creado: #{record.description} (Estado: #{record.status})"
  item.reload
  puts "  Estado del Item (debe ser Dañado): #{item.status}"
  raise "ERROR: El estado del item debería ser Dañado" unless item.status == "Dañado"

  # 4. Finalización de reparación (Fixed)
  record.update!(status: :fixed, cost: 15.00)
  puts "✓ Ticket actualizado a Listo (Costo: $#{record.cost})"
  item.reload
  puts "  Estado del Item (debe ser Excelente): #{item.status}"
  raise "ERROR: El estado del item debería ser Excelente" unless item.status == "Excelente"

  # 5. Reporte de pérdida
  puts "\n=== Test Reporte de Pérdida ==="
  # Simulación del controlador para reportar pérdida de 2 unidades
  lost_qty = 2
  
  # Lógica del controlador:
  new_returned = [[gig_item.returned_quantity + lost_qty, 0].max, gig_item.loaded_quantity].min
  gig_item.update!(returned_quantity: new_returned)
  
  # Descuento en stock maestro
  if lost_qty > 1
    qty_to_deduct_now = lost_qty - 1
    item.update!(quantity: [item.quantity - qty_to_deduct_now, 0].max)
  end

  # Crear record con status :discarded (el callback descontará la otra unidad)
  lost_record = MaintenanceRecord.create!(
    item: item,
    gig: gig,
    description: "PÉRDIDA EN EVENTO: Se extraviaron en el salón",
    status: :discarded,
    cost: 0.00
  )

  item.reload
  gig_item.reload
  puts "✓ Pérdida procesada:"
  puts "  Nueva cantidad en inventario maestro (debe ser 8): #{item.quantity}"
  puts "  Nueva cantidad retornada (debe ser 5): #{gig_item.returned_quantity}"
  puts "  ¿Tiene discrepancia? (debe ser NO): #{gig_item.discrepancy? ? 'SÍ' : 'NO'}"

  raise "ERROR: El stock del item debería ser 8" unless item.quantity == 8
  raise "ERROR: El gig_item debería estar cuadrado (retornado = 5)" unless gig_item.returned_quantity == 5

  puts "\n=== ¡TODAS LAS PRUEBAS PASARON EXITOSAMENTE! ==="
  
  # Hacemos rollback para no contaminar la base de datos de producción/desarrollo del usuario
  puts "Realizando rollback para limpiar datos de prueba..."
  raise ActiveRecord::Rollback
end
