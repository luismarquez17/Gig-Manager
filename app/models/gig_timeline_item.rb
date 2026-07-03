class GigTimelineItem < ApplicationRecord
  belongs_to :gig

  validates :time, :title, presence: true

  default_scope { order(position: :asc, time: :asc) }
end
