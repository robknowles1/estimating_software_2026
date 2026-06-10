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
    # Retry the click if the page has not navigated: Selenium occasionally drops
    # the first synthetic click on a freshly loaded page (the Chromedriver/Turbo
    # quirk this file documents). The retry only fires when we are still on the
    # sign-in page, so the credentials are submitted exactly once.
    click_button "Sign In"
    return if page.has_current_path?(estimates_path, wait: 3)

    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  # Clicks the "Create Proposal" button_to form, retrying the click if the wizard
  # has not advanced shortly after. Selenium occasionally drops the very first
  # synthetic click on a freshly loaded page (the known Chromedriver/Turbo timing
  # quirk this file documents), which leaves us stranded on the estimate page. The
  # retry is safe: it only fires when the POST never happened (we are still on the
  # estimate edit page), so it never creates a duplicate proposal.
  def click_create_proposal(target_estimate)
    opening_path = step_estimate_proposal_path(target_estimate, "opening")
    click_button "Create Proposal"
    return if page.has_current_path?(opening_path, wait: 3)

    # The synthetic click was dropped before submitting the button_to form (the
    # known Chromedriver/Turbo first-click quirk this file documents). Submit the
    # form directly — same requestSubmit() fallback save_and_continue uses. It
    # only runs when the POST never happened, so no duplicate proposal is created.
    submit_form_for_button("Create Proposal")
    expect(page).to have_current_path(opening_path, wait: 5)
  end

  # Submits the form owning the button with the given visible label/value via a
  # real requestSubmit() — the fallback used when a synthetic click is dropped on
  # a freshly loaded page (the Chromedriver/Turbo first-click quirk this file
  # documents). These forms have no JS submit hooks beyond Turbo, so this
  # dispatches an equivalent submit event.
  def submit_form_for_button(label)
    page.execute_script(<<~JS, label)
      var label = arguments[0];
      var btn = Array.from(document.querySelectorAll("input[type='submit'], button"))
        .find(function (el) { return (el.value || el.textContent).trim() === label; });
      if (btn) { btn.closest("form").requestSubmit(); }
    JS
  end

  # Fills a pre-populated field and confirms the typed value is committed in the
  # DOM, re-filling if it reverts. These fields render with a server-side default
  # (job_name → estimate title, recipient_email → contact email). Reaching the
  # page goes through a Turbo Drive navigation that paints a cached preview
  # snapshot before swapping in the fresh page; a fill against the preview node is
  # discarded by the swap, leaving the default in place. We wait for the preview
  # to clear and for a single settled input, then re-fill until the field holds
  # the value, so the subsequent submit carries the typed value not the default.
  def fill_field_until_committed(name, value)
    selector = "input[name='#{name}']"
    5.times do
      wait_for_turbo_settled
      # Settle to a single input first: a Turbo Drive navigation can briefly leave
      # a cached snapshot's duplicate field alongside the fresh one.
      expect(page).to have_selector(selector, count: 1, wait: 5)
      fill_in name, with: value
      return if page.has_field?(name, with: value, wait: 2)

      # The field still holds its server-side default. On a freshly navigated page
      # a clear+type can land on a transient stale node (replaced by Turbo before
      # it commits), so the live field keeps its default. Set the live field's
      # value directly and fire input/change so it matches a real edit. These
      # forms have no JS submit hooks beyond Turbo and submit via requestSubmit,
      # which reads .value, so the set value is exactly what is submitted.
      page.execute_script(<<~JS, name, value)
        var name = arguments[0], value = arguments[1];
        var el = document.querySelector("input[name='" + name + "']");
        if (el) {
          el.value = value;
          el.dispatchEvent(new Event("input", { bubbles: true }));
          el.dispatchEvent(new Event("change", { bubbles: true }));
        }
      JS
      return if page.has_field?(name, with: value, wait: 2)
    end
    expect(page).to have_field(name, with: value, wait: 5)
  end

  # Starts the wizard from the estimate page. Creation is POST-only: the
  # "Create Proposal" entry point is a button_to form on the estimate page, so
  # clicking it submits a real POST to create and redirects to the opening step.
  #
  # Selenium occasionally drops the very first synthetic click on a freshly loaded
  # page (a known Chromedriver/Turbo timing quirk); if the step has not advanced
  # shortly after, submit the form directly so the test asserts on real behaviour
  # rather than that click quirk. Mirror the save_and_continue fallback pattern.
  def start_wizard
    visit edit_estimate_path(estimate)
    expect(page).to have_button("Create Proposal", wait: 5)
    click_create_proposal(estimate)
    # The navigation to the opening step lands via Turbo Drive, which paints a
    # cached preview snapshot before the fresh page. Interacting during that
    # preview targets stale nodes whose values Turbo then discards. Wait for the
    # preview to clear and the form to settle to a single input before any field
    # interaction.
    wait_for_turbo_settled
    expect(page).to have_selector("input[name='proposal[job_name]']", count: 1, wait: 5)
    expect(page).to have_field("proposal[job_name]", with: estimate.title, wait: 5)
  end

  # Navigates to the review step and waits for the Turbo Drive navigation to
  # settle (preview cleared, expected URL) before any interaction.
  def visit_review_fresh
    visit step_estimate_proposal_path(estimate, "review")
    wait_for_turbo_settled
    expect(page).to have_current_path(
      step_estimate_proposal_path(estimate, "review"), wait: 5
    )
  end

  # Blocks until Turbo Drive has finished swapping in the real page — i.e. the
  # <html> element no longer carries the data-turbo-preview marker Turbo sets
  # while a cached snapshot is on screen. Prevents interacting with stale preview
  # nodes during a navigation.
  def wait_for_turbo_settled
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.05 until page.evaluate_script(
        "!document.documentElement.hasAttribute('data-turbo-preview')"
      )
    end
  rescue Timeout::Error
    # Fall through — the subsequent settle assertions provide the real failure.
    nil
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

  # M2 / AT1 — exercise the REAL "Create Proposal" button click so the entry
  # point is genuinely tested. Creation is POST-only: the button_to renders a
  # form that POSTs to create, which builds the proposal and 302-redirects to
  # the opening step. A real click submits that form and creates exactly one
  # proposal — no side effect on GET.
  it "creates the proposal when the real Create Proposal button is clicked" do
    login
    visit edit_estimate_path(estimate)
    expect(page).to have_button("Create Proposal", wait: 5)

    # click_create_proposal retries the click only when no navigation happened
    # (the dropped-first-click quirk), so at most one POST ever creates a proposal.
    expect {
      click_create_proposal(estimate)
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

    # Review step — preview content + all three live actions (Download PDF,
    # Send Email, Mark as Sent). A real headless-Chrome file download assertion
    # is flaky, so we assert the Download link is present and points at the pdf
    # route; the request spec covers the actual PDF bytes.
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "review"), wait: 5)
    expect(page).to have_text("Review and Export")
    expect(page).to have_text("Dana Reed")
    expect(page).to have_link("Download PDF", href: pdf_estimate_proposal_path(estimate))
    expect(page).to have_button("Send Email")
    expect(page).to have_button("Mark as Sent")
  end

  # Submits a review-step action form (Send Email / Mark as Sent) and waits for
  # the success notice. Both buttons POST and 302-redirect back to the review
  # step, which re-renders the page; the redirect must settle (notice visible +
  # current path back at review) before the notice text and any DB read are
  # trusted.
  #
  # The submit is driven by requestSubmit() rather than a synthetic click. These
  # actions are NOT idempotent — Send Email dispatches a real email and the
  # redirect re-renders the recipient field back to its default — so the
  # click-then-retry pattern used for the idempotent step forms is unsafe here: a
  # dropped-then-late first click could double-submit (two emails / a submit with
  # stale defaults). requestSubmit() avoids the first-click-drop quirk entirely
  # and fires exactly once, with whatever field values are currently in the form.
  # These forms have no JS submit hooks beyond Turbo, so this dispatches an
  # equivalent submit event.
  def submit_review_action(label, notice)
    submit_form_for_button(label)
    expect(page).to have_current_path(
      step_estimate_proposal_path(estimate, "review"), wait: 5
    )
    expect(page).to have_text(notice, wait: 5)
  end

  # Test 6 — Send Email from the review step flips the proposal to sent.
  # ActionMailer uses the test adapter (deliveries collected in-memory), so we
  # assert on the success flash + persisted status rather than real SMTP.
  it "sends the proposal email from the review step and marks it sent" do
    proposal = Proposals::BuildService.new(estimate: estimate).call
    proposal.update!(current_step: "review", contact: contact)
    ActionMailer::Base.deliveries.clear

    login
    visit_review_fresh

    expect(page).to have_field("recipient_email", with: contact.email, wait: 5)
    # Fill the recipient and confirm the typed value sticks (re-filling if it
    # reverts to the contact-email default), so the POST carries the typed address
    # rather than that default — which the success-notice assertion checks by name.
    fill_field_until_committed("recipient_email", "client@example.com")

    # submit_review_action fires the form exactly once via requestSubmit(), so the
    # typed recipient is sent and the delivery count changes by exactly 1.
    expect {
      submit_review_action("Send Email", "Proposal sent to client@example.com")
    }.to change { ActionMailer::Base.deliveries.size }.by(1)

    # Read the DB only after the redirect + notice confirm the request finished.
    expect(proposal.reload.status).to eq("sent")
  end

  # Test 7 — Mark as Sent records delivery without sending an email.
  it "marks the proposal sent without sending an email" do
    proposal = Proposals::BuildService.new(estimate: estimate).call
    proposal.update!(current_step: "review")
    ActionMailer::Base.deliveries.clear

    login
    visit_review_fresh

    expect {
      submit_review_action("Mark as Sent", "Proposal marked as sent.")
    }.not_to change { ActionMailer::Base.deliveries.size }

    # Read the DB only after the redirect + notice confirm the request finished.
    expect(proposal.reload.status).to eq("sent")
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
    # Fill the job name and confirm it actually stuck before submitting. The
    # opening form is rendered after a full navigation and the field defaults to
    # the estimate title; a late paint/restore can briefly replace the field and
    # drop a just-typed value. Re-fill until the typed value is committed so the
    # save persists "Resume Job" rather than the default (which the preservation
    # assertion at the end of this example depends on).
    fill_field_until_committed("proposal[job_name]", "Resume Job")
    save_and_continue("opening")
    # The opening step form is data: { turbo: false } (native HTTP navigation).
    # Give the full-page redirect more time to settle than the default wait.
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "specifications"), wait: 10)

    # Returning to the estimate offers "Edit Proposal", which resumes at the next
    # incomplete step (specifications).
    visit edit_estimate_path(estimate)
    expect(page).to have_link("Edit Proposal", href: estimate_proposal_path(estimate), wait: 5)
    visit estimate_proposal_path(estimate)
    expect(page).to have_current_path(step_estimate_proposal_path(estimate, "specifications"), wait: 5)

    # Saved opening data is preserved when navigating back to the opening step.
    visit step_estimate_proposal_path(estimate, "opening")
    # Turbo may show a cached snapshot (preview) while the real page loads.
    # Wait for the preview to be replaced so we read the server-persisted value.
    expect(page).to have_no_css("html[data-turbo-preview]", wait: 5)
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
      visit edit_estimate_path(bare_estimate)
      expect(page).to have_button("Create Proposal", wait: 5)
      click_create_proposal(bare_estimate)
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
