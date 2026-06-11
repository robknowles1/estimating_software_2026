# Company letterhead used in the commercial proposal PDF header (OQ-A / OQ-B).
#
# Text-only letterhead for v1 (OQ-A); a logo image is a deferred follow-up.
#
# The address block is configurable so it never has to be hardcoded in the PDF
# service: it is read first from Rails encrypted credentials
# (`company.address`), then from the COMPANY_ADDRESS environment variable, and
# finally falls back to the default extracted from Blake's existing proposal
# template.
#
# TODO(OQ-B): confirm exact company name/address block with Blake before first
# production proposal send. The default below is provisional.
module Company
  DEFAULT_ADDRESS = <<~ADDRESS.strip
    TrimArt
    601 Boro Street
    Kaysville, UT 84037
  ADDRESS

  # @return [String] the multi-line letterhead address block.
  def self.address
    Rails.application.credentials.dig(:company, :address).presence ||
      ENV["COMPANY_ADDRESS"].presence ||
      DEFAULT_ADDRESS
  end
end
