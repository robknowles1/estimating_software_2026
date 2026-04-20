class EstimateMaterialsController < ApplicationController
  before_action :set_estimate

  layout "estimate"

  def index
    @estimate_materials = @estimate.estimate_materials.includes(:material).order("materials.name")
    @material_sets      = MaterialSet.order(:name)
  end

  def new
    @mode = params[:mode] || "search"
    @materials = Material.active.order(:name)
    @estimate_material = @estimate.estimate_materials.new
    @material_sets = MaterialSet.order(:name)
  end

  def create
    if params[:material_id].present?
      material = Material.active.find(params[:material_id])

      em = @estimate.estimate_materials.build(material: material, quote_price: material.default_price)
      begin
        if em.save
          redirect_to estimate_estimate_materials_path(@estimate), notice: t(".notice")
        elsif em.errors.details[:material_id].any? { |e| e[:error] == :taken }
          redirect_to estimate_estimate_materials_path(@estimate), notice: t(".already_present")
        else
          @mode = "search"
          @materials = Material.active.order(:name)
          @estimate_material = em
          @material_sets = MaterialSet.order(:name)
          render :new, status: :unprocessable_content
        end
      rescue ActiveRecord::RecordNotUnique
        redirect_to estimate_estimate_materials_path(@estimate), notice: t(".already_present")
      end
    elsif params[:material].present?
      material = Material.new(new_material_params)
      em       = nil
      saved    = false

      ActiveRecord::Base.transaction do
        if material.save
          em = @estimate.estimate_materials.build(material: material, quote_price: material.default_price)
          unless em.save
            raise ActiveRecord::Rollback
          end
          saved = true
        end
      end

      if saved
        redirect_to estimate_estimate_materials_path(@estimate), notice: t(".notice")
      else
        @mode = "new"
        @materials = Material.active.order(:name)
        @new_material      = material
        @estimate_material = em || @estimate.estimate_materials.new
        @material_sets = MaterialSet.order(:name)
        render :new, status: :unprocessable_content
      end
    else
      redirect_to new_estimate_estimate_material_path(@estimate)
    end
  end

  def edit
    @estimate_material = @estimate.estimate_materials.find(params[:id])
  end

  def update
    @estimate_material = @estimate.estimate_materials.find(params[:id])
    if @estimate_material.update(estimate_material_params)
      redirect_to estimate_estimate_materials_path(@estimate), notice: t(".notice")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @estimate_material = @estimate.estimate_materials.find(params[:id])
    @estimate_material.destroy
    redirect_to estimate_estimate_materials_path(@estimate), notice: t(".notice")
  end

  private

  def set_estimate
    @estimate = Estimate.find(params[:estimate_id])
  end

  def estimate_material_params
    p = params.require(:estimate_material).permit(:quote_price, :role)
    p[:role] = p[:role].presence_in(EstimateMaterial::ROLES)
    p
  end

  def new_material_params
    params.require(:material).permit(:name, :description, :category, :unit, :default_price)
  end
end
