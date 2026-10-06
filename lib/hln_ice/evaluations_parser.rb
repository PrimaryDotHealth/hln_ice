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
        event_id = event.xpath("./id").first&.[]("root")
        cvx = event.xpath("./substance/substanceCode").first&.[]("code")

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
        observation = component.xpath("./relatedClinicalStatement/observationResult[observationValue/concept]").first
        return unless observation

        focus = observation.xpath("./observationFocus").first
        status = observation.xpath("./observationValue/concept").first
        dose_number = component.xpath("./doseNumber").first&.[]("value")
        valid = component.xpath("./isValid").first&.[]("value")

        {
          event_id:,
          cvx:,
          administered_on: format_ice_date(component.xpath("./administrationTimeInterval").first&.[]("low")),
          vaccine_group: { code: focus&.[]("code"), name: focus&.[]("displayName") },
          dose_number: dose_number&.to_i,
          valid: valid.nil? ? nil : valid == "true",
          status: { code: status["code"], name: status["displayName"] },
          reasons: observation.xpath("./interpretation").map do |interpretation|
            { code: interpretation["code"], name: interpretation["displayName"] }
          end
        }
      end
  end
end
