require "rails_helper"

RSpec.describe "EstimateMaterials", type: :request do
  describe "GET /estimates/:estimate_id/estimate_materials/new" do
    it "includes active material names as <option> elements inside the select" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      create(:material, name: "Cherry Plywood", category: "sheet_good")
      sign_in(user)

      # Act
      get new_estimate_estimate_material_path(estimate)

      # Assert
      expect(response.body).to include("Cherry Plywood")
      expect(response.body).to match(/<option value="\d+">Cherry Plywood/)
    end

    it "renders no material <option> elements when no active materials exist" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      sign_in(user)

      # Act
      get new_estimate_estimate_material_path(estimate)

      # Assert — only the blank placeholder option should be present; no material options
      expect(response.body).not_to match(/<option value="\d+">/)
    end
  end

  describe "GET /estimates/:estimate_id/estimate_materials" do
    it "returns http ok" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      sign_in(user)

      # Act / Assert
      get estimate_estimate_materials_path(estimate)
      expect(response).to have_http_status(:ok)
    end

    it "lists the estimate's materials" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      material = create(:material, name: "Birch Ply")
      create(:estimate_material, estimate: estimate, material: material)
      sign_in(user)

      # Act
      get estimate_estimate_materials_path(estimate)

      # Assert
      expect(response.body).to include("Birch Ply")
    end

    it "redirects to login when unauthenticated" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)

      # Act
      get estimate_estimate_materials_path(estimate)

      # Assert
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "POST /estimates/:estimate_id/estimate_materials with material_id" do
    it "creates an estimate_materials row with quote_price from default_price" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      material = create(:material, name: "Oak Sheet", default_price: BigDecimal("55.00"))
      sign_in(user)

      # Act
      expect {
        post estimate_estimate_materials_path(estimate), params: { material_id: material.id }
      }.to change(EstimateMaterial, :count).by(1)

      # Assert
      em = estimate.estimate_materials.last
      expect(em.quote_price).to eq(BigDecimal("55.00"))
      expect(em.material).to eq(material)
    end

    it "redirects to the price book index" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      material = create(:material, name: "Oak Sheet", default_price: BigDecimal("55.00"))
      sign_in(user)

      # Act
      post estimate_estimate_materials_path(estimate), params: { material_id: material.id }

      # Assert
      expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
    end

    it "does not create a duplicate when material is already present" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      material = create(:material, name: "Oak Sheet", default_price: BigDecimal("55.00"))
      create(:estimate_material, estimate: estimate, material: material)
      sign_in(user)

      # Act / Assert
      expect {
        post estimate_estimate_materials_path(estimate), params: { material_id: material.id }
      }.not_to change(EstimateMaterial, :count)
    end

    it "redirects with an informational notice when material already present" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      material = create(:material, name: "Oak Sheet", default_price: BigDecimal("55.00"))
      create(:estimate_material, estimate: estimate, material: material)
      sign_in(user)

      # Act
      post estimate_estimate_materials_path(estimate), params: { material_id: material.id }

      # Assert
      expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
      expect(flash[:notice]).to include("already")
    end
  end

  describe "POST /estimates/:estimate_id/estimate_materials with new material params" do
    it "creates a Material and an EstimateMaterial in one request" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      sign_in(user)

      # Act / Assert
      expect {
        post estimate_estimate_materials_path(estimate), params: {
          material: {
            name:          "Custom Hardwood",
            category:      "sheet_good",
            default_price: "75.00",
            unit:          "sheet"
          }
        }
      }.to change(Material, :count).by(1)
        .and change(EstimateMaterial, :count).by(1)
    end

    it "redirects to the price book index" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      sign_in(user)

      # Act
      post estimate_estimate_materials_path(estimate), params: {
        material: {
          name:          "Custom Hardwood",
          category:      "sheet_good",
          default_price: "75.00",
          unit:          "sheet"
        }
      }

      # Assert
      expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
    end
  end

  describe "PATCH /estimates/:estimate_id/estimate_materials/:id" do
    it "updates quote_price and recomputes cost_with_tax" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user, tax_rate: BigDecimal("0.10"), tax_exempt: false)
      material = create(:material, default_price: BigDecimal("50.00"))
      em       = create(:estimate_material, estimate: estimate, material: material,
                        quote_price: BigDecimal("50.00"))
      sign_in(user)

      # Act
      patch estimate_estimate_material_path(estimate, em), params: {
        estimate_material: { quote_price: "60.00" }
      }
      em.reload

      # Assert
      expect(em.quote_price).to eq(BigDecimal("60.00"))
      expect(em.cost_with_tax).to eq(BigDecimal("60.00") * BigDecimal("1.10"))
    end

    it "redirects to the price book index" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user, tax_rate: BigDecimal("0.10"), tax_exempt: false)
      material = create(:material, default_price: BigDecimal("50.00"))
      em       = create(:estimate_material, estimate: estimate, material: material,
                        quote_price: BigDecimal("50.00"))
      sign_in(user)

      # Act
      patch estimate_estimate_material_path(estimate, em), params: {
        estimate_material: { quote_price: "60.00" }
      }

      # Assert
      expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
    end

    # SPEC-022: short code updates
    context "SPEC-022: short_code field" do
      it "updates short_code with a valid unique value" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user, tax_rate: BigDecimal("0.10"), tax_exempt: false)
        material = create(:material, default_price: BigDecimal("50.00"))
        em       = create(:estimate_material, estimate: estimate, material: material,
                          quote_price: BigDecimal("50.00"))
        sign_in(user)

        # Act
        patch estimate_estimate_material_path(estimate, em), params: {
          estimate_material: { quote_price: em.quote_price.to_s, short_code: "PL1" }
        }

        # Assert
        expect(em.reload.short_code).to eq("PL1")
        expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
      end

      it "rejects a duplicate short_code on the same estimate with 422" do
        # Arrange
        user      = create(:user)
        estimate  = create(:estimate, created_by: user, tax_rate: BigDecimal("0.10"), tax_exempt: false)
        material  = create(:material, default_price: BigDecimal("50.00"))
        material2 = create(:material, default_price: BigDecimal("30.00"))
        em  = create(:estimate_material, estimate: estimate, material: material,
                     quote_price: BigDecimal("50.00"))
        create(:estimate_material, estimate: estimate, material: material2,
               quote_price: BigDecimal("30.00"), short_code: "PL1")
        sign_in(user)

        # Act
        patch estimate_estimate_material_path(estimate, em), params: {
          estimate_material: { quote_price: em.quote_price.to_s, short_code: "PL1" }
        }

        # Assert
        expect(response).to have_http_status(:unprocessable_content)
        expect(em.reload.short_code).to be_nil
      end

      it "allows a blank short_code" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user, tax_rate: BigDecimal("0.10"), tax_exempt: false)
        material = create(:material, default_price: BigDecimal("50.00"))
        em       = create(:estimate_material, estimate: estimate, material: material,
                          quote_price: BigDecimal("50.00"))
        sign_in(user)

        # Act
        patch estimate_estimate_material_path(estimate, em), params: {
          estimate_material: { quote_price: em.quote_price.to_s, short_code: "" }
        }

        # Assert
        expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
        expect(em.reload.short_code).to be_nil
      end
    end
  end

  describe "strong params — removed flat columns" do
    it "does not permit exterior_unit_price on line item create" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      sign_in(user)

      # Act
      post estimate_line_items_path(estimate), params: {
        line_item: { description: "Test", quantity: "1", unit: "EA", exterior_unit_price: "999" }
      }

      # Assert
      li = LineItem.last
      expect(li).not_to respond_to(:exterior_unit_price)
    end

    it "does not permit exterior_description on line item create" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      sign_in(user)

      # Act
      post estimate_line_items_path(estimate), params: {
        line_item: { description: "Test2", quantity: "1", unit: "EA", exterior_description: "ignored" }
      }

      # Assert
      li = LineItem.last
      expect(li).not_to respond_to(:exterior_description)
    end
  end

  describe "POST /estimates/:estimate_id/estimate_materials — soft-deleted material" do
    it "returns 404 when the material is soft-deleted" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      material = create(:material, discarded_at: Time.current)
      sign_in(user)

      # Act
      post estimate_estimate_materials_path(estimate), params: { material_id: material.id }

      # Assert
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /estimates/:estimate_id/estimate_materials — race condition on duplicate" do
    it "redirects with already_present notice instead of raising on RecordNotUnique" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      material = create(:material)
      # Pre-create the record so the unique index is violated
      create(:estimate_material, estimate: estimate, material: material)
      sign_in(user)

      # Act
      # Force the race: em.save will hit the DB unique constraint because find_or_initialize
      # is not used anymore — the duplicate check is now handled by rescuing RecordNotUnique
      post estimate_estimate_materials_path(estimate), params: { material_id: material.id }

      # Assert
      expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
      expect(flash[:notice]).to include("already")
    end
  end

  describe "POST /estimates/:estimate_id/estimate_materials — new material transaction atomicity" do
    it "creates both Material and EstimateMaterial together" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      sign_in(user)

      # Act / Assert
      expect {
        post estimate_estimate_materials_path(estimate), params: {
          material: {
            name:          "Brand New Material",
            category:      "sheet_good",
            default_price: "10.00",
            unit:          "sheet"
          }
        }
      }.to change(Material, :count).by(1).and change(EstimateMaterial, :count).by(1)
    end

    it "does not leave an orphaned Material when only material params are invalid" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      sign_in(user)

      # Act / Assert — category missing — material fails validation, nothing is created
      expect {
        post estimate_estimate_materials_path(estimate), params: {
          material: { name: "", category: "", default_price: "10.00", unit: "sheet" }
        }
      }.not_to change(Material, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    # NOTE: This test requires stubbing EstimateMaterial#save because the controller builds
    # the EstimateMaterial from a brand-new Material (unique material_id), making it
    # impossible to force em.save to fail with real objects alone without controller refactoring.
    # Deviation from testing standard §3.7.5 noted; tracked for post-MVP controller refactor.
    it "rolls back the Material when EstimateMaterial save fails" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      sign_in(user)
      allow_any_instance_of(EstimateMaterial).to receive(:save).and_return(false)

      # Act / Assert
      expect {
        post estimate_estimate_materials_path(estimate), params: {
          material: {
            name:          "Orphan Risk Material",
            category:      "sheet_good",
            default_price: "20.00",
            unit:          "sheet"
          }
        }
      }.not_to change(Material, :count)
    end
  end

  describe "unauthenticated access" do
    it "redirects GET index to login" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)

      # Act
      get estimate_estimate_materials_path(estimate)

      # Assert
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects POST create to login" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)

      # Act
      post estimate_estimate_materials_path(estimate), params: { material_id: "1" }

      # Assert
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "POST /estimates/:estimate_id/estimate_materials/inline_create" do
    context "with valid params" do
      it "returns HTTP 201 with JSON body containing id, name, and formatted display" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act
        post inline_create_estimate_estimate_materials_path(estimate),
             params: { material: { name: "Test Birch", cost: "42.50" } },
             as: :json

        # Assert
        expect(response).to have_http_status(:created)
        expect(response.media_type).to include("application/json")
        body = JSON.parse(response.body)
        expect(body["id"]).to be_a(Integer)
        expect(body["name"]).to eq("Test Birch")
        expect(body["display"]).to match(/Test Birch \(\$42\.50\)/)
      end

      it "creates a Material with default_price equal to the entered cost" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act
        expect {
          post inline_create_estimate_estimate_materials_path(estimate),
               params: { material: { name: "Test Birch", cost: "42.50" } },
               as: :json
        }.to change(Material, :count).by(1)

        # Assert
        material = Material.find_by(name: "Test Birch")
        expect(material).to be_present
        expect(material.default_price).to eq(BigDecimal("42.50"))
        expect(material.category).to eq("hardware")
        expect(material.unit).to eq("EA")
      end

      it "creates an EstimateMaterial linking the new material to the estimate" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act
        expect {
          post inline_create_estimate_estimate_materials_path(estimate),
               params: { material: { name: "Test Birch", cost: "42.50" } },
               as: :json
        }.to change(EstimateMaterial, :count).by(1)

        # Assert
        em = estimate.estimate_materials.last
        expect(em.material.name).to eq("Test Birch")
        expect(em.quote_price).to eq(BigDecimal("42.50"))
      end

      it "computes cost_with_tax via the existing before_save callback" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user, tax_rate: BigDecimal("0.10"), tax_exempt: false)
        sign_in(user)

        # Act
        post inline_create_estimate_estimate_materials_path(estimate),
             params: { material: { name: "Taxed Material", cost: "100.00" } },
             as: :json

        # Assert
        em = estimate.estimate_materials.last
        expect(em.cost_with_tax).to eq(BigDecimal("100.00") * BigDecimal("1.10"))
      end

      it "returns the EstimateMaterial id (not the Material id) so the form submits the correct slot value" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act
        post inline_create_estimate_estimate_materials_path(estimate),
             params: { material: { name: "Returned Id", cost: "5.00" } },
             as: :json

        # Assert
        body = JSON.parse(response.body)
        em = estimate.estimate_materials.last
        expect(body["id"]).to eq(em.id)
        expect(body["id"]).not_to eq(em.material.id)
      end
    end

    context "with invalid params" do
      it "returns HTTP 422 and an errors array when name is blank" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act / Assert
        expect {
          post inline_create_estimate_estimate_materials_path(estimate),
               params: { material: { name: "", cost: "10.00" } },
               as: :json
        }.not_to change(Material, :count)

        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body["errors"]).to be_an(Array)
        expect(body["errors"]).to be_present
        expect(body["errors"].any? { |m| m =~ /Name/i }).to be true
      end

      it "returns HTTP 422 and an errors array when cost is blank" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act / Assert
        expect {
          post inline_create_estimate_estimate_materials_path(estimate),
               params: { material: { name: "Cedar Ply", cost: "" } },
               as: :json
        }.not_to change(Material, :count)

        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body["errors"]).to be_an(Array)
        expect(body["errors"]).to be_present
      end

      it "returns HTTP 422 and an errors array when cost is negative" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act / Assert
        expect {
          post inline_create_estimate_estimate_materials_path(estimate),
               params: { material: { name: "Negative", cost: "-1.00" } },
               as: :json
        }.not_to change(Material, :count)

        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body["errors"]).to be_present
      end

      it "creates a duplicate Material when the name already exists in the global library (AC-16)" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        create(:material, name: "Duplicate Name")
        sign_in(user)

        # Act / Assert
        expect {
          post inline_create_estimate_estimate_materials_path(estimate),
               params: { material: { name: "Duplicate Name", cost: "5.00" } },
               as: :json
        }.to change(Material, :count).by(1)

        expect(response).to have_http_status(:created)
      end
    end

    context "without authentication" do
      it "redirects to the login page (HTTP 302) — require_login redirects, not 401" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)

        # Act
        post inline_create_estimate_estimate_materials_path(estimate),
             params: { material: { name: "Anon", cost: "5.00" } },
             as: :json

        # Assert
        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(new_session_path)
      end
    end

    context "with an invalid estimate_id" do
      it "returns HTTP 404" do
        # Arrange
        user = create(:user)
        sign_in(user)

        # Act
        post "/estimates/9999999/estimate_materials/inline_create",
             params: { material: { name: "X", cost: "1" } },
             as: :json

        # Assert
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
