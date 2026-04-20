class ProductsController < ApplicationController
  before_action :set_product, only: [ :show, :edit, :update, :destroy ]

  def index
    @products = Product.by_category
  end

  def show
    redirect_to edit_product_path(@product)
  end

  def new
    @product = Product.new
  end

  def create
    @product = Product.new(product_params)
    if @product.save
      redirect_to products_path, notice: t(".notice")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @product.update(product_params)
      redirect_to products_path, notice: t(".notice")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @product.destroy
    redirect_to products_path, notice: t(".notice")
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def product_params
    params.require(:product).permit(
      :name, :category, :unit,
      :exterior_qty, :interior_qty, :interior2_qty, :back_qty,
      :drawers_qty, :pulls_qty, :hinges_qty, :slides_qty, :locks_qty,
      :other_material_cost,
      :detail_hrs, :mill_hrs, :assembly_hrs, :customs_hrs, :finish_hrs, :install_hrs,
      :equipment_hrs, :equipment_rate
    )
  end
end
