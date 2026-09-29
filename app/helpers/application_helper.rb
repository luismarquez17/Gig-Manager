module ApplicationHelper
  def current_active_company
    current_company || (@gig.respond_to?(:company) ? @gig.company : nil) || (@client_quote.respond_to?(:company) ? @client_quote.company : nil)
  end

  def company_term(key, fallback = nil)
    comp = current_active_company
    if comp.present? && comp.respond_to?(:term_for)
      comp.term_for(key, fallback)
    else
      fallback || key.to_s.humanize
    end
  end

  def venue_mode?
    comp = current_active_company
    comp.present? && comp.respond_to?(:venue_mode?) && comp.venue_mode?
  end

  def academy_mode?
    comp = current_active_company
    comp.present? && comp.respond_to?(:academy_mode?) && comp.academy_mode?
  end

  def music_mode?
    comp = current_active_company
    return true if comp.blank?
    comp.respond_to?(:music_mode?) && comp.music_mode?
  end
end
