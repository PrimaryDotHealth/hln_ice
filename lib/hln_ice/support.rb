# frozen_string_literal: true

require "date"

module HlnIce
  # Helpers shared by the request builder and response parsers. Included as
  # private instance methods.
  module Support
    private
      # Plain-Ruby equivalent of ActiveSupport's `blank?`.
      def blank?(value)
        return true if value.nil?
        return value.strip.empty? if value.is_a?(String)
        return value.empty? if value.respond_to?(:empty?)

        false
      end

      # Plain-Ruby equivalent of ActiveSupport's `present?`.
      def present?(value)
        !blank?(value)
      end

      # Helper method to format ICE dates to standard format
      def format_ice_date(ice_date)
        return nil unless ice_date

        # ICE dates are in format: YYYYMMDDHHMMSS.000+0000
        if ice_date.match(/^(\d{4})(\d{2})(\d{2})/)
          year = $1
          month = $2
          day = $3
          "#{year}-#{month}-#{day}"
        else
          ice_date
        end
      end

      # Helper method to format dates for ICE (YYYYMMDD)
      def format_date_for_ice(date_string)
        return nil unless date_string

        begin
          date = Date.parse(date_string)
          # Format as YYYYMMDD
          date.strftime("%Y%m%d")
        rescue
          # If parsing fails, try to use the original string
          date_string
        end
      end
  end
end
