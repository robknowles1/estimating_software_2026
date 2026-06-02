require "rails_helper"

RSpec.describe "Room Tracking on CSV Import", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  def login(user)
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  # Opens the "Import CSV" <details> panel on the estimate edit page and submits
  # the given IO/path as a CSV file upload.
  def import_csv(estimate, csv_content)
    visit edit_estimate_path(estimate)

    import_details = all("details").find { |det| det.text.include?("Import CSV") }
    page.execute_script("arguments[0].setAttribute('open', '')", import_details.native)

    within(import_details) do
      find("input[type='file']", visible: :visible, wait: 5)
      # Write content to a temp file so attach_file can reference a real path
      Tempfile.create([ "room_tracking_import", ".csv" ]) do |f|
        f.write(csv_content)
        f.flush
        attach_file "csv_file", f.path
        submit_btn = find("input[type='submit']")
        page.execute_script("arguments[0].click()", submit_btn.native)
      end
    end

    expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
  end

  # AT-1: Import CSV with "Room A" and "Room B" → both cards show room label
  describe "AT-1: importing a CSV with two different rooms" do
    it "shows the room label on each line item card" do
      user     = create(:user)
      client   = create(:client, company_name: "Prestige Millwork")
      estimate = create(:estimate, client: client, title: "Room Tracking Test", created_by: user)
      login(user)

      csv = [
        "Base Cabinets,Room A,Kitchen,,BC-001,Base 2-Door,desc,,2,EA,extra",
        "Upper Cabinets,Room B,Living,,UC-001,Wall Cabinet,desc,,3,EA,extra"
      ].join("\n")

      import_csv(estimate, csv)

      expect(page).to have_text("Room: Room A", wait: 5)
      expect(page).to have_text("Room: Room B", wait: 5)
    end
  end

  # AT-2: Import CSV with a "Finished Schedule" row plus a normal row → only one line item appears
  describe "AT-2: importing a CSV with a Finished Schedule row" do
    it "skips the Finished Schedule row and shows only one line item card" do
      user     = create(:user)
      client   = create(:client, company_name: "Prestige Millwork")
      estimate = create(:estimate, client: client, title: "Finished Schedule Test", created_by: user)
      login(user)

      csv = [
        "Finished Schedule,Room A,Kitchen,,FS-001,Schedule Item,desc,,1,EA,extra",
        "Base Cabinets,Room A,Kitchen,,BC-001,Base 2-Door,desc,,2,EA,extra"
      ].join("\n")

      import_csv(estimate, csv)

      expect(page).to have_text("Base 2-Door", wait: 5)
      expect(page).not_to have_text("Schedule Item")
      expect(estimate.line_items.count).to eq(1)
    end
  end

  # AT-3: Line item with room: nil → no room label rendered on the card
  describe "AT-3: line item with room nil shows no room label" do
    it "does not render the room label when room is nil" do
      user     = create(:user)
      client   = create(:client, company_name: "Prestige Millwork")
      estimate = create(:estimate, client: client, title: "No Room Test", created_by: user)
      create(:line_item, estimate: estimate, description: "Roomless Cabinet", room: nil)
      login(user)

      visit edit_estimate_path(estimate)

      expect(page).to have_text("Roomless Cabinet", wait: 5)
      expect(page).not_to have_text("Room:")
    end
  end
end
