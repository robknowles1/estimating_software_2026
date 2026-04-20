class LineItemsController < ApplicationController
  before_action :set_estimate

  def new
    @line_item = @estimate.line_items.new
    @products  = Product.by_category
  end

  def create
    product = Product.find_by(id: params.dig(:line_item, :product_id))

    @line_item = @estimate.line_items.new
    product.apply_to(@line_item) if product
    @line_item.assign_attributes(line_item_params)
    @line_item.description = product.name if product && @line_item.description.blank?
    @line_item.product_id = product&.id

    if @line_item.save
      redirect_to edit_estimate_path(@estimate), notice: t(".notice")
    else
      @products = Product.by_category
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @line_item = @estimate.line_items.find(params[:id])
    @products  = Product.by_category
  end

  def update
    @line_item = @estimate.line_items.find(params[:id])

    if @line_item.update(update_line_item_params)
      redirect_to edit_estimate_path(@estimate), notice: t(".notice")
    else
      @products = Product.by_category
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @line_item = @estimate.line_items.find(params[:id])
    @line_item.destroy
    redirect_to edit_estimate_path(@estimate), notice: t(".notice")
  end

  def move
    @line_item = @estimate.line_items.find(params[:id])
    direction  = params[:direction]

    case direction
    when "up"   then @line_item.move_higher
    when "down" then @line_item.move_lower
    end

    redirect_to edit_estimate_path(@estimate)
  end

  SHARED_LINE_ITEM_PARAMS = [
    :description, :quantity, :unit,
    :exterior_material_id, :exterior_qty,
    :interior_material_id, :interior_qty,
    :interior2_material_id, :interior2_qty,
    :back_material_id, :back_qty,
    :banding_material_id,
    :drawers_material_id, :drawers_qty,
    :pulls_material_id, :pulls_qty,
    :hinges_material_id, :hinges_qty,
    :slides_material_id, :slides_qty,
    :locks_qty,
    :other_material_cost,
    :detail_hrs, :mill_hrs, :assembly_hrs, :customs_hrs, :finish_hrs, :install_hrs,
    :equipment_hrs, :equipment_rate
  ].freeze

  private

  def set_estimate
    @estimate = Estimate.includes(line_items: :product, estimate_materials: :material).find(params[:estimate_id])
  end

  def line_item_params
    params.require(:line_item).permit(:product_id, *SHARED_LINE_ITEM_PARAMS)
  end

  def update_line_item_params
    params.require(:line_item).permit(*SHARED_LINE_ITEM_PARAMS)
  end
end
