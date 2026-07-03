class AddClientEmailAndClientToUsersAndGigs < ActiveRecord::Migration[7.1]
  def change
    # 1. Agregar client_email a gigs con índice
    add_column :gigs, :client_email, :string
    add_index :gigs, :client_email

    # 2. Hacer client_id opcional en gigs
    change_column_null :gigs, :client_id, true

    # 3. Asociar client a users (opcional)
    add_reference :users, :client, null: true, foreign_key: true
  end
end
