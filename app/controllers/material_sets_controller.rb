class MaterialSetsController < ApplicationController
  before_action :set_material_set, only: [ :edit, :update, :destroy, :apply_to_estimate ]

  def index
    @material_sets = MaterialSet.includes(:material_set_items).order(:name)
  end

  def new
    @material_set = MaterialSet.new
    @materials    = Material.active.order(:name)
  end

  def create
    @material_set = MaterialSet.new(material_set_params)
    if @material_set.save
      sync_material_set_items
      redirect_to material_sets_path, notice: t(".notice")
    else
      @materials = Material.active.order(:name)
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @materials = Material.active.order(:name)
  end

  def update
    if @material_set.update(material_set_params)
      sync_material_set_items
      redirect_to material_sets_path, notice: t(".notice")
    else
      @materials = Material.active.order(:name)
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @material_set.destroy
    redirect_to material_sets_path, notice: t(".notice")
  end

  def apply_to_estimate
    estimate = Estimate.find(params[:estimate_id])

    added   = 0
    skipped = 0

    @material_set.material_set_items.includes(:material).each do |item|
      em = EstimateMaterial.find_or_initialize_by(estimate: estimate, material: item.material)
      if em.persisted?
        skipped += 1
      else
        em.quote_price = item.material.default_price
        begin
          if em.save
            added += 1
          else
            skipped += 1
          end
        rescue ActiveRecord::RecordNotUnique
          skipped += 1
        end
      end
    end

    redirect_to estimate_estimate_materials_path(estimate),
                notice: t(".notice", added: added, skipped: skipped)
  end

  private

  def set_material_set
    @material_set = MaterialSet.find(params[:id])
  end

  def material_set_params
    params.require(:material_set).permit(:name)
  end

  # Replaces material_set_items to match the submitted material_ids checkboxes.
  def sync_material_set_items
    submitted_ids = Array(params.dig(:material_set, :material_ids)).map(&:to_i).reject(&:zero?)
    return if submitted_ids.empty? && params.dig(:material_set, :material_ids).nil?

    existing_ids = @material_set.material_set_items.pluck(:material_id)
    to_add    = submitted_ids - existing_ids
    to_remove = existing_ids - submitted_ids

    to_add.each    { |mid| @material_set.material_set_items.create!(material_id: mid) }
    to_remove.each { |mid| @material_set.material_set_items.find_by(material_id: mid)&.destroy }
  end
end
