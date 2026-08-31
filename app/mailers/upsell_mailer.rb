class UpsellMailer < ApplicationMailer
  # Notifica al líder de la empresa que un cliente solicitó un adicional
  def new_upsell_request(upsell_request)
    @request  = upsell_request
    @gig      = upsell_request.gig
    @company  = upsell_request.company || @gig.company

    # Destinatarios: todos los líderes de la empresa
    leader_emails = @company&.users&.where(role: :leader)&.pluck(:email)&.compact
    return if leader_emails.blank?

    @gig_url = gig_url(@gig)

    mail(
      to:      leader_emails,
      subject: "🚀 #{@request.emoji.presence || '🚀'} Solicitud de adicional: #{@request.title} — #{@gig.client&.name || @gig.client_email}"
    )
  end

  # Notifica al cliente cuando se aprueba su solicitud
  def upsell_approved(upsell_request)
    @request = upsell_request
    @gig     = upsell_request.gig
    @company = upsell_request.company || @gig.company

    client_email = @gig.client&.email.presence || @gig.client_email
    return if client_email.blank?

    @portal_url = public_portal_url(token: @gig.portal_token)

    mail(
      to:      client_email,
      subject: "✅ ¡Tu adicional fue confirmado! #{@request.emoji.presence || '🚀'} #{@request.title}"
    )
  end

  # Notifica al cliente cuando se rechaza su solicitud
  def upsell_rejected(upsell_request)
    @request = upsell_request
    @gig     = upsell_request.gig
    @company = upsell_request.company || @gig.company

    client_email = @gig.client&.email.presence || @gig.client_email
    return if client_email.blank?

    @portal_url = public_portal_url(token: @gig.portal_token)

    mail(
      to:      client_email,
      subject: "❌ Solicitud de adicional no disponible — #{@request.title}"
    )
  end
end
