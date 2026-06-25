require "rails_helper"

RSpec.describe "Estimates", type: :request do
  let(:user)   { create(:user) }
  let(:client) { create(:client) }

  before { sign_in(user) }

  describe "GET /estimates" do
    it "returns http ok" do
      get estimates_path
      expect(response).to have_http_status(:ok)
    end

    it "shows all estimates with client name, title, status, and number" do
      estimate = create(:estimate, client: client, title: "Kitchen Remodel")
      get estimates_path
      expect(response.body).to include(estimate.estimate_number)
      expect(response.body).to include(estimate.title)
      expect(response.body).to include(client.company_name)
    end

    it "shows empty state when no estimates exist" do
      get estimates_path
      expect(response.body).to include("No estimates yet")
    end

    it "redirects to login when not authenticated" do
      delete session_path
      get estimates_path
      expect(response).to redirect_to(new_session_path)
    end

    context "with status filter" do
      let!(:draft_estimate) { create(:estimate, client: client, title: "Draft Job", status: "draft") }
      let!(:sent_estimate)  { create(:estimate, client: client, title: "Sent Job", status: "sent") }

      it "returns only estimates with the given status" do
        get estimates_path, params: { status: "sent" }
        expect(response.body).to include("Sent Job")
        expect(response.body).not_to include("Draft Job")
      end

      it "returns all estimates when no status filter" do
        get estimates_path
        expect(response.body).to include("Draft Job")
        expect(response.body).to include("Sent Job")
      end
    end

    context "with search query" do
      let!(:matching)    { create(:estimate, client: client, title: "Kitchen Remodel") }
      let!(:nonmatching) { create(:estimate, client: client, title: "Garage Door") }

      it "returns only matching estimates" do
        get estimates_path, params: { q: "Kitchen" }
        expect(response.body).to include("Kitchen Remodel")
        expect(response.body).not_to include("Garage Door")
      end
    end
  end

  describe "GET /estimates/new" do
    it "renders the new estimate form" do
      get new_estimate_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /estimates" do
    let(:valid_params) do
      { estimate: { client_id: client.id, title: "New Kitchen" } }
    end

    context "with valid params" do
      it "creates estimate and redirects to estimate edit page" do
        expect {
          post estimates_path, params: valid_params
        }.to change(Estimate, :count).by(1)

        expect(response).to redirect_to(edit_estimate_path(Estimate.last))
      end

      it "sets status to draft" do
        post estimates_path, params: valid_params
        expect(Estimate.last.status).to eq("draft")
      end

      it "generates an estimate number in EST-YYYY-NNNN format" do
        post estimates_path, params: valid_params
        expect(Estimate.last.estimate_number).to match(/\AEST-\d{4}-\d{4}\z/)
      end

      it "sets created_by to current user" do
        post estimates_path, params: valid_params
        expect(Estimate.last.created_by_user_id).to eq(user.id)
      end
    end

    context "without client_id" do
      it "returns unprocessable entity" do
        post estimates_path, params: { estimate: { title: "No Client" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not create an estimate" do
        expect {
          post estimates_path, params: { estimate: { title: "No Client" } }
        }.not_to change(Estimate, :count)
      end
    end

    context "without title" do
      it "returns unprocessable entity" do
        post estimates_path, params: { estimate: { client_id: client.id } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not create an estimate" do
        expect {
          post estimates_path, params: { estimate: { client_id: client.id } }
        }.not_to change(Estimate, :count)
      end
    end
  end

  describe "GET /estimates/:id/edit" do
    let(:estimate) { create(:estimate, client: client) }

    it "renders the edit page" do
      get edit_estimate_path(estimate)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(estimate.title)
    end

    it "shows the add product link" do
      get edit_estimate_path(estimate)
      expect(response.body).to include("Add Product")
    end
  end

  describe "PATCH /estimates/:id" do
    let(:estimate) { create(:estimate, client: client, status: "draft") }

    it "updates the estimate status and redirects" do
      patch estimate_path(estimate), params: { estimate: { status: "sent", title: estimate.title, client_id: client.id } }
      expect(response).to redirect_to(edit_estimate_path(estimate))
      expect(estimate.reload.status).to eq("sent")
    end

    it "updates the estimate title" do
      patch estimate_path(estimate), params: { estimate: { title: "Updated Title", client_id: client.id } }
      expect(estimate.reload.title).to eq("Updated Title")
    end

    it "persists job-level settings on the estimate" do
      patch estimate_path(estimate),
        params: {
          estimate: {
            title: estimate.title,
            client_id: estimate.client_id,
            miles_to_jobsite: "42.5",
            installer_crew_size: "3",
            profit_overhead_percent: "20.0",
            tax_rate: "0.09"
          }
        }

      estimate.reload
      expect(estimate.miles_to_jobsite).to eq(BigDecimal("42.5"))
      expect(estimate.installer_crew_size).to eq(3)
      expect(estimate.profit_overhead_percent).to eq(BigDecimal("20.0"))
      expect(estimate.tax_rate).to eq(BigDecimal("0.09"))
    end

    it "persists job-level cost fields on the estimate" do
      patch estimate_path(estimate),
        params: {
          estimate: {
            title: estimate.title,
            client_id: estimate.client_id,
            install_travel_qty: "3",
            delivery_qty:       "2",
            delivery_rate:      "450.00",
            per_diem_qty:       "4",
            per_diem_rate:      "70.00",
            hotel_qty:          "2",
            airfare_qty:        "1",
            countertop_quote:   "1500.00"
          }
        }

      expect(response).to redirect_to(edit_estimate_path(estimate))
      estimate.reload
      expect(estimate.install_travel_qty).to eq(BigDecimal("3"))
      expect(estimate.delivery_qty).to eq(BigDecimal("2"))
      expect(estimate.delivery_rate).to eq(BigDecimal("450.00"))
      expect(estimate.per_diem_qty).to eq(BigDecimal("4"))
      expect(estimate.per_diem_rate).to eq(BigDecimal("70.00"))
      expect(estimate.hotel_qty).to eq(BigDecimal("2"))
      expect(estimate.airfare_qty).to eq(BigDecimal("1"))
      expect(estimate.countertop_quote).to eq(BigDecimal("1500.00"))
    end

    it "recalculates burdened_total when pm_supervision_percent is updated" do
      create(:labor_rate, labor_category: "detail",   hourly_rate: BigDecimal("20.00"))
      create(:labor_rate, labor_category: "mill",     hourly_rate: BigDecimal("22.00"))
      create(:labor_rate, labor_category: "assembly", hourly_rate: BigDecimal("25.00"))
      create(:labor_rate, labor_category: "customs",  hourly_rate: BigDecimal("18.00"))
      create(:labor_rate, labor_category: "finish",   hourly_rate: BigDecimal("21.00"))
      create(:labor_rate, labor_category: "install",  hourly_rate: BigDecimal("23.00"))

      patch estimate_path(estimate),
        params: {
          estimate: {
            title: estimate.title,
            client_id: estimate.client_id,
            pm_supervision_percent: "8.0",
            profit_overhead_percent: "10.0"
          },
          panel_update: "totals"
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      estimate.reload
      expect(estimate.pm_supervision_percent).to eq(BigDecimal("8.0"))

      # Turbo Stream response must include the updated totals partial targeting the correct id
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("estimate_#{estimate.id}_totals")
      # The burdened total (with no line items, just burden multiplier) should appear as $0.00
      expect(response.body).to include("Final Burdened Total")
      # Flash notice must use turbo_stream.update so the id="flash" wrapper is preserved across saves
      expect(response.body).to match(/action="update"[^>]*target="flash"/)
      expect(response.body).to include("successfully updated")
    end

    it "recalculates material cost_with_tax when tax_rate is updated" do
      material = create(:material, default_price: BigDecimal("100.00"))
      em       = create(:estimate_material, estimate: estimate, material: material,
                        quote_price: BigDecimal("100.00"))

      patch estimate_path(estimate),
        params: {
          estimate: {
            title: estimate.title,
            client_id: estimate.client_id,
            tax_rate: "0.10"
          }
        }

      expect(response).to redirect_to(edit_estimate_path(estimate))
      expect(em.reload.cost_with_tax).to eq(BigDecimal("110.00"))
    end
  end

  describe "GET /estimates/:id/edit — totals panel" do
    let(:estimate) { create(:estimate, client: client) }

    before do
      create(:labor_rate, labor_category: "detail",   hourly_rate: BigDecimal("20.00"))
      create(:labor_rate, labor_category: "mill",     hourly_rate: BigDecimal("22.00"))
      create(:labor_rate, labor_category: "assembly", hourly_rate: BigDecimal("25.00"))
      create(:labor_rate, labor_category: "customs",  hourly_rate: BigDecimal("18.00"))
      create(:labor_rate, labor_category: "finish",   hourly_rate: BigDecimal("21.00"))
      create(:labor_rate, labor_category: "install",  hourly_rate: BigDecimal("23.00"))
    end

    it "renders the sticky totals panel with COGS breakdown labels" do
      get edit_estimate_path(estimate)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("COGS Breakdown")
      expect(response.body).to include("100 — Materials")
      expect(response.body).to include("Final Burdened Total")
    end

    it "renders job-level fixed cost labels in the totals panel" do
      get edit_estimate_path(estimate)
      expect(response.body).to include("Job-Level Fixed Costs")
      expect(response.body).to include("Install Travel")
      expect(response.body).to include("Delivery")
    end

    it "renders labor hours summary in the totals panel" do
      get edit_estimate_path(estimate)
      expect(response.body).to include("Labor Hours Summary")
      expect(response.body).to include("Man-Days (Install)")
    end
  end

  describe "date fields — bid_due_date and job_start_date (SPEC-023)" do
    let(:estimate) { create(:estimate, client: client) }

    describe "POST /estimates with date params" do
      it "saves bid_due_date from params" do
        post estimates_path, params: {
          estimate: { client_id: client.id, title: "Date Test", bid_due_date: "2026-07-01" }
        }
        expect(Estimate.last.bid_due_date).to eq(Date.new(2026, 7, 1))
      end

      it "saves job_start_date from params" do
        post estimates_path, params: {
          estimate: { client_id: client.id, title: "Date Test", job_start_date: "2026-09-01" }
        }
        expect(Estimate.last.job_start_date).to eq(Date.new(2026, 9, 1))
      end

      it "saves both date fields together" do
        post estimates_path, params: {
          estimate: {
            client_id: client.id,
            title: "Both Dates",
            bid_due_date: "2026-07-01",
            job_start_date: "2026-09-01"
          }
        }
        created = Estimate.last
        expect(created.bid_due_date).to eq(Date.new(2026, 7, 1))
        expect(created.job_start_date).to eq(Date.new(2026, 9, 1))
      end

      it "saves nil for both date fields when blank" do
        post estimates_path, params: {
          estimate: {
            client_id: client.id,
            title: "Nil Dates",
            bid_due_date: "",
            job_start_date: ""
          }
        }
        created = Estimate.last
        expect(created.bid_due_date).to be_nil
        expect(created.job_start_date).to be_nil
      end
    end

    describe "PATCH /estimates/:id with date params" do
      it "updates bid_due_date" do
        patch estimate_path(estimate), params: {
          estimate: { client_id: estimate.client_id, title: estimate.title, bid_due_date: "2026-07-15" }
        }
        expect(estimate.reload.bid_due_date).to eq(Date.new(2026, 7, 15))
      end

      it "updates job_start_date" do
        patch estimate_path(estimate), params: {
          estimate: { client_id: estimate.client_id, title: estimate.title, job_start_date: "2026-09-15" }
        }
        expect(estimate.reload.job_start_date).to eq(Date.new(2026, 9, 15))
      end

      it "clears both date fields when blank is submitted" do
        estimate.update!(bid_due_date: "2026-07-01", job_start_date: "2026-09-01")
        patch estimate_path(estimate), params: {
          estimate: {
            client_id: estimate.client_id,
            title: estimate.title,
            bid_due_date: "",
            job_start_date: ""
          }
        }
        estimate.reload
        expect(estimate.bid_due_date).to be_nil
        expect(estimate.job_start_date).to be_nil
      end

      it "does not persist an unpermitted param (strong params silently drops unknown keys)" do
        original_number = estimate.estimate_number
        patch estimate_path(estimate), params: {
          estimate: { client_id: estimate.client_id, title: estimate.title, estimate_number: "EST-FAKE-9999" }
        }
        expect(response).to redirect_to(edit_estimate_path(estimate))
        expect(estimate.reload.estimate_number).to eq(original_number)
      end
    end

    describe "unauthenticated access" do
      it "redirects to login and does not modify the estimate" do
        delete session_path
        patch estimate_path(estimate), params: {
          estimate: { bid_due_date: "2026-07-01", job_start_date: "2026-09-01" }
        }
        expect(response).to redirect_to(new_session_path)
        estimate.reload
        expect(estimate.bid_due_date).to be_nil
        expect(estimate.job_start_date).to be_nil
      end
    end
  end

  describe "DELETE /estimates/:id" do
    let!(:estimate) { create(:estimate, client: client) }

    it "destroys the estimate and redirects to index" do
      expect {
        delete estimate_path(estimate)
      }.to change(Estimate, :count).by(-1)

      expect(response).to redirect_to(estimates_path)
    end
  end
end
