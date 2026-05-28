require "rails_helper"

RSpec.describe "LineItems", type: :request do
  describe "GET /estimates/:estimate_id/line_items/new" do
    it "returns http ok" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)
      sign_in(user)

      # Act / Assert
      get new_estimate_line_item_path(estimate)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /estimates/:estimate_id/line_items" do
    context "without product_id (freeform)" do
      it "creates a line item with product_id nil (freeform)" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act / Assert
        expect {
          post estimate_line_items_path(estimate), params: {
            line_item: { description: "Custom shelf unit", quantity: "2", unit: "EA" }
          }
        }.to change(LineItem, :count).by(1)

        expect(LineItem.last.product_id).to be_nil
      end

      it "does not create a catalog product for a freeform line item" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act / Assert
        expect {
          post estimate_line_items_path(estimate), params: {
            line_item: { description: "Custom shelf unit", quantity: "2", unit: "EA" }
          }
        }.not_to change(Product, :count)
      end

      it "saves the provided description" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: { description: "Custom shelf unit", quantity: "2", unit: "EA" }
        }

        # Assert
        expect(LineItem.last.description).to eq("Custom shelf unit")
      end
    end

    context "with product_id" do
      it "creates a line item with the product's name as description when description is blank" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        product  = create(:product, name: "MDF Base 2-door", unit: "EA",
                          exterior_qty: BigDecimal("2.5"), detail_hrs: BigDecimal("0.75"))
        sign_in(user)

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: { product_id: product.id, description: "", quantity: "1", unit: "EA" }
        }

        # Assert
        expect(LineItem.last.description).to eq("MDF Base 2-door")
      end

      it "copies exterior_qty from the product" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        product  = create(:product, name: "MDF Base 2-door", unit: "EA",
                          exterior_qty: BigDecimal("2.5"), detail_hrs: BigDecimal("0.75"))
        sign_in(user)

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: { product_id: product.id, description: "", quantity: "1", unit: "EA" }
        }

        # Assert
        expect(LineItem.last.exterior_qty).to eq(BigDecimal("2.5"))
      end

      it "respects an overridden description param over the product name" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        product  = create(:product, name: "MDF Base 2-door", unit: "EA",
                          exterior_qty: BigDecimal("2.5"), detail_hrs: BigDecimal("0.75"))
        sign_in(user)

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: { product_id: product.id, description: "My custom override", quantity: "1", unit: "EA" }
        }

        # Assert
        expect(LineItem.last.description).to eq("My custom override")
      end

      it "sets product_id on the created line item" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        product  = create(:product, name: "MDF Base 2-door", unit: "EA",
                          exterior_qty: BigDecimal("2.5"), detail_hrs: BigDecimal("0.75"))
        sign_in(user)

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: { product_id: product.id, description: "", quantity: "1", unit: "EA" }
        }

        # Assert
        expect(LineItem.last.product_id).to eq(product.id)
      end
    end

    context "with exterior_material_id" do
      it "creates line item with the FK set" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        material = create(:material, default_price: BigDecimal("50.00"))
        em       = create(:estimate_material, estimate: estimate, material: material,
                          quote_price: BigDecimal("50.00"))
        sign_in(user)

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: {
            description: "Test cabinet", quantity: "1", unit: "EA",
            exterior_material_id: em.id.to_s
          }
        }

        # Assert
        expect(LineItem.last.exterior_material_id).to eq(em.id)
      end
    end

    # SPEC-018: other_material_id / other_qty params
    context "SPEC-018: with other_material_id and other_qty" do
      it "saves other_material_id and other_qty on the created record" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        material = create(:material, default_price: BigDecimal("10.00"))
        em       = create(:estimate_material, estimate: estimate, material: material,
                          quote_price: BigDecimal("10.00"))
        sign_in(user)

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: {
            description: "Other slot cabinet", quantity: "1", unit: "EA",
            other_material_id: em.id.to_s, other_qty: "3"
          }
        }

        # Assert
        li = LineItem.last
        expect(li.other_material_id).to eq(em.id)
        expect(li.other_qty).to eq(BigDecimal("3"))
      end
    end

    context "SPEC-018: with other_material_id from a different estimate (cross-estimate attack)" do
      it "is rejected with unprocessable_content" do
        # Arrange
        user           = create(:user)
        estimate       = create(:estimate, created_by: user)
        other_estimate = create(:estimate, created_by: user)
        material       = create(:material, default_price: BigDecimal("10.00"))
        em_other       = create(:estimate_material, estimate: other_estimate, material: material,
                                quote_price: BigDecimal("10.00"))
        sign_in(user)

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: {
            description: "Attack cabinet", quantity: "1", unit: "EA",
            other_material_id: em_other.id.to_s, other_qty: "1"
          }
        }

        # Assert
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not persist the line item" do
        # Arrange
        user           = create(:user)
        estimate       = create(:estimate, created_by: user)
        other_estimate = create(:estimate, created_by: user)
        material       = create(:material, default_price: BigDecimal("10.00"))
        em_other       = create(:estimate_material, estimate: other_estimate, material: material,
                                quote_price: BigDecimal("10.00"))
        sign_in(user)

        # Act / Assert
        expect {
          post estimate_line_items_path(estimate), params: {
            line_item: {
              description: "Attack cabinet", quantity: "1", unit: "EA",
              other_material_id: em_other.id.to_s, other_qty: "1"
            }
          }
        }.not_to change(LineItem, :count)
      end
    end

    # SPEC-029: ProductSlotResolver integration
    context "SPEC-029: with product_id and matching price book short codes" do
      it "assigns pulls_material_id from the resolver when product has pulls_slot_code matching price book" do
        # Arrange
        user = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "PULL1")
        product = create(:product, name: "Cabinet", unit: "EA", pulls_slot_code: "PULL1")

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: { product_id: product.id, description: "Cabinet", quantity: "1", unit: "EA" }
        }

        # Assert
        expect(LineItem.last.pulls_material_id).to eq(em.id)
      end

      it "creates the line item and redirects even when price book has no short codes" do
        # Arrange
        user = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: nil)
        product = create(:product, name: "Cabinet", unit: "EA", pulls_slot_code: "PULL1",
                                   hinges_slot_code: "HINGE1")

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: { product_id: product.id, description: "Cabinet", quantity: "1", unit: "EA" }
        }

        # Assert
        li = LineItem.last
        expect(response).to redirect_to(edit_estimate_path(estimate))
        expect(li.pulls_material_id).to be_nil
        expect(li.hinges_material_id).to be_nil
      end

      it "uses estimator-submitted pulls_material_id over resolver assignment" do
        # Arrange
        user = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)
        material1 = create(:material)
        material2 = create(:material)
        em_resolver = create(:estimate_material, estimate: estimate, material: material1, short_code: "PULL1")
        em_override = create(:estimate_material, estimate: estimate, material: material2)
        product = create(:product, name: "Cabinet", unit: "EA", pulls_slot_code: "PULL1")

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: {
            product_id: product.id,
            description: "Cabinet",
            quantity: "1",
            unit: "EA",
            pulls_material_id: em_override.id.to_s
          }
        }

        # Assert
        li = LineItem.last
        expect(li.pulls_material_id).to eq(em_override.id)
        expect(li.pulls_material_id).not_to eq(em_resolver.id)
      end

      it "leaves all material_ids nil for a freeform line item (no product_id)" do
        # Arrange
        user = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "PULL1")

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: { description: "Freeform shelf", quantity: "1", unit: "EA" }
        }

        # Assert
        li = LineItem.last
        expect(li.pulls_material_id).to be_nil
        expect(li.exterior_material_id).to be_nil
      end
    end

    context "with invalid params" do
      it "returns unprocessable entity when description is blank" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act
        post estimate_line_items_path(estimate), params: {
          line_item: { description: "", quantity: "1", unit: "EA" }
        }

        # Assert
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "redirects to login when unauthenticated" do
      # Arrange
      user     = create(:user)
      estimate = create(:estimate, created_by: user)

      # Act
      post estimate_line_items_path(estimate), params: {
        line_item: { description: "Test", quantity: "1", unit: "EA" }
      }

      # Assert
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "PATCH /estimates/:estimate_id/line_items/:id" do
    it "updates the line item description" do
      # Arrange
      user      = create(:user)
      estimate  = create(:estimate, created_by: user)
      line_item = create(:line_item, estimate: estimate, description: "Old Name")
      sign_in(user)

      # Act
      patch estimate_line_item_path(estimate, line_item), params: {
        line_item: { description: "New Name", quantity: "1", unit: "EA" }
      }

      # Assert
      expect(line_item.reload.description).to eq("New Name")
    end

    it "redirects to the estimate edit page on success" do
      # Arrange
      user      = create(:user)
      estimate  = create(:estimate, created_by: user)
      line_item = create(:line_item, estimate: estimate, description: "Old Name")
      sign_in(user)

      # Act
      patch estimate_line_item_path(estimate, line_item), params: {
        line_item: { description: "New Name", quantity: "1", unit: "EA" }
      }

      # Assert
      expect(response).to redirect_to(edit_estimate_path(estimate))
    end

    context "with exterior_material_id" do
      it "updates the FK" do
        # Arrange
        user      = create(:user)
        estimate  = create(:estimate, created_by: user)
        line_item = create(:line_item, estimate: estimate, description: "Old Name")
        material  = create(:material, default_price: BigDecimal("50.00"))
        em        = create(:estimate_material, estimate: estimate, material: material,
                           quote_price: BigDecimal("50.00"))
        sign_in(user)

        # Act
        patch estimate_line_item_path(estimate, line_item), params: {
          line_item: {
            description: "New Name", quantity: "1", unit: "EA",
            exterior_material_id: em.id.to_s
          }
        }

        # Assert
        expect(line_item.reload.exterior_material_id).to eq(em.id)
      end
    end

    # SPEC-018: other_material_id / other_qty on update
    context "SPEC-018: updating other_material_id and other_qty" do
      it "saves other_material_id and other_qty on the updated record" do
        # Arrange
        user      = create(:user)
        estimate  = create(:estimate, created_by: user)
        line_item = create(:line_item, estimate: estimate, description: "Old Name")
        material  = create(:material, default_price: BigDecimal("10.00"))
        em        = create(:estimate_material, estimate: estimate, material: material,
                           quote_price: BigDecimal("10.00"))
        sign_in(user)

        # Act
        patch estimate_line_item_path(estimate, line_item), params: {
          line_item: {
            description: "Updated cabinet", quantity: "1", unit: "EA",
            other_material_id: em.id.to_s, other_qty: "5"
          }
        }

        # Assert
        expect(line_item.reload.other_material_id).to eq(em.id)
        expect(line_item.reload.other_qty).to eq(BigDecimal("5"))
      end
    end

    context "SPEC-018: updating with other_material_id from a different estimate" do
      it "returns 422 and does not save" do
        # Arrange
        user           = create(:user)
        estimate       = create(:estimate, created_by: user)
        other_estimate = create(:estimate, created_by: user)
        line_item      = create(:line_item, estimate: estimate, description: "Old Name")
        material       = create(:material, default_price: BigDecimal("10.00"))
        em_other       = create(:estimate_material, estimate: other_estimate, material: material,
                                quote_price: BigDecimal("10.00"))
        sign_in(user)

        # Act
        patch estimate_line_item_path(estimate, line_item), params: {
          line_item: {
            description: "Attack update", quantity: "1", unit: "EA",
            other_material_id: em_other.id.to_s, other_qty: "1"
          }
        }

        # Assert
        expect(response).to have_http_status(:unprocessable_content)
        expect(line_item.reload.other_material_id).to be_nil
      end
    end

    it "redirects to login when unauthenticated" do
      # Arrange
      user      = create(:user)
      estimate  = create(:estimate, created_by: user)
      line_item = create(:line_item, estimate: estimate, description: "Old Name")

      # Act
      patch estimate_line_item_path(estimate, line_item), params: {
        line_item: { description: "New Name", quantity: "1", unit: "EA" }
      }

      # Assert
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "POST /estimates/:estimate_id/line_items/import" do
    context "with a valid CSV file" do
      it "redirects to the estimate edit page" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act
        post import_estimate_line_items_path(estimate),
          params: { csv_file: Rack::Test::UploadedFile.new(
            Rails.root.join("spec/fixtures/files/sample_import.csv"), "text/csv"
          ) }

        # Assert
        expect(response).to redirect_to(edit_estimate_path(estimate))
      end

      it "increases LineItem.count by the number of unique products" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act / Assert
        expect {
          post import_estimate_line_items_path(estimate),
            params: { csv_file: Rack::Test::UploadedFile.new(
              Rails.root.join("spec/fixtures/files/sample_import.csv"), "text/csv"
            ) }
        }.to change(LineItem, :count).by(2)
      end

      it "shows a flash notice containing the count" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        sign_in(user)

        # Act
        post import_estimate_line_items_path(estimate),
          params: { csv_file: Rack::Test::UploadedFile.new(
            Rails.root.join("spec/fixtures/files/sample_import.csv"), "text/csv"
          ) }
        follow_redirect!

        # Assert
        expect(response.body).to include("2")
      end
    end

    context "with an invalid/empty file" do
      it "redirects with an alert" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        bad_csv  = Rack::Test::UploadedFile.new(StringIO.new("Base Cabinets,short"), "text/csv",
                                                original_filename: "bad.csv")
        sign_in(user)

        # Act
        post import_estimate_line_items_path(estimate), params: { csv_file: bad_csv }

        # Assert
        expect(response).to redirect_to(edit_estimate_path(estimate))
        expect(flash[:alert]).to be_present
      end

      it "does not change LineItem.count" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        bad_csv  = Rack::Test::UploadedFile.new(StringIO.new("Base Cabinets,short"), "text/csv",
                                                original_filename: "bad.csv")
        sign_in(user)

        # Act / Assert
        expect {
          post import_estimate_line_items_path(estimate), params: { csv_file: bad_csv }
        }.not_to change(LineItem, :count)
      end
    end

    context "unauthenticated" do
      it "redirects to the login page" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)

        # Act
        post import_estimate_line_items_path(estimate),
          params: { csv_file: Rack::Test::UploadedFile.new(
            Rails.root.join("spec/fixtures/files/sample_import.csv"), "text/csv"
          ) }

        # Assert
        expect(response).to redirect_to(new_session_path)
      end

      it "creates no line items" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)

        # Act / Assert
        expect {
          post import_estimate_line_items_path(estimate),
            params: { csv_file: Rack::Test::UploadedFile.new(
              Rails.root.join("spec/fixtures/files/sample_import.csv"), "text/csv"
            ) }
        }.not_to change(LineItem, :count)
      end
    end
  end

  # SPEC-022: apply_aliases action
  describe "POST /estimates/:estimate_id/line_items/apply_aliases" do
    context "with a matching short code and line item" do
      it "redirects to the estimate edit page" do
        # Arrange
        user      = create(:user)
        estimate  = create(:estimate, created_by: user)
        material  = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        create(:line_item, estimate: estimate, description: "PL1 Cabinet")
        sign_in(user)

        # Act
        post apply_aliases_estimate_line_items_path(estimate)

        # Assert
        expect(response).to redirect_to(edit_estimate_path(estimate))
      end

      it "sets exterior_material_id on the matched line item" do
        # Arrange
        user      = create(:user)
        estimate  = create(:estimate, created_by: user)
        material  = create(:material)
        em        = create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        line_item = create(:line_item, estimate: estimate, description: "PL1 Cabinet")
        sign_in(user)

        # Act
        post apply_aliases_estimate_line_items_path(estimate)

        # Assert
        expect(line_item.reload.exterior_material_id).to eq(em.id)
      end
    end

    context "unauthenticated" do
      it "redirects to the login page" do
        # Arrange
        user     = create(:user)
        estimate = create(:estimate, created_by: user)

        # Act
        post apply_aliases_estimate_line_items_path(estimate)

        # Assert
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  # SPEC-022: import flash messages with short code counts
  # These tests use real CSV data and real price book entries to exercise flash variants.
  # The sample_import.csv produces "Base 2-Door" and "Wall Cabinet" as product names.
  describe "POST /estimates/:estimate_id/line_items/import — SPEC-022 flash variants" do
    context "with matching short codes for every imported product" do
      it "shows all_matched flash when all items matched" do
        # Arrange — add short codes that match both products in the sample CSV
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "Base")
        material2 = create(:material)
        create(:estimate_material, estimate: estimate, material: material2, short_code: "Wall")
        sign_in(user)

        # Act
        post import_estimate_line_items_path(estimate),
          params: { csv_file: Rack::Test::UploadedFile.new(
            Rails.root.join("spec/fixtures/files/sample_import.csv"), "text/csv"
          ) }
        follow_redirect!

        # Assert
        expect(response.body).to include("All materials auto-assigned")
      end
    end

    context "with a short code matching only one of two imported products" do
      it "shows unmatched flash with count" do
        # Arrange — "Base" matches "Base 2-Door" but not "Wall Cabinet"
        user     = create(:user)
        estimate = create(:estimate, created_by: user)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "Base")
        sign_in(user)

        # Act
        post import_estimate_line_items_path(estimate),
          params: { csv_file: Rack::Test::UploadedFile.new(
            Rails.root.join("spec/fixtures/files/sample_import.csv"), "text/csv"
          ) }
        follow_redirect!

        # Assert
        expect(response.body).to include("need review")
      end
    end

    context "with two short codes both present in a single product name" do
      it "shows ambiguous flash with count" do
        # Arrange — "Base" and "2-Door" are both substrings of "Base 2-Door"
        user      = create(:user)
        estimate  = create(:estimate, created_by: user)
        material  = create(:material)
        material2 = create(:material)
        create(:estimate_material, estimate: estimate, material: material,  short_code: "Base")
        create(:estimate_material, estimate: estimate, material: material2, short_code: "2-Door")
        sign_in(user)

        # Act
        post import_estimate_line_items_path(estimate),
          params: { csv_file: Rack::Test::UploadedFile.new(
            Rails.root.join("spec/fixtures/files/sample_import.csv"), "text/csv"
          ) }
        follow_redirect!

        # Assert
        expect(response.body).to include("ambiguous")
      end
    end
  end

  describe "DELETE /estimates/:estimate_id/line_items/:id" do
    it "destroys the line item" do
      # Arrange
      user      = create(:user)
      estimate  = create(:estimate, created_by: user)
      line_item = create(:line_item, estimate: estimate)
      sign_in(user)

      # Act / Assert
      expect {
        delete estimate_line_item_path(estimate, line_item)
      }.to change(LineItem, :count).by(-1)
    end

    it "redirects to the estimate edit page" do
      # Arrange
      user      = create(:user)
      estimate  = create(:estimate, created_by: user)
      line_item = create(:line_item, estimate: estimate)
      sign_in(user)

      # Act
      delete estimate_line_item_path(estimate, line_item)

      # Assert
      expect(response).to redirect_to(edit_estimate_path(estimate))
    end

    it "redirects to login when unauthenticated" do
      # Arrange
      user      = create(:user)
      estimate  = create(:estimate, created_by: user)
      line_item = create(:line_item, estimate: estimate)

      # Act
      delete estimate_line_item_path(estimate, line_item)

      # Assert
      expect(response).to redirect_to(new_session_path)
    end
  end
end
