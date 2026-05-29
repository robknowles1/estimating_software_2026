require "rails_helper"

RSpec.describe "Client and Contact Management", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user) { create(:user) }

  def login(as: user, password: "password123")
    visit new_session_path
    fill_in "Email", with: as.email
    fill_in "Password", with: password
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  # Strips data-turbo-confirm from all elements and clicks the button via
  # JavaScript rather than a Selenium CDP click.  The CDP click path has a
  # Chrome 148 headless-mode bug where the synthetic trusted click sometimes
  # misses the hit-test for the target element and is silently swallowed,
  # leaving the submit event unfired.  A JS-dispatched click (isTrusted=false)
  # is not subject to the coordinate hit-test and always reaches the element.
  #
  # The tests that use this helper are exercising server-side behaviour
  # (blocked vs. successful deletion), not the dialog or click trust level
  # itself, so bypassing both is an acceptable trade-off.
  def confirm_and_click(button_text)
    page.execute_script(<<~JS, button_text)
      var text = arguments[0];
      window.confirm = function() { return true; };
      document.querySelectorAll('[data-turbo-confirm]').forEach(function(el) {
        el.removeAttribute('data-turbo-confirm');
      });
      var buttons = Array.prototype.slice.call(document.querySelectorAll('button[type="submit"], input[type="submit"]'));
      var target = buttons.find(function(b) {
        return (b.value || b.textContent || '').trim() === text;
      });
      if (target) { target.click(); }
    JS
  end

  def wait_for_js
    expect(page).to have_css("html[data-js-ready='true']", wait: 5)
  end

  describe "primary contact badge" do
    it "shows Primary badge only on the primary contact" do
      client = create(:client, company_name: "Prestige Cabinets")
      create(:contact, client: client, first_name: "Alice", last_name: "Smith", is_primary: false)
      create(:contact, client: client, first_name: "Bob",   last_name: "Jones", is_primary: true)

      login
      visit client_path(client)

      within("table tbody") do
        expect(find("tr", text: "Bob Jones")).to have_text("Primary")
        expect(find("tr", text: "Alice Smith")).not_to have_text("Primary")
      end
    end
  end

  describe "blocked client deletion" do
    it "shows block message and preserves client when estimates exist" do
      login

      client = create(:client, company_name: "Locked Client Co")
      create(:estimate, client: client)

      visit client_path(client)
      expect(page).to have_text("Locked Client Co")
      wait_for_js
      confirm_and_click "Delete"

      expect(page).to have_current_path(client_path(client), wait: 5)
      expect(page).to have_css("[role='alert']", wait: 10)
      expect(page).to have_text("Cannot delete", wait: 10)
      expect(Client.find_by(id: client.id)).to be_present
    end

    it "deletes client successfully when no estimates exist" do
      login

      client = create(:client, company_name: "Removable Client Co")

      visit client_path(client)
      expect(page).to have_text("Removable Client Co")
      wait_for_js
      confirm_and_click "Delete"

      expect(page).to have_current_path(clients_path, wait: 5)
      expect(page).not_to have_text("Removable Client Co")
    end
  end
end
