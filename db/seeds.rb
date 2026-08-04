# Garantizar la empresa principal del dueño (Márquez Música)
marquez_musica = Company.find_by(slug: 'marquez-musica') || Company.find_by(slug: 'principal')

if marquez_musica.nil?
  marquez_musica = Company.create!(
    name: 'Márquez Música',
    slug: 'marquez-musica',
    monthly_fee: 0.0,
    currency: 'USD',
    status: :active,
    invitation_token: SecureRandom.hex(12)
  )
else
  marquez_musica.update!(name: 'Márquez Música', slug: 'marquez-musica')
end

# Garantizar usuario Superadmin y dueño de Márquez Música
superadmin = User.find_or_initialize_by(email: 'luismarquezocando2006@gmail.com')
superadmin.name ||= 'Luis Márquez'
superadmin.password = '123456'
superadmin.password_confirmation = '123456'
superadmin.role = :superadmin
superadmin.company = marquez_musica
superadmin.save!

puts "✅ Seed completado: Usuario Superadmin y dueño de Márquez Música asignado (#{superadmin.email})"
