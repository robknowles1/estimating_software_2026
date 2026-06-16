class MaterialsController < ApplicationController
  before_action :set_material, only: [ :edit, :update, :destroy ]

  def index
    @query = params[:q].to_s
    scope = @query.present? ? Material.search(@query) : Material.active
    @pagy, @materials = pagy(scope.order(:name), limit: 20)
  rescue Pagy::RangeError => e
    redirect_to materials_path(q: @query.presence, page: e.pagy.last)
  end

  def new
    @material = Material.new
  end

  def create
    @material = Material.new(material_params)
    if @material.save
      redirect_to materials_path, notice: t(".notice")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @material.update(material_params)
      redirect_to materials_path, notice: t(".notice")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @material.discard!
      redirect_to materials_path, notice: t(".notice")
    else
      redirect_to materials_path, alert: @material.errors.full_messages.to_sentence
    end
  end

  private

  def set_material
    @material = Material.find(params[:id])
  end

  def material_params
    params.require(:material).permit(:name, :description, :category, :unit, :default_price)
  end
end
