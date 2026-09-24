# frozen_string_literal: true

require "base64"

RSpec.describe HlnIce::Client do
  let(:base_url) { "https://ice.example.com" }
  let(:logger)   { Logger.new(IO::NULL) }
  let(:client)   { described_class.new(base_url: base_url, logger: logger, retry_delay: 0) }

  # A minimal VMR XML response with one Polio proposal marked RECOMMENDED.
  let(:vmr_xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <cdsOutput>
        <vmrOutput>
          <patient>
            <id extension="12345"/>
            <demographics>
              <birthTime value="20200101"/>
              <gender code="M"/>
            </demographics>
            <clinicalStatements>
              <substanceAdministrationProposals>
                <substanceAdministrationProposal>
                  <substance>
                    <substanceCode code="10"
                                   codeSystem="2.16.840.1.113883.12.292"
                                   displayName="Polio Vaccine Group"/>
                  </substance>
                  <proposedAdministrationTimeInterval low="20200301" high="20200401"/>
                  <relatedClinicalStatement>
                    <observationResult>
                      <observationValue>
                        <concept code="RECOMMENDED" displayName="Recommended"/>
                      </observationValue>
                      <interpretation code="DUE_NOW" displayName="Due Now"/>
                    </observationResult>
                  </relatedClinicalStatement>
                </substanceAdministrationProposal>
              </substanceAdministrationProposals>
            </clinicalStatements>
          </patient>
        </vmrOutput>
      </cdsOutput>
    XML
  end

  let(:success_body) do
    {
      "finalKMEvaluationResponse" => [
        {
          "kmEvaluationResultData" => [
            { "data" => { "base64EncodedPayload" => [Base64.strict_encode64(vmr_xml)] } }
          ]
        }
      ]
    }.to_json
  end

  let(:patient_data) do
    {
      patient: { id: "12345", date_of_birth: "2020-01-01", gender: "M" },
      immunizations: []
    }
  end

  def stub_response(success:, body: "", code: 200)
    instance_double(HTTParty::Response, success?: success, body: body, code: code)
  end

  describe "#available?" do
    it "returns true when the service responds successfully" do
      allow(HTTParty).to receive(:get).and_return(stub_response(success: true))
      expect(client.available?).to be(true)
    end

    it "returns false when the service responds unsuccessfully" do
      allow(HTTParty).to receive(:get).and_return(stub_response(success: false))
      expect(client.available?).to be(false)
    end

    it "returns false when the request raises" do
      allow(HTTParty).to receive(:get).and_raise(SocketError.new("boom"))
      expect(client.available?).to be(false)
    end
  end

  describe "#evaluate_immunizations" do
    it "parses a successful response into recommendations and a simplified status" do
      allow(HTTParty).to receive(:post).and_return(stub_response(success: true, body: success_body))

      result = client.evaluate_immunizations(patient_data)

      expect(result[:success]).to be(true)
      expect(result[:data][:simplified_status]).to eq(ipv_opv: "overdue")
      expect(result[:data][:recommendations].first[:vaccine][:name]).to eq("Polio Vaccine Group")
    end

    it "omits schedule_authorities when the service does not return them" do
      allow(HTTParty).to receive(:post).and_return(stub_response(success: true, body: success_body))

      result = client.evaluate_immunizations(patient_data)

      expect(result[:data][:recommendations].first).not_to have_key(:schedule_authorities)
    end

    context "when the service returns schedule authorities" do
      # Mirrors ICE output with outputScheduleAuthorities enabled, where the
      # authorities observation can precede the status observation.
      let(:vmr_xml) do
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <cdsOutput>
            <vmrOutput>
              <patient>
                <id extension="12345"/>
                <clinicalStatements>
                  <substanceAdministrationProposals>
                    <substanceAdministrationProposal>
                      <substance>
                        <substanceCode code="400"
                                       codeSystem="2.16.840.1.113883.3.795.12.100.1"
                                       displayName="Polio Vaccine Group"/>
                      </substance>
                      <relatedClinicalStatement>
                        <observationResult>
                          <observationFocus code="ICE_VACCINE_GROUP_SCHEDULE_AUTHORITIES"
                                            codeSystem="2.16.840.1.113883.3.795.12.100.500"/>
                          <interpretation code="ACIP_CDC" codeSystem="2.16.840.1.113883.3.795.12.100.12"
                                          displayName="Advisory Committee on Immunization Practices / Centers for Disease Control and Prevention"/>
                          <interpretation code="AAP" codeSystem="2.16.840.1.113883.3.795.12.100.12"
                                          displayName="American Academy of Pediatrics"/>
                          <interpretation code="AAFP" codeSystem="2.16.840.1.113883.3.795.12.100.12"
                                          displayName="American Academy of Family Physicians"/>
                        </observationResult>
                      </relatedClinicalStatement>
                      <relatedClinicalStatement>
                        <observationResult>
                          <observationFocus code="400" codeSystem="2.16.840.1.113883.3.795.12.100.1"/>
                          <observationValue>
                            <concept code="RECOMMENDED" displayName="Recommended"/>
                          </observationValue>
                          <interpretation code="DUE_NOW" displayName="Due Now"/>
                        </observationResult>
                      </relatedClinicalStatement>
                    </substanceAdministrationProposal>
                  </substanceAdministrationProposals>
                </clinicalStatements>
              </patient>
            </vmrOutput>
          </cdsOutput>
        XML
      end

      before do
        allow(HTTParty).to receive(:post).and_return(stub_response(success: true, body: success_body))
      end

      it "exposes them on the recommendation" do
        recommendation = client.evaluate_immunizations(patient_data)[:data][:recommendations].first

        expect(recommendation[:schedule_authorities]).to eq(
          [
            {
              code: "ACIP_CDC",
              name: "Advisory Committee on Immunization Practices / Centers for Disease Control and Prevention"
            },
            { code: "AAP", name: "American Academy of Pediatrics" },
            { code: "AAFP", name: "American Academy of Family Physicians" }
          ]
        )
      end

      it "still reads status and reasons from the status observation" do
        result = client.evaluate_immunizations(patient_data)
        recommendation = result[:data][:recommendations].first

        expect(recommendation[:status]).to eq(code: "RECOMMENDED", name: "Recommended")
        expect(recommendation[:reasons]).to eq([{ code: "DUE_NOW", name: "Due Now" }])
        expect(result[:data][:simplified_status]).to eq(ipv_opv: "overdue")
      end
    end

    it "defaults a blank gender to 'U' in the request payload" do
      blank_gender = patient_data.merge(patient: patient_data[:patient].merge(gender: ""))
      allow(HTTParty).to receive(:post).and_return(stub_response(success: true, body: success_body))

      client.evaluate_immunizations(blank_gender)

      expect(HTTParty).to have_received(:post) do |_url, options|
        payload = options[:body]
        decoded = Base64.decode64(JSON.parse(payload).dig(
          "evaluationRequest", "dataRequirementItemData", 0, "data", "base64EncodedPayload", 0
        ))
        expect(decoded).to include('code="U"')
      end
    end

    it "returns a failure hash on an error response" do
      allow(HTTParty).to receive(:post).and_return(
        stub_response(success: false, body: { message: "bad request" }.to_json, code: 400)
      )

      result = client.evaluate_immunizations(patient_data)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("400")
    end

    it "retries then fails after exhausting max_retries" do
      retry_client = described_class.new(
        base_url: base_url, logger: logger, max_retries: 2, retry_delay: 0
      )
      allow(HTTParty).to receive(:post).and_raise(Timeout::Error.new("slow"))

      result = retry_client.evaluate_immunizations(patient_data)

      expect(result[:success]).to be(false)
      expect(HTTParty).to have_received(:post).exactly(3).times # initial + 2 retries
    end
  end

  describe "PHI payload logging" do
    let(:spy_logger) { instance_spy(Logger) }

    before do
      allow(HTTParty).to receive(:post).and_return(stub_response(success: true, body: success_body))
    end

    context "by default" do
      let(:client) { described_class.new(base_url: base_url, logger: spy_logger, retry_delay: 0) }

      it "does not log the input data, generated XML, or service response" do
        client.evaluate_immunizations(patient_data)

        expect(spy_logger).not_to have_received(:debug).with(/ICE Input Data/)
        expect(spy_logger).not_to have_received(:debug).with(/Generated ICE XML/)
        expect(spy_logger).not_to have_received(:debug).with(/ICE service response/)
      end
    end

    context "when log_payloads is enabled" do
      let(:client) do
        described_class.new(base_url: base_url, logger: spy_logger, retry_delay: 0, log_payloads: true)
      end

      it "logs the input data, generated XML, and service response for debugging" do
        client.evaluate_immunizations(patient_data)

        expect(spy_logger).to have_received(:debug).with(/ICE Input Data/)
        expect(spy_logger).to have_received(:debug).with(/Generated ICE XML/)
        expect(spy_logger).to have_received(:debug).with(/ICE service response/)
      end
    end
  end
end
