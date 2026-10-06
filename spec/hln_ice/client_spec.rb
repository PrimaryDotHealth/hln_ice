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

    context "with a recorded ICE 2.59.1 response" do
      # Recorded from a real ICE 2.59.1 server: input events with ids "1"
      # (CVX 141 influenza) and "2" (CVX 115 Tdap), both evaluated as valid.
      let(:success_body) do
        File.read(File.expand_path("../fixtures/ice/evaluate_schedule_authorities_first.json", __dir__))
      end

      before do
        allow(HTTParty).to receive(:post).and_return(stub_response(success: true, body: success_body))
      end

      it "returns one evaluation per input event and vaccine group" do
        evaluations = client.evaluate_immunizations(patient_data)[:data][:evaluations]

        expect(evaluations).to eq(
          [
            {
              event_id: "1",
              cvx: "141",
              administered_on: "2024-10-01",
              vaccine_group: { code: "800", name: "Influenza Vaccine Group" },
              dose_number: 1,
              valid: true,
              status: { code: "VALID", name: "Valid Dose" },
              reasons: []
            },
            {
              event_id: "2",
              cvx: "115",
              administered_on: "2019-05-02",
              vaccine_group: { code: "200", name: "DTP Vaccine Group" },
              dose_number: 1,
              valid: true,
              status: { code: "VALID", name: "Valid Dose" },
              reasons: []
            }
          ]
        )
      end

      it "leaves the patient, recommendations, and simplified status unchanged" do
        data = client.evaluate_immunizations(patient_data)[:data]

        expect(data.keys).to eq(%i[raw_xml patient recommendations evaluations simplified_status])
        expect(data[:patient]).to eq(id: "1", birth_date: "1960-03-14", gender: "M")
        expect(data[:recommendations].size).to eq(17)
        expect(data[:recommendations].first).to eq(
          vaccine: { code: "600", code_system: "2.16.840.1.113883.3.795.12.100.1", name: "Varicella Vaccine Group" },
          status: { code: "CONDITIONAL", name: "Conditionally Recommended" },
          reasons: [{ code: "HIGH_RISK", name: "Recommended for high-risk groups." }],
          schedule_authorities: [
            {
              code: "ACIP_CDC",
              name: "Advisory Committee on Immunization Practices / Centers for Disease Control and Prevention"
            },
            { code: "AAP", name: "American Academy of Pediatrics" },
            { code: "AAFP", name: "American Academy of Family Physicians" }
          ]
        )
        expect(data[:simplified_status]).to eq(
          var: "conditional", hib: "conditional", pcv: "overdue", ipv_opv: "conditional", hep_a: "conditional",
          dtap_tdap: "overdue", mmr: "overdue", hpv: "compliant", hep_b: "conditional"
        )
      end
    end

    context "when the service evaluates doses as invalid or for several vaccine groups" do
      # Built by hand: the recorded response only has valid, single-group doses.
      # It follows the structure of the recorded response and of the examples in
      # ICE's vMR Implementation Guide (docs/implementation-guides/ in
      # cdsframework/ice). The INVALID status and BELOW_MINIMUM_INTERVAL reason
      # come from that guide's example; the "Invalid Dose" display name is the
      # one in ICE's supportedEvaluationStatuses.yml. The second dose has no
      # doseNumber, as in the guide's invalid-dose example.
      #
      # Event "1" is a CVX 110 (DTaP-HepB-IPV) combination vaccine, abridged to
      # two of the groups it counts toward (DTP and Hep B). Event "2" is an
      # invalid Hep B dose.
      let(:vmr_xml) do
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <cdsOutput>
            <vmrOutput>
              <patient>
                <id extension="12345"/>
                <clinicalStatements>
                  <substanceAdministrationEvents>
                    <substanceAdministrationEvent>
                      <id root="1"/>
                      <substance><substanceCode code="110" codeSystem="2.16.840.1.113883.12.292"/></substance>
                      <administrationTimeInterval low="20200301000000.000+0000" high="20200301000000.000+0000"/>
                      <relatedClinicalStatement>
                        <substanceAdministrationEvent>
                          <substance><substanceCode code="110" codeSystem="2.16.840.1.113883.12.292"/></substance>
                          <doseNumber value="1"/>
                          <administrationTimeInterval low="20200301000000.000+0000" high="20200301000000.000+0000"/>
                          <isValid value="true"/>
                          <relatedClinicalStatement>
                            <observationResult>
                              <observationFocus code="200" codeSystem="2.16.840.1.113883.3.795.12.100.1"
                                                displayName="DTP Vaccine Group"/>
                              <observationValue>
                                <concept code="VALID" codeSystem="2.16.840.1.113883.3.795.12.100.2" displayName="Valid Dose"/>
                              </observationValue>
                            </observationResult>
                          </relatedClinicalStatement>
                        </substanceAdministrationEvent>
                      </relatedClinicalStatement>
                      <relatedClinicalStatement>
                        <substanceAdministrationEvent>
                          <substance><substanceCode code="110" codeSystem="2.16.840.1.113883.12.292"/></substance>
                          <doseNumber value="1"/>
                          <administrationTimeInterval low="20200301000000.000+0000" high="20200301000000.000+0000"/>
                          <isValid value="true"/>
                          <relatedClinicalStatement>
                            <observationResult>
                              <observationFocus code="100" codeSystem="2.16.840.1.113883.3.795.12.100.1"
                                                displayName="Hep B Vaccine Group"/>
                              <observationValue>
                                <concept code="VALID" codeSystem="2.16.840.1.113883.3.795.12.100.2" displayName="Valid Dose"/>
                              </observationValue>
                            </observationResult>
                          </relatedClinicalStatement>
                        </substanceAdministrationEvent>
                      </relatedClinicalStatement>
                    </substanceAdministrationEvent>
                    <substanceAdministrationEvent>
                      <id root="2"/>
                      <substance><substanceCode code="08" codeSystem="2.16.840.1.113883.12.292"/></substance>
                      <administrationTimeInterval low="20200315000000.000+0000" high="20200315000000.000+0000"/>
                      <relatedClinicalStatement>
                        <substanceAdministrationEvent>
                          <substance><substanceCode code="08" codeSystem="2.16.840.1.113883.12.292"/></substance>
                          <administrationTimeInterval low="20200315000000.000+0000" high="20200315000000.000+0000"/>
                          <isValid value="false"/>
                          <relatedClinicalStatement>
                            <observationResult>
                              <observationFocus code="100" codeSystem="2.16.840.1.113883.3.795.12.100.1"
                                                displayName="Hep B Vaccine Group"/>
                              <observationValue>
                                <concept code="INVALID" codeSystem="2.16.840.1.113883.3.795.12.100.2"
                                         displayName="Invalid Dose"/>
                              </observationValue>
                              <interpretation code="BELOW_MINIMUM_INTERVAL" codeSystem="2.16.840.1.113883.3.795.12.100.3"
                                              displayName="Below Minimum Interval" originalText="BELOW_MINIMUM_INTERVAL"/>
                            </observationResult>
                          </relatedClinicalStatement>
                        </substanceAdministrationEvent>
                      </relatedClinicalStatement>
                    </substanceAdministrationEvent>
                  </substanceAdministrationEvents>
                </clinicalStatements>
              </patient>
            </vmrOutput>
          </cdsOutput>
        XML
      end

      let(:evaluations) { client.evaluate_immunizations(patient_data)[:data][:evaluations] }

      before do
        allow(HTTParty).to receive(:post).and_return(stub_response(success: true, body: success_body))
      end

      it "returns one evaluation per vaccine group a combination vaccine counts toward" do
        expect(evaluations.select { |e| e[:event_id] == "1" }).to eq(
          [
            {
              event_id: "1",
              cvx: "110",
              administered_on: "2020-03-01",
              vaccine_group: { code: "200", name: "DTP Vaccine Group" },
              dose_number: 1,
              valid: true,
              status: { code: "VALID", name: "Valid Dose" },
              reasons: []
            },
            {
              event_id: "1",
              cvx: "110",
              administered_on: "2020-03-01",
              vaccine_group: { code: "100", name: "Hep B Vaccine Group" },
              dose_number: 1,
              valid: true,
              status: { code: "VALID", name: "Valid Dose" },
              reasons: []
            }
          ]
        )
      end

      it "returns the status and reasons of an invalid dose, with a nil dose number when ICE omits it" do
        expect(evaluations.select { |e| e[:event_id] == "2" }).to eq(
          [
            {
              event_id: "2",
              cvx: "08",
              administered_on: "2020-03-15",
              vaccine_group: { code: "100", name: "Hep B Vaccine Group" },
              dose_number: nil,
              valid: false,
              status: { code: "INVALID", name: "Invalid Dose" },
              reasons: [{ code: "BELOW_MINIMUM_INTERVAL", name: "Below Minimum Interval" }]
            }
          ]
        )
      end
    end

    it "returns no evaluations when the service returns no events" do
      allow(HTTParty).to receive(:post).and_return(stub_response(success: true, body: success_body))

      expect(client.evaluate_immunizations(patient_data)[:data][:evaluations]).to eq([])
    end

    it "defaults a blank gender to 'U' in the request payload" do
      blank_gender = patient_data.merge(patient: patient_data[:patient].merge(gender: ""))
      allow(HTTParty).to receive(:post).and_return(stub_response(success: true, body: success_body))

      client.evaluate_immunizations(blank_gender)

      expect(HTTParty).to have_received(:post) do |_url, options|
        path = ["evaluationRequest", "dataRequirementItemData", 0, "data", "base64EncodedPayload", 0]
        decoded = Base64.decode64(JSON.parse(options[:body]).dig(*path))
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
