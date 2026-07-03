# scratch/check_claim.rb

puts "--- TEST START ---"

test_email = "verification_test_#{Time.now.to_i}@example.com"
puts "Generating unique test email: #{test_email}"

# 1. Crear Gig con solo email de cliente
puts "\n1. Creando Gig con solo email..."
gig = Gig.new(
  client_email: test_email,
  amount: 250.0,
  currency: "USD",
  location: "Verification Plaza",
  date: Date.today
)

if gig.save
  puts "✅ Gig creado con éxito! ID: #{gig.id}"
  puts "   client_id: #{gig.client_id.inspect} (debe ser nil)"
  puts "   client_email: #{gig.client_email}"
else
  puts "❌ Error al crear Gig: #{gig.errors.full_messages.join(', ')}"
  exit 1
end

# 2. Registrar usuario nuevo con ese correo
puts "\n2. Creando usuario con el mismo email..."
user = User.new(
  email: test_email,
  password: "password123",
  password_confirmation: "password123"
)

if user.save
  puts "✅ Usuario creado con éxito! ID: #{user.id}"
  puts "   client_id de usuario: #{user.client_id.inspect} (debe estar asociado)"
  
  # Buscar cliente
  client = user.client
  if client
    puts "   Client asociado - Nombre: #{client.name}, Email: #{client.email}"
  else
    puts "❌ No se asoció ningún cliente al usuario!"
  end
else
  puts "❌ Error al crear usuario: #{user.errors.full_messages.join(', ')}"
  exit 1
end

# 3. Verificar que el Gig anterior ahora tenga asignado el client_id del usuario recién registrado
puts "\n3. Verificando si el Gig fue reclamado..."
gig.reload
if gig.client_id == user.client_id && gig.client_id.present?
  puts "✅ ¡GIG RECLAMADO CON ÉXITO!"
  puts "   Gig client_id: #{gig.client_id} (coincide con user.client_id: #{user.client_id})"
else
  puts "❌ Error: El Gig no fue reclamado o client_id es incorrecto."
  puts "   Gig client_id: #{gig.client_id.inspect}"
  puts "   User client_id: #{user.client_id.inspect}"
  exit 1
end

puts "\n--- TEST SUCCESS ---"
