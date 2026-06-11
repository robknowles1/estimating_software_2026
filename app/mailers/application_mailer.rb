class ApplicationMailer < ActionMailer::Base
  # Project sending address. Read first from encrypted credentials, then the
  # COMPANY_EMAIL env var, falling back to a placeholder.
  #
  # TODO: confirm the real sending address with Blake and wire production SMTP
  # (delivery settings are environment/devops config — see SPEC-026 PR 5 note).
  default from: Rails.application.credentials.dig(:company, :email).presence ||
                ENV["COMPANY_EMAIL"].presence ||
                "proposals@example.com"
  layout "mailer"
end
