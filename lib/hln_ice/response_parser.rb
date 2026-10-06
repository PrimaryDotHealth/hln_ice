# frozen_string_literal: true

require "base64"
require "json"
require "nokogiri"

module HlnIce
  # Parses the body of an ICE evaluate response into the result data:
  # patient, recommendations, evaluations, and simplified status.
  #
  # Does no logging; the Client decides what may be logged.
  class ResponseParser
    include Support

    def initialize(response_body)
      @response_body = response_body
    end

    # Returns nil when the response carries no vMR payload. Raises if the
    # body cannot be parsed.
    def data
      result = JSON.parse(response_body)

      base64_result = result.dig("finalKMEvaluationResponse", 0, "kmEvaluationResultData", 0, "data",
                                 "base64EncodedPayload", 0)
      return unless base64_result

      # Parse the XML response
      parse_xml_response(Base64.decode64(base64_result))
    end

    private
      attr_reader :response_body

      def parse_xml_response(xml_string)
        # Parse the XML
        doc = Nokogiri::XML(xml_string)

        # Remove namespaces to simplify parsing
        doc.remove_namespaces!

        # Extract patient information
        patient = doc.xpath("//patient").first
        return { raw_xml: xml_string } unless patient

        patient_id = patient.xpath("./id").first&.[]("extension")
        birth_time = patient.xpath("./demographics/birthTime").first&.[]("value")
        gender = patient.xpath("./demographics/gender").first&.[]("code")

        # Format birth date if present
        birth_date = format_ice_date(birth_time)

        # Extract vaccine recommendations
        all_recommendations = []

        doc.xpath("//substanceAdministrationProposal").each do |proposal|
          # Get the substance code and name
          substance_element = proposal.xpath("./substance/substanceCode").first
          next unless substance_element

          vaccine_code        = substance_element["code"]
          vaccine_name        = substance_element["displayName"]
          vaccine_code_system = substance_element["codeSystem"]

          # Get the clinical observation result carrying the recommendation status.
          # A proposal may contain other observation results (e.g. schedule
          # authorities), in any order, so select the one with a status concept.
          observation = proposal.xpath(".//observationResult[observationValue/concept]").first
          next unless observation

          # Get recommendation status
          status_element = observation.xpath(".//observationValue/concept").first

          status_code = status_element["code"]
          status_name = status_element["displayName"]

          # Get interpretation reasons
          reasons = []
          observation.xpath(".//interpretation").each do |interpretation|
            reason = {
              code: interpretation["code"],
              name: interpretation["displayName"]
            }

            # Add supplemental text if available
            reason[:supplemental_text] = interpretation["originalText"] if interpretation["originalText"]

            reasons << reason
          end

          # Get administration time intervals if available
          proposed_interval = proposal.xpath("./proposedAdministrationTimeInterval").first
          valid_interval = proposal.xpath("./validAdministrationTimeInterval").first

          intervals = {}
          if proposed_interval
            intervals[:proposed] = {
              low: format_ice_date(proposed_interval["low"]),
              high: format_ice_date(proposed_interval["high"])
            }.compact
          end

          if valid_interval
            intervals[:valid] = {
              low: format_ice_date(valid_interval["low"]),
              high: format_ice_date(valid_interval["high"])
            }.compact
          end

          # Build the recommendation object
          recommendation = {
            vaccine: {
              code: vaccine_code,
              code_system: vaccine_code_system,
              name: vaccine_name
            },
            status: {
              code: status_code,
              name: status_name
            },
            reasons:
          }

          # Only add intervals if they exist
          recommendation[:intervals] = intervals if present?(intervals)

          # Only add schedule authorities if the service returned them
          # (requires the ICE outputScheduleAuthorities property)
          schedule_authorities = parse_schedule_authorities(proposal)
          recommendation[:schedule_authorities] = schedule_authorities if present?(schedule_authorities)

          all_recommendations << recommendation
        end

        # Build the final result structure
        {
          raw_xml: xml_string,
          patient: {
            id: patient_id,
            birth_date: birth_date || birth_time,
            gender:
          }.compact,
          recommendations: all_recommendations, # Keep the original flat list for backward compatibility
          evaluations: EvaluationsParser.new(patient).evaluations,
          simplified_status: SimplifiedStatus.new(all_recommendations).to_h
        }
      end

      # Extract the schedule authorities (e.g. ACIP_CDC, AAP) for a proposal.
      # Returns an empty array when the service did not include them.
      def parse_schedule_authorities(proposal)
        authorities = proposal.xpath(
          ".//observationResult[observationFocus/@code='ICE_VACCINE_GROUP_SCHEDULE_AUTHORITIES']/interpretation"
        )

        authorities.map do |interpretation|
          {
            code: interpretation["code"],
            name: interpretation["displayName"]
          }
        end
      end
  end
end
