# frozen_string_literal: true

require "date"
require "json"
require "base64"
require "logger"
require "securerandom"
require "httparty"
require "nokogiri"

module HlnIce
  # Client for the HLN ICE (Immunization Calculation Engine) OpenCDS service.
  #
  # Evaluates a patient's immunization history against the ICE forecasting
  # rules and returns both the raw recommendations and a simplified status
  # mapping keyed by vaccine group.
  class Client
    # Mapping from ICE status codes to our status keys
    STATUS_MAPPING = {
      "CONDITIONAL" => "conditional",
      "FUTURE_RECOMMENDED" => "compliant",
      "NOT_RECOMMENDED" => "compliant",
      "RECOMMENDED" => "overdue",
    }.freeze

    # Mapping from ICE vaccine groups to our immunization keys
    VACCINE_MAPPING = {
      "DTP Vaccine Group" => :dtap_tdap,
      "Hep A Vaccine Group" => :hep_a,
      "Hep B Vaccine Group" => :hep_b,
      "Hib Vaccine Group" => :hib,
      "HPV Vaccine Group" => :hpv,
      "Meningococcal Vaccine Group" => :mcv4,
      "MMR Vaccine Group" => :mmr,
      "Pneumococcal Vaccine Group" => :pcv,
      "Polio Vaccine Group" => :ipv_opv,
      "Varicella Vaccine Group" => :var,
    }.freeze

    attr_reader :base_url, :timeout, :max_retries, :retry_delay, :logger

    def initialize(base_url:, timeout: 30, max_retries: 3, retry_delay: 1, logger: nil)
      @base_url = base_url
      @timeout = timeout
      @max_retries = max_retries
      @retry_delay = retry_delay
      @logger = logger || Logger.new($stdout)
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
      rescue => e
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
      rescue => e
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

      def build_ice_payload(patient_data)
        # Extract patient information
        patient_id = patient_data[:patient][:id]
        date_of_birth = patient_data[:patient][:date_of_birth]
        gender = patient_data[:patient][:gender]
        gender = "U" if blank?(gender) # Set default to 'U' if blank

        # Log input data for debugging
        logger.debug("ICE Input Data: #{JSON.pretty_generate(patient_data)}")

        # Build the VMR XML
        xml_payload = <<~XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <ns4:cdsInput xmlns:ns2="org.opencds"
                        xmlns:ns3="org.opencds.vmr.v1_0.schema.vmr"
                        xmlns:ns4="org.opencds.vmr.v1_0.schema.cdsinput"
                        xmlns:ns5="org.opencds.vmr.v1_0.schema.cdsoutput">
            <templateId root="2.16.840.1.113883.3.795.11.1.1"/>
            <cdsContext>
              <cdsSystemUserPreferredLanguage code="en" codeSystem="2.16.840.1.113883.6.99" displayName="English"/>
            </cdsContext>
            <vmrInput>
              <templateId root="2.16.840.1.113883.3.795.11.1.1"/>
              <patient>
                <templateId root="2.16.840.1.113883.3.795.11.2.1.1"/>
                <id root="2.16.840.1.113883.3.795.12.100.11" extension="#{patient_id}"/>
                <demographics>
                  <birthTime value="#{format_date_for_ice(date_of_birth)}"/>
                  <gender code="#{gender}" codeSystem="2.16.840.1.113883.5.1"/>
                </demographics>
                <clinicalStatements>
                  <substanceAdministrationEvents>
        XML

        # Add immunization records if available
        if present?(patient_data[:immunizations])
          patient_data[:immunizations].each do |imm|
            next unless present?(imm.dig(:clinicalStatements, :substanceAdministrationEvents))

            imm[:clinicalStatements][:substanceAdministrationEvents].each do |event|
              next unless present?(event.dig(:substance, :substanceCode))

              substance_code = event[:substance][:substanceCode]

              # Format dates to ICE format (YYYYMMDD)
              low_date = format_date_for_ice(event[:administrationTimeInterval][:low])
              high_date = format_date_for_ice(event[:administrationTimeInterval][:high])

              xml_payload += <<~XML
                    <substanceAdministrationEvent>
                      <templateId root="2.16.840.1.113883.3.795.11.9.1.1"/>
                      <id root="#{event[:id] || SecureRandom.uuid}"/>
                      <substanceAdministrationGeneralPurpose code="384810002" codeSystem="2.16.840.1.113883.6.5"/>
                      <substance>
                        <id root="#{event[:substance][:id] || SecureRandom.uuid}"/>
                        <substanceCode code="#{substance_code[:code]}"
                                    codeSystem="2.16.840.1.113883.12.292"
                                    displayName="#{substance_code[:displayName]}"
                                    originalText="#{substance_code[:displayName]}"/>
                      </substance>
                      <administrationTimeInterval low="#{low_date}" high="#{high_date}"/>
                    </substanceAdministrationEvent>
              XML
            end
          end
        end

        # Close the XML
        xml_payload += <<~XML
                  </substanceAdministrationEvents>
                </clinicalStatements>
              </patient>
            </vmrInput>
          </ns4:cdsInput>
        XML

        # Log the generated XML for debugging
        logger.debug("Generated ICE XML: #{xml_payload}")

        # Base64 encode the XML
        base64_encoded_payload = Base64.strict_encode64(xml_payload)

        # Build the full payload
        {
          "interactionId" => {
            "scopingEntityId" => "org.nyc.cir",
            "interactionId" => "#{patient_id}-#{Time.now.to_i}",
            "submissionTime" => (Time.now.to_f * 1000).to_i
          },
          "evaluationRequest" => {
            "clientLanguage" => "en",
            "clientTimeZoneOffset" => "+0000",
            "kmEvaluationRequest" => [
              {
                "kmId" => {
                  "scopingEntityId" => "org.nyc.cir",
                  "businessId" => "ICE",
                  "version" => "1.0.0"
                }
              }
            ],
            "dataRequirementItemData" => [
              {
                "driId" => {
                  "containingEntityId" => {
                    "scopingEntityId" => "org.nyc.cir",
                    "businessId" => "ICEData",
                    "version" => "1.0.0"
                  },
                  "itemId" => "cdsPayload"
                },
                "data" => {
                  "informationModelSSId" => {
                    "scopingEntityId" => "org.opencds.vmr",
                    "businessId" => "VMR",
                    "version" => "1.0"
                  },
                  "base64EncodedPayload" => [base64_encoded_payload]
                }
              }
            ]
          }
        }
      end

      def parse_ice_response(response_body)
        logger.info("ICE service response: #{response_body}")

        result = JSON.parse(response_body)

        if result.dig("finalKMEvaluationResponse", 0, "kmEvaluationResultData", 0, "data", "base64EncodedPayload", 0)
          base64_result = result["finalKMEvaluationResponse"][0]["kmEvaluationResultData"][0]["data"]["base64EncodedPayload"][0]
          decoded_result = Base64.decode64(base64_result)

          # Parse the XML response
          parsed_result = parse_xml_response(decoded_result)

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
      rescue => e
        logger.error("Error parsing ICE response: #{e.message}")
        { success: false, error: "Error parsing ICE response: #{e.message}" }
      end

      def parse_xml_response(xml_string)
        # Parse the XML
        doc = Nokogiri::XML(xml_string)

        # Remove namespaces to simplify parsing
        doc.remove_namespaces!

        # Extract patient information
        patient = doc.xpath("//patient").first
        return { raw_xml: xml_string } unless patient

        patient_id = patient.xpath("./id").first["extension"] rescue nil
        birth_time = patient.xpath("./demographics/birthTime").first["value"] rescue nil
        gender = patient.xpath("./demographics/gender").first["code"] rescue nil

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

          # Get the clinical observation result
          observation = proposal.xpath(".//observationResult").first
          next unless observation

          # Get recommendation status
          status_element = observation.xpath(".//observationValue/concept").first
          next unless status_element

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
            if interpretation["originalText"]
              reason[:supplemental_text] = interpretation["originalText"]
            end

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

          all_recommendations << recommendation
        end

        # Create simplified immunization status mapping
        simplified_status = {}

        # Process all recommendations to create the simplified mapping
        all_recommendations.each do |recommendation|
          vaccine_name = recommendation[:vaccine][:name]
          status_code = recommendation[:status][:code]

          # Map the vaccine name to our key
          vaccine_key = VACCINE_MAPPING[vaccine_name]
          next unless vaccine_key # Skip if we don't have a mapping

          # Map the status code to our status
          status = STATUS_MAPPING[status_code] || "overdue" # Default to overdue if unknown

          # Special handling for conditional status based on reasons
          if status == "conditional"
            # Check if any reason indicates medical exemption
            has_medical_exemption = recommendation[:reasons].any? { |r| r[:code] == "MEDICAL_EXEMPTION" }
            if has_medical_exemption
              status = "medically_exempt"
            end
          end

          # Store in our simplified mapping
          simplified_status[vaccine_key] = status
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
          simplified_status: # Add the simplified mapping
        }
      end

      def handle_error_response(response)
        error_message = "ICE service error: #{response.code}"

        begin
          error_details = JSON.parse(response.body)
          error_message += " - #{error_details['message'] || error_details['error'] || response.body}"
        rescue
          error_message += " - #{response.body}"
        end

        logger.error(error_message)
        { success: false, error: error_message }
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
