# frozen_string_literal: true

module HlnIce
  # Extracts ICE's evaluation of each administered dose from the vMR patient
  # element. ICE nests one substanceAdministrationEvent per vaccine group under
  # each input event, so a combination vaccine yields one evaluation per group
  # it counts toward.
  class EvaluationsParser
    include Support

    def initialize(patient)
      @patient = patient
    end

    def evaluations
      events = patient.xpath("./clinicalStatements/substanceAdministrationEvents/substanceAdministrationEvent")

      events.flat_map do |event|
        event_id = event.at_xpath("./id")&.[]("root")
        cvx = event.at_xpath("./substance/substanceCode")&.[]("code")

        event.xpath("./relatedClinicalStatement/substanceAdministrationEvent").filter_map do |component|
          parse_evaluation(component, event_id:, cvx:)
        end
      end
    end

    private
      attr_reader :patient

      # Build the evaluation for one vaccine group from a nested event.
      # Returns nil when the event has no evaluation status observation.
      def parse_evaluation(component, event_id:, cvx:)
        observation = vaccine_group_observation(component)
        status = observation&.at_xpath("./observationValue/concept")
        return unless status

        focus = observation.at_xpath("./observationFocus")
        dose_number = component.at_xpath("./doseNumber")&.[]("value")
        valid = component.at_xpath("./isValid")&.[]("value")
        series = SeriesParser.new(component).series

        evaluation = {
          event_id:,
          cvx:,
          administered_on: format_ice_date(component.at_xpath("./administrationTimeInterval")&.[]("low")),
          vaccine_group: { code: focus["code"], name: focus["displayName"] },
          dose_number: dose_number&.to_i,
          valid: valid.nil? ? nil : valid == "true",
          status: { code: status["code"], name: status["displayName"] },
          reasons: observation.xpath("./interpretation").map do |interpretation|
            { code: interpretation["code"], name: interpretation["displayName"] }
          end
        }
        evaluation[:series] = series if series
        evaluation
      end
  end
end
