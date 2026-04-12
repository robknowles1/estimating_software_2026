class LineItemsController < ApplicationController
  before_action :set_estimate
  before_action :set_line_item, only: [ :update, :destroy, :move ]

  def new
    @line_item = @estimate.line_items.new
    render partial: "line_items/new_form", locals: { estimate: @estimate, line_item: @line_item }
  end

  def create
    @line_item = @estimate.line_items.new(line_item_params)
    if @line_item.save
      @totals = EstimateTotalsCalculator.new(@estimate).call
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_estimate_path(@estimate) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :create_error, status: :unprocessable_entity }
        format.html { redirect_to edit_estimate_path(@estimate) }
      end
    end
  end

  def update
    if @line_item.update(line_item_params)
      @totals = EstimateTotalsCalculator.new(@estimate).call
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_estimate_path(@estimate) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update_error, status: :unprocessable_entity }
        format.html { redirect_to edit_estimate_path(@estimate) }
      end
    end
  end

  def destroy
    @line_item.destroy
    @totals = EstimateTotalsCalculator.new(@estimate).call
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to edit_estimate_path(@estimate) }
    end
  end

  def move
    direction = params[:direction]
    @line_item.move_higher if direction == "up"
    @line_item.move_lower  if direction == "down"
    redirect_to edit_estimate_path(@estimate), status: :see_other
  end

  private

  def set_estimate
    @estimate = Estimate.includes(
      :materials,
      line_items: [
        :exterior_material, :interior_material, :interior2_material,
        :back_material, :banding_material, :drawers_material,
        :pulls_material, :hinges_material, :slides_material
      ]
    ).find(params[:estimate_id])
  end

  def set_line_item
    @line_item = @estimate.line_items.find(params[:id])
  end

  def line_item_params
    params.require(:line_item).permit(
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
      :locks_qty, :other_material_cost,
      :detail_hrs, :mill_hrs, :assembly_hrs, :customs_hrs, :finish_hrs, :install_hrs,
      :equipment_hrs, :equipment_rate
    )
  end
end
