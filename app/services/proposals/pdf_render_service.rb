require "prawn"
require "prawn/table"

module Proposals
  class PdfRenderService
    include ActionView::Helpers::NumberHelper
    include ProposalHelper

    BRAND_COLOR = "1F2937".freeze # slate-800
    MUTED_COLOR = "6B7280".freeze # slate-500

    def initialize(proposal:)
      @proposal = preload(proposal)
    end

    def call
      document.render
    end

    private

    attr_reader :proposal

    def preload(proposal)
      Proposal
        .includes(:contact, :proposal_clarifications, :proposal_alternates,
                  :proposal_exclusions, :proposal_specifications,
                  proposal_inclusions: { photos_attachments: :blob })
        .find(proposal.id)
    end

    def document
      # The default AFM fonts use the WinAnsi (Windows-1252) encoding, which
      # covers the characters used in proposal copy (including the en dash and
      # bullet); suppress the i18n warning since no text beyond WinAnsi is
      # rendered.
      Prawn::Fonts::AFM.hide_m17n_warning = true
      Prawn::Document.new(page_size: "LETTER", margin: 54).tap do |pdf|
        if proposal.residential?
          render_residential(pdf)
        else
          render_commercial(pdf)
        end
      end
    end

    def render_commercial(pdf)
      render_letterhead(pdf)
      render_date(pdf)
      render_salutation(pdf)
      render_opening_paragraph(pdf)
      render_specifications(pdf) if proposal.include_specifications?
      render_inclusions(pdf, with_photos: true)
      render_clarifications(pdf)
      render_alternates(pdf)
      render_exclusions(pdf)
    end

    def render_residential(pdf)
      render_letterhead(pdf)
      render_date(pdf)
      render_salutation(pdf)
      render_residential_narrative(pdf)
      render_room_pricing_table(pdf)
      render_alternates(pdf)
      render_payment_terms(pdf)
    end

    def render_letterhead(pdf)
      pdf.text Company.address, leading: 2, color: BRAND_COLOR
      pdf.move_down 18
    end

    def render_date(pdf)
      pdf.text Date.current.strftime("%B %-d, %Y"), color: MUTED_COLOR
      pdf.move_down 14
    end

    def render_salutation(pdf)
      first_name = proposal.contact&.first_name.presence || "Sir or Madam"
      pdf.text "Dear #{first_name},"
      pdf.move_down 12
    end

    def render_opening_paragraph(pdf)
      job_name = proposal.job_name.presence || "this project"
      plan_date = proposal.plan_date&.strftime("%B %-d, %Y") || "the referenced date"
      addenda = proposal.addendum_list.presence || "none"
      amount = number_to_currency(proposal.total_amount || 0)
      words = amount_in_words(proposal.total_amount)

      paragraph = "Thank you for the opportunity to bid the #{job_name}. " \
                  "This proposal is based on plans dated #{plan_date} and " \
                  "addenda #{addenda}. The total for the items listed below " \
                  "is #{amount} (#{words})."
      pdf.text paragraph, leading: 2, align: :justify
      pdf.move_down 16
    end

    def render_specifications(pdf)
      return if proposal.proposal_specifications.empty?

      heading(pdf, "Specifications")
      proposal.proposal_specifications.each do |spec|
        pdf.text "#{spec.spec_number} – #{spec.spec_title}", leading: 2
      end
      pdf.move_down 14
    end

    def render_inclusions(pdf, with_photos:)
      return if proposal.proposal_inclusions.empty?

      heading(pdf, "Specific Inclusions")
      proposal.proposal_inclusions.each do |inclusion|
        pdf.text inclusion.room_name.to_s, style: :bold
        render_bullet_points(pdf, inclusion.bullet_points)
        render_photos(pdf, inclusion) if with_photos
        pdf.move_down 10
      end
      pdf.move_down 6
    end

    def render_bullet_points(pdf, bullet_points)
      return if bullet_points.blank?

      bullet_points.to_s.split("\n").map(&:strip).reject(&:empty?).each do |line|
        pdf.text "• #{line}", indent_paragraphs: 10, leading: 2
      end
    end

    def render_photos(pdf, inclusion)
      return unless inclusion.photos.attached?

      inclusion.photos.each do |photo|
        embed_photo(pdf, photo)
      end
    end

    def embed_photo(pdf, photo)
      variant = photo.variant(:pdf).processed
      io = StringIO.new(variant.download)
      pdf.move_down 4
      pdf.image io, fit: [ 360, 240 ]
    rescue Vips::Error, ImageProcessing::Error, ActiveStorage::Error => e
      Rails.logger.warn("[PdfRenderService] skipped photo #{photo.id}: #{e.class}: #{e.message}")
    end

    def render_clarifications(pdf)
      return if proposal.proposal_clarifications.empty?

      heading(pdf, "Design Clarifications")
      proposal.proposal_clarifications.each do |clarification|
        pdf.text "• #{clarification.body}", leading: 2
      end
      pdf.move_down 14
    end

    def render_alternates(pdf)
      return if proposal.proposal_alternates.empty?

      heading(pdf, "Alternates")
      rows = proposal.proposal_alternates.map do |alternate|
        [ alternate.description.to_s, number_to_currency(alternate.display_cost || 0) ]
      end
      pdf.table([ [ "Description", "Cost" ] ] + rows, width: pdf.bounds.width) do |table|
        table.row(0).font_style = :bold
        table.columns(1).align = :right
        table.cells.padding = [ 4, 6 ]
        table.cells.borders = [ :bottom ]
      end
      pdf.move_down 14
    end

    def render_exclusions(pdf)
      return if proposal.proposal_exclusions.empty?

      heading(pdf, "Exclusions")
      proposal.proposal_exclusions.each do |exclusion|
        pdf.text "• #{exclusion.body}", leading: 2
      end
      pdf.move_down 14
    end

    def render_residential_narrative(pdf)
      job_name = proposal.job_name.presence || "this project"
      amount = number_to_currency(proposal.total_amount || 0)
      words = amount_in_words(proposal.total_amount)

      paragraph = "Thank you for the opportunity to bid the #{job_name}. The " \
                  "scope below covers all materials and labor required to " \
                  "complete the work as described. The total for the work is " \
                  "#{amount} (#{words})."
      pdf.text paragraph, leading: 2, align: :justify
      pdf.move_down 16
    end

    def render_room_pricing_table(pdf)
      return if proposal.proposal_inclusions.empty?

      heading(pdf, "Room-by-Room Pricing")
      rows = proposal.proposal_inclusions.map do |inclusion|
        [ inclusion.room_name.to_s, room_description(inclusion) ]
      end
      pdf.table([ [ "Room", "Scope" ] ] + rows, width: pdf.bounds.width) do |table|
        table.row(0).font_style = :bold
        table.cells.padding = [ 4, 6 ]
        table.cells.borders = [ :bottom ]
        table.column(0).width = 140
      end
      pdf.move_down 14
    end

    def room_description(inclusion)
      inclusion.bullet_points.to_s.split("\n").map(&:strip).reject(&:empty?).join("; ")
    end

    def render_payment_terms(pdf)
      return if proposal.payment_terms.blank?

      heading(pdf, "Payment Terms")
      pdf.text proposal.payment_terms, leading: 2
      pdf.move_down 14
    end

    def heading(pdf, text)
      pdf.text text, style: :bold, size: 13, color: BRAND_COLOR
      pdf.move_down 6
    end
  end
end
