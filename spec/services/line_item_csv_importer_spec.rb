require "rails_helper"
require "ostruct"

RSpec.describe LineItemCsvImporter, type: :service do
  let(:estimate) { create(:estimate) }

  # Helper: wrap a CSV string in an object that responds to #read (like an uploaded file)
  def uploaded_file(csv_string)
    OpenStruct.new(read: csv_string)
  end

  def build_row(category: "Base Cabinets", product_number: "BC-001", name: "Base 2-Door",
                marker: "", qty: "2", unit: "EA")
    "#{category},Room A,Kitchen,,#{product_number},#{name},desc,#{marker},#{qty},#{unit},extra"
  end

  # Real CSV Total rows have blank cols 0-6; col 7 = "Total", col 8 = qty, col 9 = unit
  def build_total_row(qty:, unit: "EA")
    ",,,,,,,Total,#{qty},#{unit},extra"
  end

  describe "#call" do
    context "two products, no Total rows" do
      let(:csv) do
        [
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2"),
          build_row(product_number: "BC-002", name: "Wall Cabinet", qty: "3")
        ].join("\n")
      end

      it "creates two line items" do
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(2)
      end

      it "uses each row's qty (no Total override)" do
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        qtys = estimate.line_items.reload.map(&:quantity).map(&:to_i)
        expect(qtys).to contain_exactly(2, 3)
      end

      it "returns line_items_created = 2" do
        result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(result.line_items_created).to eq(2)
      end

      it "returns a nil error" do
        result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(result.error).to be_nil
      end
    end

    context "product spanning multiple room rows followed by a real Total row (blank col 4)" do
      let(:csv) do
        [
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "4"),
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "3"),
          build_total_row(qty: "7"),
          build_row(product_number: "BC-002", name: "Wall Cabinet", qty: "3")
        ].join("\n")
      end

      it "creates one line item per unique product" do
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(2)
      end

      it "uses the Total row qty, not the first room row qty" do
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        base_item = estimate.line_items.reload.find { |li| li.description == "Base 2-Door" }
        expect(base_item.quantity.to_i).to eq(7)
      end
    end

    context "row where col 0 starts with 'z'" do
      let(:csv) do
        [
          build_row(category: "z Clarifications", product_number: "ZZ-999", name: "Skip Me", qty: "5"),
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")
        ].join("\n")
      end

      it "skips the z-category row and creates only one line item" do
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(1)
      end

      it "does not create a product for the skipped row" do
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(Product.where(name: "Skip Me")).not_to exist
      end
    end

    context "row where col 4 (product number) is blank" do
      let(:csv) do
        [
          "Base Cabinets,Room A,Kitchen,,,Blank Number Row,desc,,2,EA,extra",
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")
        ].join("\n")
      end

      it "skips the blank-product-number row" do
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(1)
      end
    end

    context "row where col 4 is '0'" do
      let(:csv) do
        [
          "Base Cabinets,Room A,Kitchen,,0,Zero Row,desc,,2,EA,extra",
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")
        ].join("\n")
      end

      it "skips the zero-product-number row" do
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(1)
      end
    end

    context "product name matches an existing Product (case-insensitive)" do
      let!(:existing_product) do
        create(:product,
               name:         "base 2-door",
               unit:         "EA",
               exterior_qty: BigDecimal("3.0"),
               detail_hrs:   BigDecimal("1.5"))
      end

      let(:csv) { build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2") }

      it "does not create a duplicate product" do
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.not_to change(Product, :count)
      end

      it "links the line item to the existing product" do
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(estimate.line_items.reload.last.product_id).to eq(existing_product.id)
      end

      it "applies apply_to values from the product (exterior_qty)" do
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(estimate.line_items.reload.last.exterior_qty).to eq(BigDecimal("3.0"))
      end

      it "applies labor hours from apply_to" do
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(estimate.line_items.reload.last.detail_hrs).to eq(BigDecimal("1.5"))
      end
    end

    context "product name has no existing match" do
      let(:csv) { build_row(category: "Upper Cabinets", product_number: "UC-010", name: "Upper 1-Door", unit: "EA", qty: "4") }

      it "creates a new Product" do
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(Product, :count).by(1)
      end

      it "sets the correct name on the new product" do
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(Product.last.name).to eq("Upper 1-Door")
      end

      it "sets the correct category on the new product" do
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(Product.last.category).to eq("Upper Cabinets")
      end

      it "sets the correct unit on the new product" do
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(Product.last.unit).to eq("EA")
      end
    end

    context "import appends to an estimate that already has line items" do
      let!(:existing_line_item) { create(:line_item, estimate: estimate, description: "Pre-existing") }
      let(:csv) { build_row(product_number: "BC-001", name: "New Item", qty: "1") }

      it "does not remove pre-existing line items" do
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(estimate.line_items.reload.map(&:description)).to include("Pre-existing")
      end

      it "adds exactly one new line item" do
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(1)
      end

      it "pre-existing line item count is preserved" do
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        descriptions = estimate.line_items.reload.map(&:description)
        expect(descriptions.count { |d| d == "Pre-existing" }).to eq(1)
      end
    end

    context "group with qty <= 0" do
      let(:csv) { build_row(product_number: "BC-001", name: "Zero Qty Item", qty: "0") }

      it "returns a non-nil error" do
        result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(result.error).not_to be_nil
      end

      it "creates no line items (full rollback)" do
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.not_to change(LineItem, :count)
      end

      it "creates no products (full rollback)" do
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.not_to change(Product, :count)
      end
    end

    context "group with negative qty" do
      let(:csv) { build_row(product_number: "BC-001", name: "Neg Qty Item", qty: "-3") }

      it "returns a non-nil error" do
        result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        expect(result.error).not_to be_nil
      end

      it "creates no line items" do
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.not_to change(LineItem, :count)
      end
    end
  end
end
