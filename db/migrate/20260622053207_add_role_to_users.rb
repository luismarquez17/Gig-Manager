class AddRoleToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :role, :integer, default: 0

    # Backfill existing users to be leaders without loading the User model
    reversible do |dir|
      dir.up do
        execute("UPDATE users SET role = 2")
      end
    end
  end
end
