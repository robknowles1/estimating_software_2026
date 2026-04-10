class CatalogItemsController < ApplicationController
  before_action :set_catalog_item, only: [ :edit, :update, :destroy ]

  def index
    @catalog_items = CatalogItem.order(:category, :description)
    @catalog_items = @catalog_items.where(category: params[:category]) if params[:category].present?
    @categories = CatalogItem.distinct.pluck(:category).compact.sort
  end

  def new
    @catalog_item = CatalogItem.new
  end

  def create
    @catalog_item = CatalogItem.new(catalog_item_params)

    if @catalog_item.save
      redirect_to catalog_items_path, notice: t(".notice")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @catalog_item.update(catalog_item_params)
      redirect_to catalog_items_path, notice: t(".notice")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @catalog_item.destroy
    redirect_to catalog_items_path, notice: t(".notice"), status: :see_other
  end

  def search
    results = []
    if params[:q].present? && params[:q].length >= 2
      results = CatalogItem.search(params[:q])
    end
    render json: results.map { |item|
      {
        id: item.id,
        description: item.description,
        default_unit: item.default_unit,
        default_unit_cost: item.default_unit_cost
      }
    }
  end

  private

  def set_catalog_item
    @catalog_item = CatalogItem.find(params[:id])
  end

  def catalog_item_params
    params.require(:catalog_item).permit(:description, :default_unit, :default_unit_cost, :category)
  end
end
