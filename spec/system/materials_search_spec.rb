require "rails_helper"

RSpec.describe "Materials library search and pagination (SPEC-024)", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user) { create(:user) }

  def login
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  # AT1 (AC-1, AC-2, AC-3): No pagination with <= 20; pagination appears at 21
  describe "AT1: pagination threshold" do
    context "when there are 20 or fewer active materials" do
      before do
        10.times { |i| create(:material, name: "Board #{i.to_s.rjust(2, '0')}") }
      end

      it "shows all rows and no pagination controls" do
        login
        visit materials_path
        expect(page).to have_text("Board 00")
        expect(page).not_to have_css("nav.pagy")
      end
    end

    context "when there are 21 active materials" do
      before do
        21.times { |i| create(:material, name: "Panel #{i.to_s.rjust(2, '0')}") }
      end

      it "shows pagination controls and only 20 rows on page 1" do
        login
        visit materials_path
        expect(page).to have_css("nav.pagy", wait: 3)
        rows = page.all("tbody tr")
        expect(rows.count).to eq(20)
      end
    end
  end

  # AT2 (AC-4, AC-6): Search filters rows; clear restores all
  describe "AT2: search and clear" do
    before do
      create(:material, name: "Maple Plywood", description: "Top grade maple")
      create(:material, name: "Oak Veneer",    description: "Hardwood veneer")
    end

    it "shows only matching rows after searching and restores all after clearing" do
      login
      visit materials_path

      fill_in "q", with: "maple"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_text("Maple Plywood", wait: 3)
      expect(page).not_to have_text("Oak Veneer")
      expect(current_url).to include("q=maple")

      click_link "Clear"

      expect(page).to have_text("Maple Plywood", wait: 3)
      expect(page).to have_text("Oak Veneer")
      expect(current_url).not_to include("q=")
    end
  end

  # AT3 (AC-5): Search term preserved across pages
  describe "AT3: search term preserved on page 2" do
    before do
      25.times { |i| create(:material, name: "Plywood Sheet #{i.to_s.rjust(2, '0')}") }
    end

    it "shows page 2 results with search term still in the input" do
      login
      visit materials_path

      fill_in "q", with: "plywood"
      click_button "Search materials"

      expect(page).to have_css("nav.pagy", wait: 3)

      # Navigate to page 2 via the pagination link
      within("nav.pagy") do
        click_link "2"
      end

      expect(page).to have_field("q", with: "plywood", wait: 3)
      expect(current_url).to include("q=plywood")
      expect(current_url).to include("page=2")
    end
  end

  # AT4 (AC-7): Empty state shown for no-match search
  describe "AT4: empty state for no results" do
    it "displays the empty state message when no materials match the search" do
      login
      visit materials_path

      fill_in "q", with: "zzznotfound"
      click_button "Search materials"

      expect(page).to have_text("No materials matched your search.", wait: 3)
      expect(page).not_to have_css("table")
    end
  end

  # AT5 (AC-8): "New Material" button visible after search
  describe "AT5: header remains visible after search" do
    before { create(:material, name: "Walnut Plank") }

    it "shows the New Material button after a search" do
      login
      visit materials_path

      fill_in "q", with: "walnut"
      click_button "Search materials"

      expect(page).to have_link("New Material", wait: 3)
    end
  end

  # AT6 (AC-10): URL contains ?q= after search
  describe "AT6: search term in URL" do
    before { create(:material, name: "Maple Board") }

    it "includes the q param in the URL after searching" do
      login
      visit materials_path

      fill_in "q", with: "maple"
      click_button "Search materials"

      expect(page).to have_text("Maple Board", wait: 3)
      expect(current_url).to include("q=maple")
    end
  end

  # AT7 (AC-11): Overflow page redirects to last valid page
  describe "AT7: out-of-range page redirects" do
    before { create(:material, name: "Single Board") }

    it "redirects to the last valid page when page=9999 is requested" do
      login
      visit materials_path(page: 9999)
      expect(current_url).not_to include("page=9999")
      expect(page).to have_text("Single Board", wait: 3)
    end
  end
end
