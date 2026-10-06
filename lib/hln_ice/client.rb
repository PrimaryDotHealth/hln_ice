# frozen_string_literal: true

require "json"
require "logger"
require "httparty"

module HlnIce
  # Client for the HLN ICE (Immunization Calculation Engine) OpenCDS service.
  #
  # Evaluates a patient's immunization history against the ICE forecasting
  # rules and returns both the raw recommendations and a simplified status
  # mapping keyed by vaccine group.
  #
  # All logging happens here: RequestBuilder and ResponseParser never log, so
  # this class is the only place that can write patient data to the logs.
  class Client
    STATUS_MAPPING = SimplifiedStatus::STATUS_MAPPING
    VACCINE_MAPPING = SimplifiedStatus::VACCINE_MAPPING

    attr_reader :base_url, :timeout, :max_retries, :retry_delay, :logger, :log_payloads

    # log_payloads: when false (default), the ICE input data, generated request
    # XML, and raw service response are NOT logged. These contain patient PHI, so
    # logging stays off unless a caller explicitly opts in (e.g. local debugging).
    def initialize(base_url:, timeout: 30, max_retries: 3, retry_delay: 1, logger: nil, log_payloads: false)
      @base_url = base_url
      @timeout = timeout
      @max_retries = max_retries
      @retry_delay = retry_delay
      @logger = logger || Logger.new($stdout)
      @log_payloads = log_payloads
    end

    # Check if the ICE service is available
    def available?
      url = "#{base_url}/opencds-decision-support-service/version"

      begin
        response = HTTParty.get(
          url,
          timeout:
        )

        response.success?
      rescue StandardError => e
        logger.error("ICE service unavailable: #{e.message}")
        false
      end
    end

    # Evaluate immunizations using patient data
    def evaluate_immunizations(patient_data)
      url = "#{base_url}/opencds-decision-support-service/api/resources/evaluate"

      # Build the payload for the ICE service
      payload = build_ice_payload(patient_data)

      # Make the request with retries
      response = nil
      retries = 0

      begin
        response = HTTParty.post(
          url,
          body: payload.to_json,
          headers: {
            "Content-Type": "application/json",
            "Accept": "application/json"
          },
          timeout:
        )

        if response.success?
          parse_ice_response(response.body)
        else
          handle_error_response(response)
        end
      rescue StandardError => e
        retries += 1
        if retries <= max_retries
          logger.warn("Retrying ICE request (#{retries}/#{max_retries}): #{e.message}")
          sleep(retry_delay)
          retry
        else
          logger.error("Error evaluating immunizations after #{max_retries} retries: #{e.message}")
          { success: false, error: "Error evaluating immunizations: #{e.message}" }
        end
      end
    end

    private
      def build_ice_payload(patient_data)
        builder = RequestBuilder.new(patient_data)

        # Log input data for debugging
        logger.debug("ICE Input Data: #{JSON.pretty_generate(patient_data)}") if log_payloads

        # Log the generated XML for debugging
        logger.debug("Generated ICE XML: #{builder.xml}") if log_payloads

        builder.payload
      end

      def parse_ice_response(response_body)
        logger.debug("ICE service response: #{response_body}") if log_payloads

        parsed_result = ResponseParser.new(response_body).data

        if parsed_result
          {
            success: true,
            data: parsed_result
          }
        else
          logger.warn("No valid response found in ICE output.")
          {
            success: false,
            error: "No valid response found in ICE output."
          }
        end
      rescue StandardError => e
        logger.error("Error parsing ICE response: #{e.message}")
        { success: false, error: "Error parsing ICE response: #{e.message}" }
      end

      def handle_error_response(response)
        error_message = "ICE service error: #{response.code}"

        begin
          error_details = JSON.parse(response.body)
          error_message += " - #{error_details["message"] || error_details["error"] || response.body}"
        rescue StandardError
          error_message += " - #{response.body}"
        end

        logger.error(error_message)
        { success: false, error: error_message }
      end
  end
end
