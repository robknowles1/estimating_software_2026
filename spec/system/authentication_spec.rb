require 'rails_helper'

RSpec.describe "Authentication", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user) { create(:user, name: "Alice Smith", email: "alice@example.com", password: "password123", password_confirmation: "password123") }

  it "full login/logout flow" do
    # Visit protected page without being logged in — redirected to login
    visit estimates_path
    expect(page).to have_current_path(new_session_path)
    expect(page).to have_field("Email")
    expect(page).to have_field("Password")

    # Log in with valid credentials
    fill_in "Email", with: "alice@example.com"
    fill_in "Password", with: "password123"
    click_button "Sign In"

    # Landed on estimates dashboard
    expect(page).to have_current_path(estimates_path)
    expect(page).to have_text("Alice Smith")

    # Log out
    click_button "Log Out"
    expect(page).to have_current_path(new_session_path)

    # Cannot access protected page again
    visit estimates_path
    expect(page).to have_current_path(new_session_path)
  end
end
