class GigReview < ApplicationRecord
  belongs_to :gig

  has_many_attached :photos

  validates :client_name, presence: true
  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :comment, presence: true, length: { minimum: 3, maximum: 1000 }

  scope :approved, -> { where(approved: true) }
  scope :pinned_first, -> { order(pinned: :desc, created_at: :desc) }

  def stars_display
    "★" * rating + "☆" * (5 - rating)
  end
end
