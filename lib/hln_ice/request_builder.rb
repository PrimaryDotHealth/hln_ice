# frozen_string_literal: true

require "base64"
require "securerandom"

module HlnIce
  # Builds the ICE evaluate request for a patient: the vMR XML, and the JSON
  # payload that carries it base64 encoded.
  #
  # Does no logging; the Client decides what may be logged.
  class RequestBuilder
    include Support

    def initialize(patient_data)
      @patient_data = patient_data

      # Extract patient information
      @patient_id = patient_data[:patient][:id]
      @date_of_birth = patient_data[:patient][:date_of_birth]
      @gender = patient_data[:patient][:gender]
      @gender = "U" if blank?(@gender) # Set default to 'U' if blank
    end

    def xml
      @xml ||= build_xml
    end

    def payload
      # Base64 encode the XML
      base64_encoded_payload = Base64.strict_encode64(xml)

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

    private
      attr_reader :patient_data, :patient_id, :date_of_birth, :gender

      def build_xml
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
        xml_payload + <<~XML
                  </substanceAdministrationEvents>
                </clinicalStatements>
              </patient>
            </vmrInput>
          </ns4:cdsInput>
        XML
      end
  end
end
