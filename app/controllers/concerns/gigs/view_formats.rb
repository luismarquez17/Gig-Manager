# frozen_string_literal: true

module Gigs
  module ViewFormats
    extend ActiveSupport::Concern

    def load_in_checklist
      @gig ||= current_company.gigs.find(params[:id])
      @gig_items = @gig.gig_items.includes(:item).order('items.name ASC')
      render layout: false
    end

    def print_contract
      render layout: false
    end

    def flashcard
      render layout: false
    end

    def stage_mode
      @gig = current_company.gigs.includes(:client, :gig_timeline_items, staff_assignments: :user, gig_items: :item).find(params[:id])
      @timeline_items = @gig.gig_timeline_items.order(position: :asc, time: :asc)
      @staff_assignments = @gig.staff_assignments.includes(:user)
      @gig_items = @gig.gig_items.includes(:item).order('items.name ASC')
      @songs = current_company.songs.where(active: true).order(genre: :asc, title: :asc) rescue []
      render layout: false
    end
  end
end
