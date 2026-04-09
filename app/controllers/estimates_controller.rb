class EstimatesController < ApplicationController
  before_action :set_estimate, only: [ :show, :edit, :update, :destroy ]

  def index
    @estimates = Estimate.includes(:client)
                         .with_status(params[:status])
                         .search(params[:q])
                         .order(updated_at: :desc)
    @status_filter = params[:status]
    @search_query = params[:q]
  end

  def show
    redirect_to edit_estimate_path(@estimate)
  end

  def new
    @estimate = Estimate.new
    @clients = Client.alphabetical
  end

  def create
    @estimate = Estimate.new(estimate_params)
    @estimate.created_by_user_id = current_user.id

    if @estimate.save
      redirect_to edit_estimate_path(@estimate), notice: t(".notice")
    else
      @clients = Client.alphabetical
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @estimate = Estimate
      .includes(:estimate_materials, estimate_sections: { line_items: :estimate_material })
      .find(params[:id])
    @sections = @estimate.estimate_sections
    @new_section = EstimateSection.new
    @clients = Client.alphabetical
    @totals = EstimateTotalsCalculator.new(@estimate).call
  end

  def update
    if @estimate.update(estimate_params)
      redirect_to edit_estimate_path(@estimate), notice: t(".notice")
    else
      @estimate = Estimate
        .includes(:estimate_materials, estimate_sections: { line_items: :estimate_material })
        .find(@estimate.id)
      @sections = @estimate.estimate_sections
      @new_section = EstimateSection.new
      @clients = Client.alphabetical
      @totals = EstimateTotalsCalculator.new(@estimate).call
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @estimate.destroy
    redirect_to estimates_path, notice: t(".notice")
  end

  private

  def set_estimate
    @estimate = Estimate.find(params[:id])
  end

  def estimate_params
    params.require(:estimate).permit(
      :client_id, :title, :status, :job_start_date, :job_end_date, :notes, :client_notes,
      :miles_to_jobsite, :installer_crew_size, :delivery_crew_size, :on_site_time_hrs,
      :profit_overhead_percent, :pm_supervision_percent
    )
  end
end
