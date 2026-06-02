require "rails_helper"
require "ostruct"

RSpec.describe LineItemCsvImporter, type: :service do
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
      it "creates two line items" do
        estimate = create(:estimate)
        csv = [
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2"),
          build_row(product_number: "BC-002", name: "Wall Cabinet", qty: "3")
        ].join("\n")
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(2)
      end

      it "uses each row's qty (no Total override)" do
        estimate = create(:estimate)
        csv = [
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2"),
          build_row(product_number: "BC-002", name: "Wall Cabinet", qty: "3")
        ].join("\n")
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        qtys = estimate.line_items.reload.map(&:quantity).map(&:to_i)
        expect(qtys).to contain_exactly(2, 3)
      end

      it "returns line_items_created = 2" do
        estimate = create(:estimate)
        csv = [
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2"),
          build_row(product_number: "BC-002", name: "Wall Cabinet", qty: "3")
        ].join("\n")
        result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(result.line_items_created).to eq(2)
      end

      it "returns a nil error" do
        estimate = create(:estimate)
        csv = [
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2"),
          build_row(product_number: "BC-002", name: "Wall Cabinet", qty: "3")
        ].join("\n")
        result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(result.error).to be_nil
      end
    end

    context "product spanning multiple room rows followed by a real Total row (blank col 4)" do
      it "creates one line item per unique product" do
        estimate = create(:estimate)
        csv = [
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "4"),
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "3"),
          build_total_row(qty: "7"),
          build_row(product_number: "BC-002", name: "Wall Cabinet", qty: "3")
        ].join("\n")
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(2)
      end

      it "uses the Total row qty, not the first room row qty" do
        estimate = create(:estimate)
        csv = [
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "4"),
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "3"),
          build_total_row(qty: "7"),
          build_row(product_number: "BC-002", name: "Wall Cabinet", qty: "3")
        ].join("\n")
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        base_item = estimate.line_items.reload.find { |li| li.description == "Base 2-Door" }
        expect(base_item.quantity.to_i).to eq(7)
      end
    end

    context "row where col 0 starts with 'z'" do
      it "skips the z-category row and creates only one line item" do
        estimate = create(:estimate)
        csv = [
          build_row(category: "z Clarifications", product_number: "ZZ-999", name: "Skip Me", qty: "5"),
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")
        ].join("\n")
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(1)
      end

      it "does not create a product for the skipped row" do
        estimate = create(:estimate)
        csv = [
          build_row(category: "z Clarifications", product_number: "ZZ-999", name: "Skip Me", qty: "5"),
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")
        ].join("\n")
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(Product.where(name: "Skip Me")).not_to exist
      end
    end

    context "row where col 4 (product number) is blank" do
      it "skips the blank-product-number row" do
        estimate = create(:estimate)
        csv = [
          "Base Cabinets,Room A,Kitchen,,,Blank Number Row,desc,,2,EA,extra",
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")
        ].join("\n")
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(1)
      end
    end

    context "row where col 4 is '0'" do
      it "skips the zero-product-number row" do
        estimate = create(:estimate)
        csv = [
          "Base Cabinets,Room A,Kitchen,,0,Zero Row,desc,,2,EA,extra",
          build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")
        ].join("\n")
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(1)
      end
    end

    context "product name matches an existing Product (case-insensitive)" do
      it "does not create a duplicate product" do
        estimate = create(:estimate)
        create(:product, name: "base 2-door", unit: "EA",
               exterior_qty: BigDecimal("3.0"), detail_hrs: BigDecimal("1.5"))
        csv = build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.not_to change(Product, :count)
      end

      it "links the line item to the existing product" do
        estimate = create(:estimate)
        existing_product = create(:product, name: "base 2-door", unit: "EA",
                                  exterior_qty: BigDecimal("3.0"), detail_hrs: BigDecimal("1.5"))
        csv = build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(estimate.line_items.reload.last.product_id).to eq(existing_product.id)
      end

      it "applies apply_to values from the product (exterior_qty)" do
        estimate = create(:estimate)
        create(:product, name: "base 2-door", unit: "EA",
               exterior_qty: BigDecimal("3.0"), detail_hrs: BigDecimal("1.5"))
        csv = build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(estimate.line_items.reload.last.exterior_qty).to eq(BigDecimal("3.0"))
      end

      it "applies labor hours from apply_to" do
        estimate = create(:estimate)
        create(:product, name: "base 2-door", unit: "EA",
               exterior_qty: BigDecimal("3.0"), detail_hrs: BigDecimal("1.5"))
        csv = build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(estimate.line_items.reload.last.detail_hrs).to eq(BigDecimal("1.5"))
      end
    end

    context "product name has no existing match" do
      it "creates a new Product" do
        estimate = create(:estimate)
        csv = build_row(category: "Upper Cabinets", product_number: "UC-010", name: "Upper 1-Door", unit: "EA", qty: "4")
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(Product, :count).by(1)
      end

      it "sets the correct name on the new product" do
        estimate = create(:estimate)
        csv = build_row(category: "Upper Cabinets", product_number: "UC-010", name: "Upper 1-Door", unit: "EA", qty: "4")
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(Product.last.name).to eq("Upper 1-Door")
      end

      it "sets the correct category on the new product" do
        estimate = create(:estimate)
        csv = build_row(category: "Upper Cabinets", product_number: "UC-010", name: "Upper 1-Door", unit: "EA", qty: "4")
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(Product.last.category).to eq("Upper Cabinets")
      end

      it "sets the correct unit on the new product" do
        estimate = create(:estimate)
        csv = build_row(category: "Upper Cabinets", product_number: "UC-010", name: "Upper 1-Door", unit: "EA", qty: "4")
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(Product.last.unit).to eq("EA")
      end
    end

    context "import appends to an estimate that already has line items" do
      it "does not remove pre-existing line items" do
        estimate = create(:estimate)
        create(:line_item, estimate: estimate, description: "Pre-existing")
        csv = build_row(product_number: "BC-001", name: "New Item", qty: "1")
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(estimate.line_items.reload.map(&:description)).to include("Pre-existing")
      end

      it "adds exactly one new line item" do
        estimate = create(:estimate)
        create(:line_item, estimate: estimate, description: "Pre-existing")
        csv = build_row(product_number: "BC-001", name: "New Item", qty: "1")
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.to change(LineItem, :count).by(1)
      end

      it "pre-existing line item count is preserved" do
        estimate = create(:estimate)
        create(:line_item, estimate: estimate, description: "Pre-existing")
        csv = build_row(product_number: "BC-001", name: "New Item", qty: "1")
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        descriptions = estimate.line_items.reload.map(&:description)
        expect(descriptions.count { |d| d == "Pre-existing" }).to eq(1)
      end
    end

    context "group with qty <= 0" do
      it "returns a non-nil error" do
        estimate = create(:estimate)
        csv = build_row(product_number: "BC-001", name: "Zero Qty Item", qty: "0")
        result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(result.error).not_to be_nil
      end

      it "creates no line items (full rollback)" do
        estimate = create(:estimate)
        csv = build_row(product_number: "BC-001", name: "Zero Qty Item", qty: "0")
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.not_to change(LineItem, :count)
      end

      it "creates no products (full rollback)" do
        estimate = create(:estimate)
        csv = build_row(product_number: "BC-001", name: "Zero Qty Item", qty: "0")
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.not_to change(Product, :count)
      end
    end

    context "group with negative qty" do
      it "returns a non-nil error" do
        estimate = create(:estimate)
        csv = build_row(product_number: "BC-001", name: "Neg Qty Item", qty: "-3")
        result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        expect(result.error).not_to be_nil
      end

      it "creates no line items" do
        estimate = create(:estimate)
        csv = build_row(product_number: "BC-001", name: "Neg Qty Item", qty: "-3")
        expect {
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call
        }.not_to change(LineItem, :count)
      end
    end

    # SPEC-022: short code matching during import
    context "SPEC-022: short code matching" do
      context "with a matching short code in the price book" do
        it "assigns exterior_material_id to the matching estimate_material" do
          estimate = create(:estimate)
          material = create(:material)
          em = create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
          csv = build_row(product_number: "BC-001", name: "PL1 Base Cabinet", qty: "2")
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

          li = estimate.line_items.reload.last
          expect(li.exterior_material_id).to eq(em.id)
        end

        it "reports matched_count = 1 and unmatched_count = 0" do
          estimate = create(:estimate)
          material = create(:material)
          create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
          csv = build_row(product_number: "BC-001", name: "PL1 Base Cabinet", qty: "2")
          result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

          expect(result.matched_count).to eq(1)
          expect(result.unmatched_count).to eq(0)
        end
      end

      context "with no matching short code" do
        it "leaves exterior_material_id nil" do
          estimate = create(:estimate)
          material = create(:material)
          create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
          csv = build_row(product_number: "BC-002", name: "Unknown Material", qty: "1")
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

          li = estimate.line_items.reload.last
          expect(li.exterior_material_id).to be_nil
        end

        it "reports unmatched_count = 1" do
          estimate = create(:estimate)
          material = create(:material)
          create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
          csv = build_row(product_number: "BC-002", name: "Unknown Material", qty: "1")
          result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

          expect(result.unmatched_count).to eq(1)
        end
      end

      context "with ambiguous match (two short codes in description)" do
        it "reports ambiguous_count = 1" do
          estimate  = create(:estimate)
          material  = create(:material)
          material2 = create(:material)
          create(:estimate_material, estimate: estimate, material: material,  short_code: "PL1")
          create(:estimate_material, estimate: estimate, material: material2, short_code: "SS5")
          csv = build_row(product_number: "BC-003", name: "PL1 SS5 Cabinet", qty: "1")
          result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

          expect(result.ambiguous_count).to eq(1)
        end
      end

      context "matched_count + unmatched_count equals line_items_created" do
        it "matched_count + unmatched_count equals line_items_created" do
          estimate = create(:estimate)
          material = create(:material)
          create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
          csv = [
            build_row(product_number: "BC-001", name: "PL1 Base Cabinet", qty: "2"),
            build_row(product_number: "BC-002", name: "Unknown Cabinet",   qty: "1")
          ].join("\n")
          result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

          expect(result.matched_count + result.unmatched_count).to eq(result.line_items_created)
        end
      end

      context "rescue path returns all count fields as 0" do
        it "returns Result with all count fields = 0 and error populated" do
          estimate = create(:estimate)
          csv = build_row(product_number: "BC-001", name: "Zero Qty Item", qty: "0")
          result = LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

          expect(result.line_items_created).to eq(0)
          expect(result.matched_count).to eq(0)
          expect(result.unmatched_count).to eq(0)
          expect(result.ambiguous_count).to eq(0)
          expect(result.error).to be_present
        end
      end
    end

    # SPEC-029: ProductSlotResolver integration in CSV import
    context "SPEC-029: ProductSlotResolver runs during import" do
      it "assigns pulls_material_id when the product has pulls_slot_code matching a price book entry" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "PULL1")
        create(:product, name: "base 2-door", unit: "EA", pulls_slot_code: "PULL1")
        csv = build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")

        # Act
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        # Assert
        li = estimate.line_items.reload.last
        expect(li.pulls_material_id).to eq(em.id)
      end

      it "leaves material slots nil when the price book has no short codes" do
        # Arrange
        estimate = create(:estimate)
        create(:product, name: "base 2-door", unit: "EA", pulls_slot_code: "PULL1")
        csv = build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")

        # Act
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        # Assert
        li = estimate.line_items.reload.last
        expect(li.pulls_material_id).to be_nil
      end

      it "assigns multiple slots when multiple product slot codes match price book entries" do
        # Arrange
        estimate = create(:estimate)
        mat1 = create(:material)
        mat2 = create(:material)
        em_pull  = create(:estimate_material, estimate: estimate, material: mat1, short_code: "PULL1")
        em_hinge = create(:estimate_material, estimate: estimate, material: mat2, short_code: "HINGE1")
        create(:product, name: "base 2-door", unit: "EA",
               pulls_slot_code: "PULL1", hinges_slot_code: "HINGE1")
        csv = build_row(product_number: "BC-001", name: "Base 2-Door", qty: "2")

        # Act
        LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

        # Assert
        li = estimate.line_items.reload.last
        expect(li.pulls_material_id).to eq(em_pull.id)
        expect(li.hinges_material_id).to eq(em_hinge.id)
      end

      context "when both resolver and alias matcher match the same primary slot" do
        it "alias matcher result wins: exterior_material_id comes from description short code, not product slot code" do
          # Arrange
          estimate      = create(:estimate)
          mat_slot      = create(:material)
          mat_alias     = create(:material)
          # The product has exterior_slot_code pointing to mat_slot via "EXT1"
          em_slot  = create(:estimate_material, estimate: estimate, material: mat_slot,  short_code: "EXT1")
          # The description contains "PL1" which matches mat_alias via alias matching
          em_alias = create(:estimate_material, estimate: estimate, material: mat_alias, short_code: "PL1")
          create(:product, name: "base 2-door", unit: "EA", exterior_slot_code: "EXT1")
          # Row description includes "PL1" — alias matcher will match em_alias on exterior slot
          csv = build_row(product_number: "BC-001", name: "PL1 Base 2-Door", qty: "2")

          # Act
          LineItemCsvImporter.new(estimate, uploaded_file(csv)).call

          # Assert — alias matcher ran second and overwrote resolver's exterior assignment
          li = estimate.line_items.reload.last
          expect(li.exterior_material_id).to eq(em_alias.id)
        end
      end
    end
  end
end
