module Estimates
  class MaterialsController < ApplicationController
    before_action :set_estimate

    layout "estimate"

    def edit
      @materials = @estimate.materials.order(:id)
      @materials_by_category = @materials.group_by(&:category)
    end

    def update
      materials_by_id = @estimate.materials
                                  .where(id: material_ids_from_params)
                                  .index_by { |m| m.id.to_s }

      ActiveRecord::Base.transaction do
        material_attrs_from_params.each do |id, attrs|
          material = materials_by_id[id.to_s]
          next unless material
          material.assign_attributes(attrs.permit(:description, :quote_price))
          material.save!
        end
      end

      redirect_to edit_estimate_materials_path(@estimate), notice: t(".notice")
    rescue ActiveRecord::RecordInvalid => e
      @materials = @estimate.materials.order(:id)
      @materials_by_category = @materials.group_by(&:category)
      flash.now[:alert] = e.message
      render :edit, status: :unprocessable_content
    end

    private

    def set_estimate
      @estimate = Estimate.find(params[:estimate_id])
    end

    def material_ids_from_params
      params[:materials]&.keys || []
    end

    def material_attrs_from_params
      params[:materials] || {}
    end
  end
end
