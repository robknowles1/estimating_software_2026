class LineItemsController < ApplicationController
  before_action :set_estimate
  before_action :set_estimate_section
  before_action :set_line_item, only: [ :edit, :update, :destroy, :move ]

  def new
    @line_item = @section.line_items.build(
      line_item_category: "material",
      markup_percent: @section.default_markup_percent
    )
  end

  def create
    @line_item = @section.line_items.build(line_item_params)
    @line_item.markup_percent = @section.default_markup_percent unless line_item_params.key?(:markup_percent)

    if @line_item.save
      @totals = calculate_totals
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_estimate_path(@estimate), notice: t(".notice") }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("line_item_form_#{@section.id}", partial: "line_items/new_form", locals: { section: @section, estimate: @estimate, line_item: @line_item }) }
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  def edit
  end

  def update
    if @line_item.update(line_item_params)
      @totals = calculate_totals
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_estimate_path(@estimate), notice: t(".notice") }
      end
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @line_item.destroy
    @totals = calculate_totals
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to edit_estimate_path(@estimate), notice: t(".notice") }
    end
  end

  def move
    if params[:direction] == "up"
      @line_item.move_higher
    else
      @line_item.move_lower
    end
    redirect_to edit_estimate_path(@estimate), status: :see_other
  end

  private

  def set_estimate
    # All authenticated users can access all estimates — single-company internal tool.
    @estimate = Estimate.find(params[:estimate_id])
  end

  def set_estimate_section
    @section = @estimate.estimate_sections.find(params[:estimate_section_id])
  end

  def set_line_item
    @line_item = @section.line_items.find(params[:id])
  end

  def line_item_params
    params.require(:line_item).permit(
      :description,
      :line_item_category,
      :component_type,
      :labor_category,
      :estimate_material_id,
      :component_quantity,
      :hours_per_unit,
      :freeform_quantity,
      :unit_cost,
      :markup_percent,
      :unit,
      :notes
    )
  end

  def calculate_totals
    estimate_with_preloads = Estimate
      .includes(estimate_sections: { line_items: :estimate_material })
      .find(@estimate.id)
    EstimateTotalsCalculator.new(estimate_with_preloads).call
  end
end
