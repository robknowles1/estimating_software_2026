class ClientNotesController < ApplicationController
  before_action :set_client

  def create
    @client_note = ClientNote.new(client_note_params.merge(client: @client))

    if @client_note.save
      redirect_to client_path(@client), notice: t(".notice")
    else
      @contacts = @client.contacts.alphabetical
      @client_notes = @client.client_notes
      @estimates = @client.estimates.order(updated_at: :desc)
      render "clients/show", status: :unprocessable_content
    end
  end

  def destroy
    @client_note = @client.client_notes.find(params[:id])
    @client_note.destroy
    redirect_to client_path(@client), notice: t(".notice")
  end

  private

  def set_client
    @client = Client.find(params[:client_id])
  end

  def client_note_params
    params.require(:client_note).permit(:body)
  end
end
