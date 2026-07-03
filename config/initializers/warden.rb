Warden::Manager.after_authentication do |user, auth, opts|
  if user.respond_to?(:associate_and_claim_gigs)
    user.associate_and_claim_gigs
  end
end
