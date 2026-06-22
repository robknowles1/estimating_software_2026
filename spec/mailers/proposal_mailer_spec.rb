require "rails_helper"

RSpec.describe ProposalMailer, type: :mailer do
  let(:client)   { create(:client) }
  let(:estimate) { create(:estimate, client: client, title: "Acme HQ Millwork") }
  let(:contact)  { create(:contact, client: client, first_name: "Dana", last_name: "Reed") }
  let(:proposal) { create(:proposal, estimate: estimate, contact: contact, job_name: "Acme HQ Millwork") }
  let(:pdf_binary) { "%PDF-1.4 fake pdf bytes" }

  subject(:mail) do
    described_class.proposal_email(
      proposal: proposal,
      recipient_email: "client@example.com",
      pdf_binary: pdf_binary
    )
  end

  it "addresses the email to the recipient" do
    expect(mail.to).to eq([ "client@example.com" ])
  end

  it "sets the subject from the i18n key with the job name" do
    expect(mail.subject).to eq(I18n.t("proposals.mailer.proposal_email.subject", job_name: "Acme HQ Millwork"))
  end

  it "attaches the PDF as proposal.pdf with an application/pdf mime type" do
    attachment = mail.attachments.find { |a| a.filename == "proposal.pdf" }

    expect(attachment).to be_present
    expect(attachment.content_type).to include("application/pdf")
    expect(attachment.body.raw_source).to be_present
  end

  it "greets the contact by first name in the body" do
    expect(mail.body.encoded).to include("Dana")
  end

  it "renders the boilerplate body copy (guards against a translation-path regression)" do
    body = I18n.t("proposals.mailer.proposal_email.body")

    expect(body).to include("proposal attached")
    expect(mail.body.encoded).to include("proposal attached")
    expect(mail.body.encoded).not_to include("Translation missing")
  end
end
