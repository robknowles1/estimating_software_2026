require "rails_helper"

RSpec.describe "Products", type: :request do
  describe "GET /products" do
    it "returns http ok" do
      user = create(:user)
      sign_in(user)
      get products_path
      expect(response).to have_http_status(:ok)
    end

    it "lists products" do
      user = create(:user)
      sign_in(user)
      create(:product, name: "Test Cabinet")
      get products_path
      expect(response.body).to include("Test Cabinet")
    end

    it "shows empty state when no products exist" do
      user = create(:user)
      sign_in(user)
      get products_path
      expect(response.body).to include("No products yet")
    end

    it "redirects to login when unauthenticated" do
      get products_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /products/new" do
    it "returns http ok" do
      user = create(:user)
      sign_in(user)
      get new_product_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects to login when unauthenticated" do
      get new_product_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "POST /products" do
    context "with valid params" do
      it "creates a product and redirects to products index" do
        user = create(:user)
        sign_in(user)
        expect {
          post products_path, params: {
            product: {
              name: "MDF Base 2-door",
              category: "Base Cabinets",
              unit: "EA",
              exterior_qty: "2.5",
              detail_hrs: "0.75"
            }
          }
        }.to change(Product, :count).by(1)

        expect(response).to redirect_to(products_path)
      end

      it "persists all submitted fields" do
        user = create(:user)
        sign_in(user)
        post products_path, params: {
          product: {
            name: "MDF Base 2-door",
            category: "Base Cabinets",
            unit: "EA",
            exterior_qty: "2.5",
            detail_hrs: "0.75"
          }
        }
        product = Product.last
        expect(product.name).to eq("MDF Base 2-door")
        expect(product.category).to eq("Base Cabinets")
        expect(product.exterior_qty).to eq(BigDecimal("2.5"))
        expect(product.detail_hrs).to eq(BigDecimal("0.75"))
      end
    end

    context "with blank name" do
      it "returns unprocessable entity" do
        user = create(:user)
        sign_in(user)
        post products_path, params: { product: { name: "", unit: "EA" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not create a product" do
        user = create(:user)
        sign_in(user)
        expect {
          post products_path, params: { product: { name: "", unit: "EA" } }
        }.not_to change(Product, :count)
      end
    end

    it "redirects to login when unauthenticated" do
      post products_path, params: { product: { name: "Test", unit: "EA" } }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /products/:id/edit" do
    it "returns http ok" do
      user = create(:user)
      sign_in(user)
      product = create(:product)
      get edit_product_path(product)
      expect(response).to have_http_status(:ok)
    end

    it "includes the Material Slot Codes section heading" do
      user = create(:user)
      sign_in(user)
      product = create(:product)
      get edit_product_path(product)
      expect(response.body).to include("Material Slot Codes")
    end

    it "includes a slot code input for exterior_slot_code" do
      user = create(:user)
      sign_in(user)
      product = create(:product)
      get edit_product_path(product)
      expect(response.body).to include("product[exterior_slot_code]")
    end

    it "redirects to login when unauthenticated" do
      product = create(:product)
      get edit_product_path(product)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "PATCH /products/:id" do
    context "with valid params" do
      it "updates the product and redirects to products index" do
        user = create(:user)
        sign_in(user)
        product = create(:product, name: "Old Name")
        patch product_path(product), params: { product: { name: "New Name", unit: product.unit } }
        expect(response).to redirect_to(products_path)
        expect(product.reload.name).to eq("New Name")
      end
    end

    context "with blank name" do
      it "returns unprocessable entity" do
        user = create(:user)
        sign_in(user)
        product = create(:product, name: "Old Name")
        patch product_path(product), params: { product: { name: "", unit: product.unit } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    # SPEC-029: slot code params are permitted and persisted
    context "SPEC-029: updating exterior_slot_code" do
      it "persists exterior_slot_code and redirects" do
        user = create(:user)
        sign_in(user)
        product = create(:product, name: "Cabinet", unit: "EA")
        patch product_path(product), params: {
          product: { name: product.name, unit: product.unit, exterior_slot_code: "PL1" }
        }
        expect(response).to redirect_to(products_path)
        expect(product.reload.exterior_slot_code).to eq("PL1")
      end

      it "stores nil when exterior_slot_code is blank" do
        user = create(:user)
        sign_in(user)
        product = create(:product, name: "Cabinet", unit: "EA", exterior_slot_code: "PL1")
        patch product_path(product), params: {
          product: { name: product.name, unit: product.unit, exterior_slot_code: "" }
        }
        expect(product.reload.exterior_slot_code).to be_nil
      end
    end

    it "redirects to login when unauthenticated" do
      product = create(:product, name: "Cabinet", unit: "EA")
      patch product_path(product), params: { product: { name: "Test", unit: "EA" } }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "DELETE /products/:id" do
    it "destroys the product and redirects to products index" do
      user = create(:user)
      sign_in(user)
      product = create(:product)
      expect {
        delete product_path(product)
      }.to change(Product, :count).by(-1)

      expect(response).to redirect_to(products_path)
    end

    it "sets product_id to null on line items referencing this product" do
      user = create(:user)
      sign_in(user)
      product = create(:product)
      estimate = create(:estimate)
      line_item = create(:line_item, estimate: estimate, product: product)

      delete product_path(product)
      expect(line_item.reload.product_id).to be_nil
    end

    it "redirects to login when unauthenticated" do
      product = create(:product)
      delete product_path(product)
      expect(response).to redirect_to(new_session_path)
    end
  end
end
