require "rails_helper"

RSpec.describe LineItemAliasMatcherService, type: :service do
  describe "#match" do
    context "with a single matching short code" do
      it "assigns exterior_material_id, interior_material_id, interior2_material_id, and back_material_id" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        li = estimate.line_items.new(description: "PL1 Base Cabinet", quantity: 1, unit: "EA")
        service = described_class.new(estimate)

        # Act
        matched = service.match(li)

        # Assert
        expect(matched).to eq(em)
        expect(li.exterior_material_id).to eq(em.id)
        expect(li.interior_material_id).to eq(em.id)
        expect(li.interior2_material_id).to eq(em.id)
        expect(li.back_material_id).to eq(em.id)
      end

      it "returns nil and assigns nothing when description has no match" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        li = estimate.line_items.new(description: "SS5 Upper Cabinet", quantity: 1, unit: "EA")
        service = described_class.new(estimate)

        # Act
        matched = service.match(li)

        # Assert
        expect(matched).to be_nil
        expect(li.exterior_material_id).to be_nil
      end
    end

    context "case-insensitive matching" do
      it "matches when short_code is lowercase and description is uppercase" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "pl1")
        li = estimate.line_items.new(description: "PL1 Base Cabinet", quantity: 1, unit: "EA")
        service = described_class.new(estimate)

        # Act / Assert
        expect(service.match(li)).to eq(em)
      end

      it "matches when short_code is uppercase and description is lowercase" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        li = estimate.line_items.new(description: "pl1 base cabinet", quantity: 1, unit: "EA")
        service = described_class.new(estimate)

        # Act / Assert
        expect(service.match(li)).to eq(em)
      end
    end

    context "longest-match strategy" do
      it "uses the longest short code when both PL and PL1 are defined and description contains PL1" do
        # Arrange
        estimate  = create(:estimate)
        material  = create(:material)
        material2 = create(:material)
        em_short  = create(:estimate_material, estimate: estimate, material: material,  short_code: "PL")
        em_long   = create(:estimate_material, estimate: estimate, material: material2, short_code: "PL1")
        li = estimate.line_items.new(description: "PL1 Cabinet", quantity: 1, unit: "EA")
        service = described_class.new(estimate)

        # Act
        matched = service.match(li)

        # Assert
        expect(matched).to eq(em_long)
        expect(li.exterior_material_id).to eq(em_long.id)
        expect(li.exterior_material_id).not_to eq(em_short.id)
      end
    end

    context "regex-special characters in short code" do
      it "matches short_code containing C+ using String#include? (not regex)" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "C+")
        li = estimate.line_items.new(description: "C+ Cabinet", quantity: 1, unit: "EA")
        service = described_class.new(estimate)

        # Act / Assert
        expect(service.match(li)).to eq(em)
      end

      it "matches short_code containing T.1" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "T.1")
        li = estimate.line_items.new(description: "T.1 Tall Cabinet", quantity: 1, unit: "EA")
        service = described_class.new(estimate)

        # Act / Assert
        expect(service.match(li)).to eq(em)
      end
    end

    context "nil description" do
      it "does not raise and returns nil when description is nil" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        li = estimate.line_items.new(description: nil, quantity: 1, unit: "EA")
        service = described_class.new(estimate)

        # Act / Assert
        expect { service.match(li) }.not_to raise_error
        expect(service.match(li)).to be_nil
      end
    end

    context "overwriting existing slot assignments" do
      it "unconditionally overwrites existing exterior_material_id" do
        # Arrange
        estimate  = create(:estimate)
        material  = create(:material)
        material2 = create(:material)
        em1 = create(:estimate_material, estimate: estimate, material: material,  short_code: "PL1")
        em2 = create(:estimate_material, estimate: estimate, material: material2, short_code: "SS5")
        li = estimate.line_items.new(description: "PL1 Base Cabinet", quantity: 1, unit: "EA")
        service = described_class.new(estimate)

        # Act
        service.match(li)
        expect(li.exterior_material_id).to eq(em1.id)

        li.description = "SS5 Upper Cabinet"
        service.match(li)

        # Assert
        expect(li.exterior_material_id).to eq(em2.id)
      end
    end

    context "empty code_entries" do
      it "returns nil immediately when no short codes are defined" do
        # Arrange
        estimate = create(:estimate)
        li = estimate.line_items.new(description: "PL1 Base Cabinet", quantity: 1, unit: "EA")
        service = described_class.new(estimate)

        # Act / Assert
        expect(service.match(li)).to be_nil
      end
    end
  end

  describe "#ambiguous?" do
    it "returns true when description contains another short code after longest-match selection" do
      # Arrange
      estimate  = create(:estimate)
      material  = create(:material)
      material2 = create(:material)
      create(:estimate_material, estimate: estimate, material: material,  short_code: "PL1")
      create(:estimate_material, estimate: estimate, material: material2, short_code: "SS5")
      li = estimate.line_items.new(description: "PL1 SS5 Cabinet", quantity: 1, unit: "EA")
      service = described_class.new(estimate)

      # Act
      matched = service.match(li)

      # Assert
      expect(service.ambiguous?(li, matched)).to be true
    end

    it "returns false when description contains only one short code" do
      # Arrange
      estimate  = create(:estimate)
      material  = create(:material)
      material2 = create(:material)
      create(:estimate_material, estimate: estimate, material: material,  short_code: "PL1")
      create(:estimate_material, estimate: estimate, material: material2, short_code: "SS5")
      li = estimate.line_items.new(description: "PL1 Cabinet", quantity: 1, unit: "EA")
      service = described_class.new(estimate)

      # Act
      matched = service.match(li)

      # Assert
      expect(service.ambiguous?(li, matched)).to be false
    end

    it "returns false when matched_em is nil" do
      # Arrange
      estimate = create(:estimate)
      service = described_class.new(estimate)
      li = estimate.line_items.new(description: "Unknown Cabinet", quantity: 1, unit: "EA")

      # Act / Assert
      expect(service.ambiguous?(li, nil)).to be false
    end
  end

  describe "#apply_to_all_line_items" do
    context "with 2 matched and 1 unmatched line item" do
      it "returns result with matched: 2, unmatched: 1" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        create(:line_item, estimate: estimate, description: "PL1 Base Cabinet")
        create(:line_item, estimate: estimate, description: "PL1 Wall Cabinet")
        create(:line_item, estimate: estimate, description: "Unknown Cabinet")
        service = described_class.new(estimate)

        # Act
        result = service.apply_to_all_line_items

        # Assert
        expect(result.matched).to eq(2)
        expect(result.unmatched).to eq(1)
      end

      it "saves material slots on matched line items" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        em = create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        li1 = create(:line_item, estimate: estimate, description: "PL1 Base Cabinet")
        li2 = create(:line_item, estimate: estimate, description: "PL1 Wall Cabinet")
        create(:line_item, estimate: estimate, description: "Unknown Cabinet")
        service = described_class.new(estimate)

        # Act
        service.apply_to_all_line_items

        # Assert
        expect(li1.reload.exterior_material_id).to eq(em.id)
        expect(li2.reload.exterior_material_id).to eq(em.id)
      end

      it "does not modify unmatched line items" do
        # Arrange
        estimate = create(:estimate)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        create(:line_item, estimate: estimate, description: "PL1 Base Cabinet")
        create(:line_item, estimate: estimate, description: "PL1 Wall Cabinet")
        li3 = create(:line_item, estimate: estimate, description: "Unknown Cabinet")
        service = described_class.new(estimate)

        # Act
        service.apply_to_all_line_items

        # Assert
        expect(li3.reload.exterior_material_id).to be_nil
      end
    end

    context "transaction rollback on save failure" do
      it "re-raises the error and rolls back all changes" do
        # Arrange — create two matching line items; corrupt the second so save! fails
        estimate = create(:estimate)
        material = create(:material)
        create(:estimate_material, estimate: estimate, material: material, short_code: "PL1")
        li1 = create(:line_item, estimate: estimate, description: "PL1 Cabinet A")
        li2 = create(:line_item, estimate: estimate, description: "PL1 Cabinet B")
        # Corrupt li2's unit at the DB level (nullable column) so the model
        # presence validation fails when the service calls save!
        li2.update_column(:unit, nil)
        service = described_class.new(estimate)

        # Act / Assert
        expect { service.apply_to_all_line_items }.to raise_error(ActiveRecord::RecordInvalid)

        # Both should be nil because transaction rolled back
        expect(li1.reload.exterior_material_id).to be_nil
        expect(li2.reload.exterior_material_id).to be_nil
      end
    end

    context "ambiguous count" do
      it "counts ambiguous matches" do
        # Arrange
        estimate  = create(:estimate)
        material  = create(:material)
        material2 = create(:material)
        create(:estimate_material, estimate: estimate, material: material,  short_code: "PL1")
        create(:estimate_material, estimate: estimate, material: material2, short_code: "SS5")
        create(:line_item, estimate: estimate, description: "PL1 SS5 Cabinet")
        service = described_class.new(estimate)

        # Act
        result = service.apply_to_all_line_items

        # Assert
        expect(result.ambiguous).to eq(1)
      end
    end
  end
end
