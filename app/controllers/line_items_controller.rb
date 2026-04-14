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

    if @line_item.update(line_item_params)
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

  private

  def set_estimate
    @estimate = Estimate.includes(line_items: :product).find(params[:estimate_id])
  end

  def line_item_params
    params.require(:line_item).permit(
      :description, :quantity, :unit, :product_id,
      :exterior_description, :exterior_unit_price, :exterior_qty,
      :interior_description, :interior_unit_price, :interior_qty,
      :interior2_description, :interior2_unit_price, :interior2_qty,
      :back_description, :back_unit_price, :back_qty,
      :banding_description, :banding_unit_price,
      :drawers_description, :drawers_unit_price, :drawers_qty,
      :pulls_description, :pulls_unit_price, :pulls_qty,
      :hinges_description, :hinges_unit_price, :hinges_qty,
      :slides_description, :slides_unit_price, :slides_qty,
      :locks_description, :locks_unit_price, :locks_qty,
      :other_material_cost,
      :detail_hrs, :mill_hrs, :assembly_hrs, :customs_hrs, :finish_hrs, :install_hrs,
      :equipment_hrs, :equipment_rate
    )
  end
end
