class GigTimelineItem < ApplicationRecord
  belongs_to :gig

  validates :time, :title, presence: true

  default_scope { order(position: :asc, time: :asc) }

  scope :for_client, -> { where(for_musician: false) }
  scope :for_musician, -> { where(for_musician: true) }
end
