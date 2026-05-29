require "rails_helper"

RSpec.describe ProductSlotResolver, type: :service do
  describe "#call" do
    context "when a single slot code matches a price book entry" do
      it "assigns pulls_material_id when product pulls_slot_code matches a price book entry" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "PULL1")
        product = create(:product, pulls_slot_code: "PULL1")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act
        resolver.call(line_item)

        # Assert
        expect(line_item.pulls_material_id).to eq(em.id)
      end

      it "leaves pulls_material_id nil when no price book entry matches pulls_slot_code" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "PULL2")
        product = create(:product, pulls_slot_code: "PULL1")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act
        resolver.call(line_item)

        # Assert
        expect(line_item.pulls_material_id).to be_nil
      end

      it "preserves an already-populated pulls_material_id when product slot code does not match any price book entry" do
        # Arrange
        estimate = create(:estimate)
        material_existing = create(:material)
        material_other    = create(:material)
        em_existing = create(:estimate_material, estimate: estimate, material: material_existing, short_code: "EXISTING")
        create(:estimate_material, estimate: estimate, material: material_other, short_code: "PULL2")
        product = create(:product, pulls_slot_code: "PULL1")
        line_item = estimate.line_items.new(
          description: "Test",
          quantity: 1,
          unit: "EA",
          pulls_material_id: em_existing.id
        )
        resolver = described_class.new(product, estimate)

        # Act
        resolver.call(line_item)

        # Assert
        expect(line_item.pulls_material_id).to eq(em_existing.id)
      end
    end

    context "with case-insensitive slot code matching" do
      it "matches when product slot_code is lowercase and price book short_code is uppercase" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "PULL1")
        product = create(:product, pulls_slot_code: "pull1")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act
        resolver.call(line_item)

        # Assert
        expect(line_item.pulls_material_id).to eq(em.id)
      end

      it "matches when product slot_code is uppercase and price book short_code is lowercase" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "pl1")
        product = create(:product, exterior_slot_code: "PL1")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act
        resolver.call(line_item)

        # Assert
        expect(line_item.exterior_material_id).to eq(em.id)
      end
    end

    context "when slot codes are blank or nil" do
      it "does not raise and leaves slot nil when exterior_slot_code is nil" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        product = create(:product, exterior_slot_code: nil)
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act / Assert
        expect { resolver.call(line_item) }.not_to raise_error
        expect(line_item.exterior_material_id).to be_nil
      end

      it "does not raise and leaves slot nil when exterior_slot_code is empty string" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        product = create(:product, exterior_slot_code: "")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act / Assert
        expect { resolver.call(line_item) }.not_to raise_error
        expect(line_item.exterior_material_id).to be_nil
      end
    end

    context "when the price book is empty" do
      it "returns the line item immediately without assigning any slot when price book has no short codes" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: nil)
        product = create(:product, pulls_slot_code: "PULL1", hinges_slot_code: "HINGE1")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act
        result = resolver.call(line_item)

        # Assert
        expect(result).to eq(line_item)
        expect(line_item.pulls_material_id).to be_nil
        expect(line_item.hinges_material_id).to be_nil
      end

      it "is a no-op when the estimate has no estimate_materials at all" do
        # Arrange
        estimate = create(:estimate)
        product = create(:product, exterior_slot_code: "PL1")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act / Assert
        expect { resolver.call(line_item) }.not_to raise_error
        expect(line_item.exterior_material_id).to be_nil
      end
    end

    context "when multiple slot codes all match price book entries" do
      it "assigns all matching material_id columns when product has multiple slot codes" do
        # Arrange
        estimate  = create(:estimate)
        material1 = create(:material)
        material2 = create(:material)
        material3 = create(:material)
        em_pull   = create(:estimate_material, estimate: estimate, material: material1, short_code: "PULL1")
        em_hinge  = create(:estimate_material, estimate: estimate, material: material2, short_code: "HINGE1")
        em_slide  = create(:estimate_material, estimate: estimate, material: material3, short_code: "SLIDE1")
        product = create(:product,
                         pulls_slot_code:  "PULL1",
                         hinges_slot_code: "HINGE1",
                         slides_slot_code: "SLIDE1")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act
        resolver.call(line_item)

        # Assert
        expect(line_item.pulls_material_id).to eq(em_pull.id)
        expect(line_item.hinges_material_id).to eq(em_hinge.id)
        expect(line_item.slides_material_id).to eq(em_slide.id)
        expect(line_item.exterior_material_id).to be_nil
      end
    end

    context "when only some slot codes match price book entries" do
      it "assigns matched slots and leaves unmatched slots nil" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em_banding = create(:estimate_material, estimate: estimate, material: material, short_code: "BANDING3")
        product = create(:product,
                         banding_slot_code: "BANDING3",
                         pulls_slot_code:   "PULL1")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act
        resolver.call(line_item)

        # Assert
        expect(line_item.banding_material_id).to eq(em_banding.id)
        expect(line_item.pulls_material_id).to be_nil
      end
    end

    context "when locks_slot_code is set" do
      it "does not raise and does not attempt a locks_material_id assignment even when locks_slot_code matches a price book entry" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "LOCK1")
        product = create(:product, locks_slot_code: "LOCK1")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act / Assert
        expect { resolver.call(line_item) }.not_to raise_error
        expect(line_item).not_to respond_to(:locks_material_id)
      end
    end

    context "with non-material attributes on the line item" do
      it "returns the unsaved line item" do
        # Arrange
        estimate = create(:estimate)
        product = create(:product, pulls_slot_code: "PULL1")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act
        result = resolver.call(line_item)

        # Assert
        expect(result).to eq(line_item)
        expect(line_item).not_to be_persisted
      end

      it "does not modify quantity or labor hour columns" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "PULL1")
        product = create(:product, pulls_slot_code: "PULL1", exterior_qty: BigDecimal("2.5"), detail_hrs: BigDecimal("1.0"))
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act
        resolver.call(line_item)

        # Assert — qty and labor columns untouched (remain nil since apply_to was not called)
        expect(line_item.exterior_qty).to be_nil
        expect(line_item.detail_hrs).to be_nil
      end
    end

    context "when all nine resolvable slot codes match price book entries" do
      it "assigns all nine material_id columns" do
        # Arrange
        estimate  = create(:estimate)
        materials = 9.times.map { create(:material) }
        codes     = %w[EXT1 INT1 INT2 BACK1 BAND1 DRW1 PULL1 HINGE1 SLIDE1]
        ems = codes.zip(materials).map do |code, mat|
          create(:estimate_material, estimate: estimate, material: mat, short_code: code)
        end
        product = create(:product,
                         exterior_slot_code:  "EXT1",
                         interior_slot_code:  "INT1",
                         interior2_slot_code: "INT2",
                         back_slot_code:      "BACK1",
                         banding_slot_code:   "BAND1",
                         drawers_slot_code:   "DRW1",
                         pulls_slot_code:     "PULL1",
                         hinges_slot_code:    "HINGE1",
                         slides_slot_code:    "SLIDE1")
        line_item = estimate.line_items.new(description: "Test", quantity: 1, unit: "EA")
        resolver = described_class.new(product, estimate)

        # Act
        resolver.call(line_item)

        # Assert
        expect(line_item.exterior_material_id).to eq(ems[0].id)
        expect(line_item.interior_material_id).to eq(ems[1].id)
        expect(line_item.interior2_material_id).to eq(ems[2].id)
        expect(line_item.back_material_id).to eq(ems[3].id)
        expect(line_item.banding_material_id).to eq(ems[4].id)
        expect(line_item.drawers_material_id).to eq(ems[5].id)
        expect(line_item.pulls_material_id).to eq(ems[6].id)
        expect(line_item.hinges_material_id).to eq(ems[7].id)
        expect(line_item.slides_material_id).to eq(ems[8].id)
      end
    end
  end
end
