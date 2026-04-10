module Estimates
  class MaterialsController < ApplicationController
    before_action :set_estimate

    def edit
      @materials = @estimate.estimate_materials.order(:category, :slot_number)
      @materials_by_category = @materials.group_by(&:category)
    end

    def update
      materials_by_id = @estimate.estimate_materials
                                  .where(id: materials_params.keys)
                                  .index_by { |m| m.id.to_s }

      ActiveRecord::Base.transaction do
        materials_params.each do |id, attrs|
          material = materials_by_id[id.to_s]
          next unless material
          material.update!(attrs.permit(:description, :price_per_unit, :unit))
        end
      end

      redirect_to edit_estimate_materials_path(@estimate), notice: t(".notice")
    rescue ActiveRecord::RecordInvalid => e
      @materials = @estimate.estimate_materials.order(:category, :slot_number)
      @materials_by_category = @materials.group_by(&:category)
      flash.now[:alert] = e.message
      render :edit, status: :unprocessable_content
    end

    private

    def set_estimate
      @estimate = Estimate.find(params[:estimate_id])
    end

    def materials_params
      params.require(:estimate_materials)
    end
  end
end
