require 'rails_helper'

RSpec.describe "Authentication", type: :request do
  describe "protected routes" do
    it "redirects unauthenticated requests to /session/new" do
      get estimates_path
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects unauthenticated requests to users index to /session/new" do
      get users_path
      expect(response).to redirect_to(new_session_path)
    end
  end
end
