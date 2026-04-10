class EstimateSectionsController < ApplicationController
  before_action :set_estimate
  before_action :set_section, only: [ :edit, :update, :destroy, :move ]

  def new
    @section = EstimateSection.new
  end

  def create
    @section = @estimate.estimate_sections.build(section_params)

    if @section.save
      redirect_to edit_estimate_path(@estimate), notice: t(".notice")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @section.update(section_params)
      redirect_to edit_estimate_path(@estimate), notice: t(".notice")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @section.destroy
    redirect_to edit_estimate_path(@estimate), notice: t(".notice")
  end

  def move
    case params[:direction]
    when "up"   then @section.move_higher
    when "down" then @section.move_lower
    else             return head :bad_request
    end
    redirect_to edit_estimate_path(@estimate), status: :see_other
  end

  private

  def set_estimate
    @estimate = Estimate.find(params[:estimate_id])
  end

  def set_section
    @section = @estimate.estimate_sections.find(params[:id])
  end

  def section_params
    params.require(:estimate_section).permit(:name, :default_markup_percent, :quantity)
  end
end
