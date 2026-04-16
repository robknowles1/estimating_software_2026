require "rails_helper"

RSpec.describe "Products", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  describe "GET /products" do
    it "returns http ok" do
      get products_path
      expect(response).to have_http_status(:ok)
    end

    it "lists products" do
      product = create(:product, name: "Test Cabinet")
      get products_path
      expect(response.body).to include("Test Cabinet")
    end

    it "shows empty state when no products exist" do
      get products_path
      expect(response.body).to include("No products yet")
    end

    it "redirects to login when unauthenticated" do
      delete session_path
      get products_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /products/new" do
    it "returns http ok" do
      get new_product_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects to login when unauthenticated" do
      delete session_path
      get new_product_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "POST /products" do
    let(:valid_params) do
      {
        product: {
          name: "MDF Base 2-door",
          category: "Base Cabinets",
          unit: "EA",
          exterior_description: "MDF",
          exterior_unit_price: "45.00",
          exterior_qty: "2.5",
          detail_hrs: "0.75"
        }
      }
    end

    context "with valid params" do
      it "creates a product and redirects to products index" do
        expect {
          post products_path, params: valid_params
        }.to change(Product, :count).by(1)

        expect(response).to redirect_to(products_path)
      end

      it "persists all submitted fields" do
        post products_path, params: valid_params
        product = Product.last
        expect(product.name).to eq("MDF Base 2-door")
        expect(product.category).to eq("Base Cabinets")
        expect(product.exterior_description).to eq("MDF")
        expect(product.exterior_unit_price).to eq(BigDecimal("45.00"))
        expect(product.exterior_qty).to eq(BigDecimal("2.5"))
        expect(product.detail_hrs).to eq(BigDecimal("0.75"))
      end
    end

    context "with blank name" do
      it "returns unprocessable entity" do
        post products_path, params: { product: { name: "", unit: "EA" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not create a product" do
        expect {
          post products_path, params: { product: { name: "", unit: "EA" } }
        }.not_to change(Product, :count)
      end
    end

    it "redirects to login when unauthenticated" do
      delete session_path
      post products_path, params: { product: { name: "Test", unit: "EA" } }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /products/:id/edit" do
    let(:product) { create(:product) }

    it "returns http ok" do
      get edit_product_path(product)
      expect(response).to have_http_status(:ok)
    end

    it "redirects to login when unauthenticated" do
      delete session_path
      get edit_product_path(product)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "PATCH /products/:id" do
    let(:product) { create(:product, name: "Old Name") }

    context "with valid params" do
      it "updates the product and redirects to products index" do
        patch product_path(product), params: { product: { name: "New Name", unit: product.unit } }
        expect(response).to redirect_to(products_path)
        expect(product.reload.name).to eq("New Name")
      end
    end

    context "with blank name" do
      it "returns unprocessable entity" do
        patch product_path(product), params: { product: { name: "", unit: product.unit } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "redirects to login when unauthenticated" do
      delete session_path
      patch product_path(product), params: { product: { name: "Test", unit: "EA" } }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "DELETE /products/:id" do
    let!(:product) { create(:product) }

    it "destroys the product and redirects to products index" do
      expect {
        delete product_path(product)
      }.to change(Product, :count).by(-1)

      expect(response).to redirect_to(products_path)
    end

    it "sets product_id to null on line items referencing this product" do
      estimate = create(:estimate)
      line_item = create(:line_item, estimate: estimate, product: product)

      delete product_path(product)
      expect(line_item.reload.product_id).to be_nil
    end

    it "redirects to login when unauthenticated" do
      delete session_path
      delete product_path(product)
      expect(response).to redirect_to(new_session_path)
    end
  end
end
