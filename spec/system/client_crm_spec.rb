require "rails_helper"

RSpec.describe "Client CRM", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user) { create(:user) }

  def login(as: user, password: "password123")
    visit new_session_path
    fill_in "Email", with: as.email
    fill_in "Password", with: password
    # Submit the (turbo:false) login form via requestSubmit() rather than a
    # Selenium click.  In headless Chrome 148 a synthetic click is sometimes
    # swallowed by the hit-test, leaving the form unsubmitted and the spec
    # stranded on /session/new.  Driving the form node directly is reliable.
    page.execute_script("document.querySelector(\"input[type='password']\").form.requestSubmit();")
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  def wait_for_js
    expect(page).to have_css("html[data-js-ready='true']", wait: 5)
  end

  # See spec/system/clients_spec.rb for the rationale: a JS-dispatched click
  # avoids the Chrome 148 headless hit-test bug and the turbo-confirm dialog,
  # which we are not exercising here.
  def confirm_and_click(button_text, scope: "")
    page.execute_script(<<~JS, button_text, scope)
      var text = arguments[0];
      var scope = arguments[1];
      window.confirm = function() { return true; };
      document.querySelectorAll('[data-turbo-confirm]').forEach(function(el) {
        el.removeAttribute('data-turbo-confirm');
      });
      var selector = (scope ? scope + ' ' : '') + 'button[type="submit"], ' + (scope ? scope + ' ' : '') + 'input[type="submit"]';
      var buttons = Array.prototype.slice.call(document.querySelectorAll(selector));
      var target = buttons.find(function(b) {
        return (b.value || b.textContent || '').trim() === text;
      });
      if (target) { target.click(); }
    JS
  end

  describe "adding a role to a contact" do
    it "shows the role in the contacts table" do
      client  = create(:client, company_name: "Acme GC")
      contact = create(:contact, client: client, first_name: "Pat", last_name: "Smith", role: nil)

      login
      visit edit_client_contact_path(client, contact)

      fill_in "Role", with: "estimator"
      # Use requestSubmit() to avoid the Chrome 148 headless hit-test bug where
      # a synthetic click on the submit input is sometimes swallowed.
      page.execute_script("document.querySelector(\"input[type='submit'][value='Update Contact']\").form.requestSubmit();")

      expect(page).to have_current_path(client_path(client), wait: 5)
      within("table tbody") do
        expect(find("tr", text: "Pat Smith")).to have_text("estimator")
      end
      expect(contact.reload.role).to eq("estimator")
    end
  end

  describe "adding a note" do
    it "appears in the timeline with a timestamp" do
      client = create(:client, company_name: "Beta Builders")

      login
      visit client_path(client)
      wait_for_js

      # Set the body and submit the form via requestSubmit() in one JS call.
      # In headless Chrome 148 a Selenium set + click intermittently lets the
      # form POST a blank body (the reloaded page shows "No notes yet"): the
      # synthetic click can fire while Turbo is mid-restoring a cached snapshot
      # whose form is still empty.  Setting the value and submitting the same
      # form node atomically removes that race.  The test exercises the
      # server-side create, not the typing/click mechanics.
      page.execute_script(<<~JS)
        var field = document.querySelector("textarea[name='client_note[body]']");
        field.value = "Called Blake re: bid deadline";
        field.dispatchEvent(new Event("input", { bubbles: true }));
        field.form.requestSubmit();
      JS

      expect(page).to have_current_path(client_path(client), wait: 5)
      expect(page).to have_text("Called Blake re: bid deadline", wait: 5)
      # Timestamp formatted as "Mon D, YYYY h:MM AM/PM" — assert the year is present.
      expect(page).to have_text(Date.current.year.to_s)
      expect(client.client_notes.count).to eq(1)
    end
  end

  describe "submitting a blank note" do
    it "shows an inline error and adds no note" do
      client = create(:client, company_name: "Gamma Group")

      login
      visit client_path(client)
      wait_for_js

      # Submit the empty form via requestSubmit() for the same reason as the
      # add-note test: a synthetic Selenium click can be swallowed mid Turbo
      # cache restore in headless Chrome 148, leaving no POST and no error.
      page.execute_script(<<~JS)
        document.querySelector("textarea[name='client_note[body]']").form.requestSubmit();
      JS

      expect(page).to have_css("[role='alert']", wait: 5)
      expect(page).to have_text("can't be blank", wait: 5)
      # Other panels are still rendered.
      expect(page).to have_text("Contacts")
      expect(page).to have_text("Estimates")
      expect(client.client_notes.count).to eq(0)
    end
  end

  describe "deleting a note" do
    it "removes the note from the timeline after confirmation" do
      client = create(:client, company_name: "Delta Drywall")
      create(:client_note, client: client, body: "Note to be deleted")

      login
      visit client_path(client)
      wait_for_js
      expect(page).to have_text("Note to be deleted")

      # Scope to the notes list so we hit the note's Delete button, not the
      # client header's Delete button (both share the label "Delete").
      confirm_and_click "Delete", scope: "ul li"

      expect(page).to have_current_path(client_path(client), wait: 5)
      expect(page).to have_no_text("Note to be deleted", wait: 5)
      expect(client.client_notes.count).to eq(0)
      expect(Client.find_by(id: client.id)).to be_present
    end
  end

  describe "estimates panel" do
    it "shows estimate rows linking to the edit page" do
      client = create(:client, company_name: "Epsilon Electric")
      big    = create(:estimate, client: client, title: "Big Job", status: "draft")
      create(:estimate, client: client, title: "Small Job", status: "sent")

      login
      visit client_path(client)
      wait_for_js

      expect(page).to have_text("Big Job")
      expect(page).to have_text("Small Job")
      expect(page).to have_text(big.estimate_number)

      click_link "Big Job"
      expect(page).to have_current_path(edit_estimate_path(big), wait: 5)
    end

    it "shows an empty-state message when there are no estimates" do
      client = create(:client, company_name: "Zeta Framing")

      login
      visit client_path(client)
      wait_for_js

      expect(page).to have_text("No estimates have been bid to this client yet")
    end
  end
end
