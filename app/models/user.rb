class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum role: { client: 0, staff: 1, leader: 2 }

  has_many :staff_assignments, dependent: :destroy
  has_many :assigned_gigs, through: :staff_assignments, source: :gig
end
