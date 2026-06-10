class ContactsController < ApplicationController
  before_action :set_client
  before_action :set_contact, only: [ :edit, :update, :destroy ]

  def new
    @contact = @client.contacts.new
  end

  def create
    @contact = @client.contacts.new(contact_params)

    if @contact.save
      respond_to do |format|
        format.html { redirect_to @client, notice: t(".notice") }
        # Renders create.turbo_stream.erb (implicit template) after loading the
        # proposal context used to rebuild the wizard's contact field.
        format.turbo_stream { set_proposal_contact_context }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_content }
        # create_error.turbo_stream.erb re-renders just the modal frame with the
        # validation errors and echoes params[:estimate_id] back into the hidden
        # field unchanged, so no estimate lookup is needed here.
        format.turbo_stream { render "create_error", status: :unprocessable_content }
      end
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

  # When the contact is created from the proposal wizard's inline modal, the form
  # carries an estimate_id (read from params, NOT mass-assigned to the contact)
  # so the success Turbo Stream can rebuild that wizard's contact field with the
  # new contact auto-selected. Guard that the estimate's client matches @client
  # before exposing it. The new contact id is exposed so the rebuilt field can
  # pre-select it.
  def set_proposal_contact_context
    @estimate = Estimate.find_by(id: params[:estimate_id])
    @estimate = nil unless @estimate&.client_id == @client.id
    @proposal = @estimate&.proposal || Proposal.new(contact_id: @contact.id)
    @proposal.contact_id = @contact.id
    @contacts = @client.contacts.alphabetical
  end

  def contact_params
    params.require(:contact).permit(:first_name, :last_name, :title, :email, :phone, :is_primary, :notes, :role)
  end
end
