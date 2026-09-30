class EnsureGeroProduccionesVenueProfile < ActiveRecord::Migration[7.1]
  def up
    Company.unscoped.find_each do |company|
      if company.name.to_s.downcase.include?('gero') || company.slug.to_s.downcase.include?('gero')
        company.update_columns(
          business_type: 'venue_academy',
          plan_tier: 'salon'
        )
      end
    end
  end

  def down
  end
end
