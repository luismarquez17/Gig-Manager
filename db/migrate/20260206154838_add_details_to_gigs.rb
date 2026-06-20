class AddDetailsToGigs < ActiveRecord::Migration[7.1]
  def change
    add_column :gigs, :currency, :string
  end
end
