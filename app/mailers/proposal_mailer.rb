class ProposalMailer < ApplicationMailer
  # Delivers the proposal PDF to a recipient (R15 / AC-25). The PDF binary is
  # built by Proposals::EmailDeliveryService (which validates the recipient
  # address before any mailer work) and passed in here, so this mailer is a thin
  # assembler with no PDF-render or validation responsibility.
  #
  # The body deliberately avoids URL helpers that require default_url_options /
  # host config — there are no links — so no mailer host setup is needed.
  def proposal_email(proposal:, recipient_email:, pdf_binary:)
    @proposal = proposal
    @first_name = proposal.contact&.first_name.presence

    attachments["proposal.pdf"] = {
      mime_type: "application/pdf",
      content: pdf_binary
    }

    mail(
      to: recipient_email,
      subject: t("proposals.mailer.proposal_email.subject", job_name: job_name)
    )
  end

  private

  def job_name
    @proposal.job_name.presence || @proposal.estimate.title
  end
end
