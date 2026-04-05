class ClientsController < ApplicationController
  before_action :set_client, only: [ :show, :edit, :update, :destroy ]

  def index
    @clients = Client.alphabetical.includes(:primary_contact)
  end

  def show
    @contacts = @client.contacts.alphabetical
    @contact = Contact.new
  end

  def new
    @client = Client.new
  end

  def create
    @client = Client.new(client_params)

    if @client.save
      redirect_to @client, notice: t(".notice")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @client.update(client_params)
      redirect_to @client, notice: t(".notice")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @client.estimates.any?
      redirect_to @client, alert: t(".blocked")
    else
      @client.destroy
      redirect_to clients_path, notice: t(".notice")
    end
  end

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:company_name, :address, :notes)
  end
end
