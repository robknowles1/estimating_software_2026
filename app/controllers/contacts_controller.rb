class ContactsController < ApplicationController
  before_action :set_client
  before_action :set_contact, only: [ :edit, :update, :destroy ]

  def new
    @contact = @client.contacts.new
  end

  def create
    @contact = @client.contacts.new(contact_params)

    if @contact.save
      redirect_to @client, notice: t(".notice")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @contact.update(contact_params)
      redirect_to @client, notice: t(".notice")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @contact.destroy
    redirect_to @client, notice: t(".notice")
  end

  private

  def set_client
    @client = Client.find(params[:client_id])
  end

  def set_contact
    @contact = @client.contacts.find(params[:id])
  end

  def contact_params
    params.require(:contact).permit(:first_name, :last_name, :title, :email, :phone, :is_primary, :notes)
  end
end
