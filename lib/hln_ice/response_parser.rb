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
        doc = Nokogiri::XML(xml_string)

        # Remove namespaces to simplify parsing
        doc.remove_namespaces!

        patient = doc.at_xpath("/cdsOutput/vmrOutput/patient")
        return { raw_xml: xml_string } unless patient

        recommendations = parse_recommendations(patient)

        {
          raw_xml: xml_string,
          patient: parse_patient(patient),
          recommendations:,
          evaluations: EvaluationsParser.new(patient).evaluations,
          simplified_status: SimplifiedStatus.new(recommendations).to_h
        }
      end

      def parse_patient(patient)
        birth_time = patient.at_xpath("./demographics/birthTime")&.[]("value")

        {
          id: patient.at_xpath("./id")&.[]("extension"),
          birth_date: format_ice_date(birth_time) || birth_time,
          gender: patient.at_xpath("./demographics/gender")&.[]("code")
        }.compact
      end

      def parse_recommendations(patient)
        proposals = patient.xpath(
          "./clinicalStatements/substanceAdministrationProposals/substanceAdministrationProposal"
        )

        proposals.filter_map { |proposal| parse_recommendation(proposal) }
      end

      # Returns nil when the proposal has no vaccine group status observation.
      def parse_recommendation(proposal)
        substance = proposal.at_xpath("./substance/substanceCode")
        observation = vaccine_group_observation(proposal)
        status = observation&.at_xpath("./observationValue/concept")
        return unless substance && status

        recommendation = {
          vaccine: {
            code: substance["code"],
            code_system: substance["codeSystem"],
            name: substance["displayName"]
          },
          status: {
            code: status["code"],
            name: status["displayName"]
          },
          reasons: parse_reasons(observation)
        }

        intervals = parse_intervals(proposal)
        recommendation[:intervals] = intervals if present?(intervals)

        # Only add schedule authorities if the service returned them
        # (requires the ICE outputScheduleAuthorities property)
        schedule_authorities = parse_schedule_authorities(proposal)
        recommendation[:schedule_authorities] = schedule_authorities if present?(schedule_authorities)

        recommendation.merge(parse_series(proposal))
      end

      def parse_reasons(observation)
        observation.xpath("./interpretation").map do |interpretation|
          reason = {
            code: interpretation["code"],
            name: interpretation["displayName"]
          }
          reason[:supplemental_text] = interpretation["originalText"] if interpretation["originalText"]
          reason
        end
      end

      def parse_intervals(proposal)
        {
          proposed: parse_interval(proposal.at_xpath("./proposedAdministrationTimeInterval")),
          valid: parse_interval(proposal.at_xpath("./validAdministrationTimeInterval"))
        }.compact
      end

      def parse_interval(interval)
        return unless interval

        {
          low: format_ice_date(interval["low"]),
          high: format_ice_date(interval["high"])
        }.compact
      end

      # Extract the schedule authorities (e.g. ACIP_CDC, AAP) for a proposal.
      # Returns an empty array when the service did not include them.
      def parse_schedule_authorities(proposal)
        observations = related_observations(proposal, focus_code_system: ICE_OUTPUT_FOCUS_CODE_SYSTEM,
                                                      focus_code: "ICE_VACCINE_GROUP_SCHEDULE_AUTHORITIES")

        observations.xpath("./interpretation").map do |interpretation|
          {
            code: interpretation["code"],
            name: interpretation["displayName"]
          }
        end
      end

      # Only the fields ICE sent, so responses without series output parse as
      # before.
      def parse_series(proposal)
        series = SeriesParser.new(proposal)

        {
          series: series.series,
          season: series.season,
          doses_remaining: series.doses_remaining
        }.compact
      end
  end
end
