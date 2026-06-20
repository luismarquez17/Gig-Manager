class RenameEmailToNotesInClients < ActiveRecord::Migration[7.1]
  def change
    rename_column :clients, :email, :notes
  end
end