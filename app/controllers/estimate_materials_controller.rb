class EstimateMaterialsController < ApplicationController
  before_action :set_estimate

  layout "estimate"

  def index
    @estimate_materials = @estimate.estimate_materials.includes(:material).order("materials.name")
    @material_sets      = MaterialSet.order(:name)
  end

  def new
    @mode = params[:mode] || "search"
    @query = params[:q].to_s.strip
    @search_results = @query.present? ? Material.search(@query) : []
    @estimate_material = @estimate.estimate_materials.new
    @material_sets = MaterialSet.order(:name)
  end

  def create
    if params[:material_id].present?
      material = Material.find(params[:material_id])
      em = @estimate.estimate_materials.find_by(material: material)

      if em
        redirect_to estimate_estimate_materials_path(@estimate), notice: t(".already_present")
        return
      end

      em = @estimate.estimate_materials.build(material: material, quote_price: material.default_price)
      if em.save
        redirect_to estimate_estimate_materials_path(@estimate), notice: t(".notice")
      else
        @mode = "search"
        @query = ""
        @search_results = []
        @estimate_material = em
        @material_sets = MaterialSet.order(:name)
        render :new, status: :unprocessable_content
      end
    elsif params[:material].present?
      material = Material.new(new_material_params)
      if material.save
        em = @estimate.estimate_materials.build(material: material, quote_price: material.default_price)
        if em.save
          redirect_to estimate_estimate_materials_path(@estimate), notice: t(".notice")
        else
          @mode = "new"
          @query = ""
          @search_results = []
          @estimate_material = em
          @material_sets = MaterialSet.order(:name)
          render :new, status: :unprocessable_content
        end
      else
        @mode = "new"
        @query = ""
        @search_results = []
        @estimate_material = @estimate.estimate_materials.new
        @new_material = material
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
    p[:role] = p[:role].presence_in(%w[locks])
    p
  end

  def new_material_params
    params.require(:material).permit(:name, :description, :category, :unit, :default_price)
  end
end
