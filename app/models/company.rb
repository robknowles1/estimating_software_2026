module Company
  DEFAULT_ADDRESS = "601 Boro Street, Kaysville, UT 84037  |  801.656.6529  |  bids@trim-art.com".freeze
  CONTACT_NAME    = "Blake Montgomery".freeze
  CONTACT_PHONE   = "801.656.6529".freeze
  CONTACT_EMAIL   = "blake@trim-art.com".freeze
  CONTACT_WEBSITE = "www.trim-art.com".freeze

  def self.address
    Rails.application.credentials.dig(:company, :address).presence ||
      ENV["COMPANY_ADDRESS"].presence ||
      DEFAULT_ADDRESS
  end
end
