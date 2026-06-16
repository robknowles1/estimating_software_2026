module Company
  DEFAULT_ADDRESS = <<~ADDRESS.strip
    TrimArt
    601 Boro Street
    Kaysville, UT 84037
  ADDRESS

  def self.address
    Rails.application.credentials.dig(:company, :address).presence ||
      ENV["COMPANY_ADDRESS"].presence ||
      DEFAULT_ADDRESS
  end
end
