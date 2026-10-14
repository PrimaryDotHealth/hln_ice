# frozen_string_literal: true

module HlnIce
  # Extracts the series ICE selected for display from a recommendation or dose
  # evaluation, along with its season and doses remaining. ICE only sends these
  # when the ICE_OUTPUTSERIESINFORMATION and ICE_OUTPUTNUMBEROFDOSESREMAINING
  # service settings are on; each value is nil when ICE did not send it.
  class SeriesParser
    include Support

    SERIES_DISPLAY_TYPE_CODE_SYSTEM = "2.16.840.1.113883.3.795.12.100.501"
    SERIES_CODE_SYSTEM = "2.16.840.1.113883.3.795.12.100.10"
    SEASON_CODE_SYSTEM = "2.16.840.1.113883.3.795.12.100.11"
    SEASON_DATE_RANGE = %r{\((\d{2}/\d{2}/\d{4}) - (\d{2}/\d{2}/\d{4})\)\z}

    # In order of preference, so a selected series wins over an alternative.
    SELECTIONS = {
      "SERIES_DISPLAY_UNAMBIGUOUS" => "unambiguous",
      "SERIES_DISPLAY_BEST_GUESS" => "best_guess",
      "SERIES_DISPLAY_ALTERNATIVE" => "alternative"
    }.freeze

    def initialize(statement)
      @statement = statement
    end

    def series
      concept = selected_observation&.at_xpath("./observationValue/concept[@codeSystem='#{SERIES_CODE_SYSTEM}']")
      return unless concept

      {
        code: concept["code"],
        name: concept["displayName"],
        selection: SELECTIONS.fetch(selection_code(selected_observation))
      }
    end

    def season
      concept = selected_observation_detail("SEASON", SEASON_CODE_SYSTEM)
                &.at_xpath("./observationValue/concept[@codeSystem='#{SEASON_CODE_SYSTEM}']")
      return unless concept

      starts_on, ends_on = season_dates(concept["displayName"])

      {
        code: concept["code"],
        name: concept["displayName"],
        starts_on:,
        ends_on:
      }
    end

    # An Integer when ICE sends a plain count, otherwise ICE's text as is
    # (e.g. "Recurring").
    def doses_remaining
      value = selected_observation_detail("NUMBER_OF_DOSES_REMAINING", SERIES_CODE_SYSTEM)
              &.at_xpath("./observationValue/text")&.[]("value")

      value&.match?(/\A\d+\z/) ? value.to_i : value
    end

    private
      attr_reader :statement

      # ICE sends no structured season dates, only a trailing
      # "(MM/DD/YYYY - MM/DD/YYYY)" in the season's display name. Returns ISO
      # dates, or nils when the name does not end in a valid range.
      def season_dates(name)
        range = SEASON_DATE_RANGE.match(name.to_s)
        return [nil, nil] unless range

        range.captures.map { |date| Date.strptime(date, "%m/%d/%Y").iso8601 }
      rescue Date::Error
        [nil, nil]
      end

      def selected_observation
        return @selected_observation if defined?(@selected_observation)

        @selected_observation = series_selections.min_by do |observation|
          SELECTIONS.keys.index(selection_code(observation))
        end
      end

      def series_selections
        options = related_observations(statement, focus_code_system: ICE_OUTPUT_FOCUS_CODE_SYSTEM,
                                                  focus_code: "SERIES_DISPLAY_OPTIONS")

        selections = options.flat_map do |option|
          related_observations(option, focus_code_system: SERIES_DISPLAY_TYPE_CODE_SYSTEM).to_a
        end

        selections.select { |observation| SELECTIONS.key?(selection_code(observation)) }
      end

      def selection_code(observation)
        observation.at_xpath("./observationFocus")["code"]
      end

      def selected_observation_detail(focus_code, focus_code_system)
        return unless selected_observation

        related_observations(selected_observation, focus_code_system:, focus_code:).first
      end
  end
end
