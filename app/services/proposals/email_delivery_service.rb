module Proposals
  # Validates a recipient address, renders the proposal PDF, and delivers it via
  # ProposalMailer (R15 / AC-25). Validation runs BEFORE any PDF render or mailer
  # work so a bad address never triggers expensive rendering or a partial send.
  #
  # A blank / malformed / header-injection address raises ArgumentError (the
  # controller maps it to a 422 — E9 / AT15 / AC-26). A failure during render or
  # delivery is rescued and returned as a Result with success: false so the
  # controller can surface a flash without a 500.
  class EmailDeliveryService
    Result = Data.define(:success, :error)

    # Reject any address containing characters that could inject extra mail
    # headers (CR, LF) or smuggle additional recipients (`;`).
    HEADER_INJECTION_CHARS = /[\r\n;]/

    def initialize(proposal:, recipient_email:)
      @proposal = proposal
      @recipient_email = recipient_email.to_s
    end

    # @return [Result] success:/error: struct.
    # @raise [ArgumentError] if recipient_email is blank/invalid/injection-laden.
    def call
      validate_recipient!

      pdf = Proposals::PdfRenderService.new(proposal: @proposal).call
      ProposalMailer.proposal_email(
        proposal: @proposal,
        recipient_email: @recipient_email,
        pdf_binary: pdf
      ).deliver_now

      Result.new(success: true, error: nil)
    rescue ArgumentError
      # A bad address is a client error (422) — let it propagate to the
      # controller rather than swallowing it into a generic failure Result.
      raise
    rescue StandardError => e
      Rails.logger.error("[Proposals::EmailDeliveryService] #{e.class}: #{e.message}")
      Result.new(success: false, error: e.message)
    end

    private

    def validate_recipient!
      raise ArgumentError, "recipient_email is blank" if @recipient_email.blank?

      if @recipient_email.match?(HEADER_INJECTION_CHARS)
        raise ArgumentError, "recipient_email contains illegal characters"
      end

      unless @recipient_email.match?(URI::MailTo::EMAIL_REGEXP)
        raise ArgumentError, "recipient_email is not a valid email address"
      end
    end
  end
end
