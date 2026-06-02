require "rails_helper"

RSpec.describe "Estimate Date Fields (SPEC-023)", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user)   { create(:user) }
  let!(:client) { create(:client, company_name: "Millwork Co") }

  def login
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  # AT2: Form renders "Bid Due Date" and "Job Start Date" labels
  describe "new estimate form labels (AT2)" do
    it "renders a Bid Due Date label" do
      login
      visit new_estimate_path

      expect(page).to have_css("label", text: "Bid Due Date")
    end

    it "renders a Job Start Date label" do
      login
      visit new_estimate_path

      expect(page).to have_css("label", text: "Job Start Date")
    end

    it "does not render a label with text exactly 'Start Date'" do
      login
      visit new_estimate_path

      # Must not have a label whose text is exactly "Start Date" (old label)
      expect(page).not_to have_css("label", text: "Start Date", exact_text: true)
    end

    it "does not render a label with text exactly 'End Date'" do
      login
      visit new_estimate_path

      expect(page).not_to have_css("label", text: "End Date", exact_text: true)
    end

    it "renders Bid Due Date on the left and Job Start Date on the right" do
      login
      visit new_estimate_path

      labels = page.all("label").map(&:text).select { |t| t.include?("Bid Due Date") || t.include?("Job Start Date") }
      expect(labels).to eq([ "Bid Due Date", "Job Start Date" ])
    end
  end

  # AT3: Filling and submitting saves correct column values
  describe "submitting dates on new estimate form (AT3)" do
    it "saves bid_due_date and job_start_date to the correct columns" do
      login
      visit new_estimate_path

      select "Millwork Co", from: "estimate_client_id"
      fill_in "estimate[title]", with: "Date Field Test"

      # Set date inputs via JavaScript — Selenium fill_in can misinterpret date format
      page.execute_script("document.querySelector('input[name=\"estimate[bid_due_date]\"]').value = '2026-07-01'")
      page.execute_script("document.querySelector('input[name=\"estimate[job_start_date]\"]').value = '2026-09-01'")

      find("input[type='submit']").click

      expect(page).to have_current_path(%r{/estimates/\d+/edit}, wait: 5)

      created = Estimate.last
      expect(created.bid_due_date).to eq(Date.new(2026, 7, 1))
      expect(created.job_start_date).to eq(Date.new(2026, 9, 1))
    end
  end

  # AT4: Clearing both date fields saves nil
  describe "clearing dates on edit form (AT4)" do
    it "saves nil to both columns when date fields are cleared" do
      estimate = create(:estimate, client: client, title: "Clear Dates Test",
                        created_by: user,
                        bid_due_date: Date.new(2026, 7, 1),
                        job_start_date: Date.new(2026, 9, 1))

      login
      visit new_estimate_path

      # Navigate to the edit page
      visit edit_estimate_path(estimate)

      # Clear both date inputs using JavaScript since date inputs don't support fill_in("")
      page.execute_script("document.querySelector('input[name=\"estimate[bid_due_date]\"]').value = ''")
      page.execute_script("document.querySelector('input[name=\"estimate[job_start_date]\"]').value = ''")

      # Submit via the date field's parent form (the Details form)
      find("input[name='estimate[bid_due_date]']").ancestor("form").find("input[type='submit']").click

      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)

      estimate.reload
      expect(estimate.bid_due_date).to be_nil
      expect(estimate.job_start_date).to be_nil
    end
  end
end
