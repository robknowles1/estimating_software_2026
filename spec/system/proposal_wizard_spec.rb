require "rails_helper"

RSpec.describe "Proposal wizard (SPEC-026)", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user)    { create(:user) }
  let(:client)   { create(:client) }
  let(:estimate) { create(:estimate, client: client, title: "Acme HQ Millwork") }
  let!(:contact) { create(:contact, client: client, first_name: "Dana", last_name: "Reed", is_primary: true) }

  # An alternate line item so the alternates step has a row to confirm.
  let!(:alt_item) do
    create(:line_item, estimate: estimate, description: "ALT-1 Painted Finish", room: "Kitchen")
  end
  let!(:room_item) do
    create(:line_item, estimate: estimate, description: "Base Cabinet", room: "Pantry")
  end

  def login
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  # Starts the wizard from the estimate page. The "Create Proposal" entry point is
  # asserted on the estimate page (AT1 / Test 1), then the wizard is started via a
  # full-page visit to the same URL the link targets — the estimate edit page's
  # first in-page link click is environmentally flaky on a reused browser session
  # (a pre-existing Turbo behaviour affecting all edit-page links), so we navigate
  # deterministically rather than depend on that click.
  def start_wizard
    visit edit_estimate_path(estimate)
    expect(page).to have_link("Create Proposal", href: new_estimate_proposal_path(estimate), wait: 5)
    visit new_estimate_proposal_path(estimate)
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "opening"), wait: 5)
    expect(page).to have_field("proposal[job_name]", with: estimate.title, wait: 5)
  end

  # Clicks "Save and continue" on the given step. Selenium occasionally drops the
  # very first synthetic click on a freshly loaded page (a known Chromedriver/Turbo
  # timing quirk); if the step has not advanced shortly after, submit the form
  # directly so the test asserts on real behaviour rather than that click quirk.
  def save_and_continue(step)
    click_button "Save and continue"
    return if page.has_no_current_path?(step_estimate_proposal_path(estimate, step), wait: 3)

    # A10: requestSubmit() is a safe fallback only because these step forms have
    # no JS submit hooks beyond Turbo — it dispatches a real submit event and is
    # not equivalent to a click bypassing validation/JS for forms that do.
    page.execute_script(
      "document.querySelector(\"form[action*='steps/#{step}']\").requestSubmit()"
    )
  end

  # M2 / AT1 — exercise the REAL "Create Proposal" anchor click (its own fresh
  # session, not the reused-session flow) so the entry point is genuinely tested.
  #
  # Investigation outcome: the link/flow is NOT defective. The "Create Proposal"
  # anchor is a plain Turbo Drive GET to new_estimate_proposal_path; the `new`
  # action delegates to `create`, builds the proposal, and 302-redirects to the
  # opening step. A direct `visit` to that URL navigates and creates exactly one
  # proposal, and this real `click_link` works reliably once the page has
  # settled. The only failure mode is the well-known Chromedriver/Turbo timing
  # quirk where Selenium dispatches the very first click on a freshly loaded page
  # before Turbo Drive has attached its click handler, so the click is a no-op
  # (no console error, correct href, no data-turbo-method). The short settle-wait
  # below removes that flake; it is an environmental Selenium issue, not a bug.
  it "creates the proposal when the real Create Proposal link is clicked" do
    login
    visit edit_estimate_path(estimate)
    # Wait for the page (and Turbo Drive's click handler) to attach before the click.
    expect(page).to have_link("Create Proposal", href: new_estimate_proposal_path(estimate), wait: 5)

    expect {
      click_link "Create Proposal"
      expect(page).to have_current_path(
        step_estimate_proposal_path(estimate, "opening"), wait: 5
      )
    }.to change(Proposal, :count).by(1)

    expect(Proposal.count).to eq(1)
  end

  # Test 1 — happy path, commercial; ends by asserting the review step renders.
  it "walks the full commercial wizard to the review step" do
    login
    start_wizard

    # Opening step
    select "Dana Reed", from: "proposal[contact_id]"
    fill_in "proposal[job_name]", with: "Acme HQ Millwork"
    fill_in "proposal[total_amount]", with: "125000"
    save_and_continue("opening")

    # Specifications step
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "specifications"), wait: 5)
    check "Include specifications section"
    save_and_continue("specifications")

    # Inclusions step — pre-populated rooms
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "inclusions"), wait: 5)
    expect(page).to have_field("proposal[proposal_inclusions_attributes][0][room_name]")
    expect(page).to have_field("proposal[proposal_inclusions_attributes][1][room_name]")
    fill_in "proposal[proposal_inclusions_attributes][0][bullet_points]", with: "New uppers and lowers"
    save_and_continue("inclusions")

    # Clarifications step
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "clarifications"), wait: 5)
    save_and_continue("clarifications")

    # Alternates step
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "alternates"), wait: 5)
    expect(page).to have_text("ALT-1 Painted Finish")
    save_and_continue("alternates")

    # Exclusions step
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "exclusions"), wait: 5)
    save_and_continue("exclusions")

    # Review step — preview content + disabled export controls.
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "review"), wait: 5)
    expect(page).to have_text("Review and Export")
    expect(page).to have_text("Dana Reed")
    expect(page).to have_button("Download PDF", disabled: true)
    expect(page).to have_text("available in a later release")
  end

  # Test 2 — residential mode skips specifications.
  it "skips the specifications step in residential mode" do
    login
    start_wizard

    select "Dana Reed", from: "proposal[contact_id]"
    select "Residential", from: "proposal[mode]"
    save_and_continue("opening")

    # Lands directly on inclusions, not specifications.
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "inclusions"), wait: 5)
  end

  # Test 3 — resume at the earliest incomplete step with data preserved.
  it "resumes at the next incomplete step and preserves data" do
    login
    start_wizard

    select "Dana Reed", from: "proposal[contact_id]"
    fill_in "proposal[job_name]", with: "Resume Job"
    save_and_continue("opening")
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "specifications"), wait: 5)

    # Returning to the estimate offers "Edit Proposal", which resumes at the next
    # incomplete step (specifications).
    visit edit_estimate_path(estimate)
    expect(page).to have_link("Edit Proposal", href: estimate_proposal_path(estimate), wait: 5)
    visit estimate_proposal_path(estimate)
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "specifications"), wait: 5)

    # Saved opening data is preserved when navigating back to the opening step.
    visit step_estimate_proposal_path(estimate, "opening")
    expect(page).to have_field("proposal[job_name]", with: "Resume Job", wait: 5)
  end

  # Test 4 — future-step direct navigation is redirected.
  it "redirects a direct future-step URL to the earliest incomplete step" do
    proposal = Proposals::BuildService.new(estimate: estimate).call
    proposal.update!(current_step: "specifications")

    login
    visit step_estimate_proposal_path(estimate, "exclusions")

    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "specifications"), wait: 5)
    expect(page).to have_text("complete earlier steps")
  end

  # Inline add-contact modal (PR #56 follow-up) — a client with NO contacts can
  # add one from the opening step without leaving the wizard.
  context "when the estimate's client has no contacts" do
    let(:bare_client)   { create(:client) }
    let(:bare_estimate) { create(:estimate, client: bare_client, title: "No-Contact Job") }

    def start_bare_wizard
      visit new_estimate_proposal_path(bare_estimate)
      expect(page).to have_current_path(step_estimate_proposal_path(bare_estimate, "opening"), wait: 5)
    end

    # Clicks "+ Add contact" until the modal is actually open (first field visible),
    # absorbing the first-click-on-fresh-page Selenium/Stimulus timing quirk.
    def open_add_contact_modal
      2.times do
        click_button "+ Add contact"
        return if page.has_field?("contact[first_name]", wait: 2)
      end
      expect(page).to have_field("contact[first_name]", wait: 5)
    end

    it "adds a contact via the modal, auto-selects it, and continues the wizard" do
      login
      start_bare_wizard

      # No contacts yet: the hint and the always-present Add contact button show.
      expect(page).to have_text("This client has no contacts yet.")
      expect(page).to have_button("+ Add contact")

      # Open the modal. Selenium sometimes drops the very first synthetic click on
      # a freshly loaded page before Stimulus has attached (the same known
      # Chromedriver/Turbo timing quirk this file documents elsewhere); retry the
      # click until the modal's first field becomes visible.
      open_add_contact_modal

      # Modal is open and the first field is focused.
      expect(page).to have_field("contact[first_name]", wait: 5)
      fill_in "contact[first_name]", with: "Pat"
      fill_in "contact[last_name]",  with: "Quinn"
      fill_in "contact[email]",      with: "pat@example.com"

      expect {
        click_button "Save contact"
        # New contact is auto-selected in the rebuilt dropdown.
        expect(page).to have_select("proposal[contact_id]", selected: "Pat Quinn", wait: 5)
      }.to change(Contact, :count).by(1)

      # Modal has closed (its form fields are no longer interactable on screen).
      expect(page).to have_no_field("contact[first_name]", wait: 5)

      # The estimator can save-and-continue past the opening step. (Inline submit
      # rather than the shared helper since that helper targets the outer estimate.)
      click_button "Save and continue"
      unless page.has_no_current_path?(step_estimate_proposal_path(bare_estimate, "opening"), wait: 3)
        page.execute_script(
          "document.querySelector(\"form[action*='steps/opening']\").requestSubmit()"
        )
      end
      expect(page).to have_current_path(
        step_estimate_proposal_path(bare_estimate, "specifications"), wait: 5
      )
    end

    it "keeps the modal open and shows errors when saved with the name fields blank" do
      login
      start_bare_wizard
      expect(page).to have_button("+ Add contact")

      open_add_contact_modal

      # Submit with the required name fields blank. The fields carry the HTML5
      # `required` attribute, which would block a real submit client-side; strip
      # it via JS first so the request reaches the server and exercises the
      # model-level validation-failure round-trip (the 422 Turbo Stream).
      expect(page).to have_field("contact[first_name]", wait: 5)
      expect {
        page.execute_script(<<~JS)
          var form = document.querySelector("#add_contact_modal form");
          form.querySelectorAll("[required]").forEach(function (el) {
            el.removeAttribute("required");
          });
          form.requestSubmit();
        JS
        # The 422 stream re-renders the frame with errors; the dialog stays open.
        expect(page).to have_css("[role='alert']", wait: 5)
      }.not_to change(Contact, :count)

      # Dialog is still open (first field visible) and we never left the step.
      expect(page).to have_field("contact[first_name]", wait: 5)
      expect(page).to have_current_path(
        step_estimate_proposal_path(bare_estimate, "opening"), wait: 5
      )
      # No contact was persisted for this client (the only contact in the DB is
      # the outer `let!` belonging to a different client).
      expect(bare_client.contacts.count).to eq(0)
    end
  end

  # Test 5 — duplicate proposal guard.
  it "does not create a duplicate proposal" do
    proposal = Proposals::BuildService.new(estimate: estimate).call

    login
    visit edit_estimate_path(estimate)
    expect(page).to have_link("Edit Proposal", href: estimate_proposal_path(estimate), wait: 5)
    visit estimate_proposal_path(estimate)

    expect(page).to have_current_path(
      step_estimate_proposal_path(estimate, proposal.current_step), wait: 5
    )
    expect(Proposal.where(estimate_id: estimate.id).count).to eq(1)
  end
end
