# frozen_string_literal: true

require "base64"

RSpec.describe HlnIce::ResponseParser do
  def body_for(xml)
    {
      "finalKMEvaluationResponse" => [
        { "kmEvaluationResultData" => [{ "data" => { "base64EncodedPayload" => [Base64.strict_encode64(xml)] } }] }
      ]
    }.to_json
  end

  it "returns nil when the response carries no vMR payload" do
    expect(described_class.new({ "finalKMEvaluationResponse" => [] }.to_json).data).to be_nil
  end

  it "raises when the body is not JSON" do
    expect { described_class.new("not json").data }.to raise_error(JSON::ParserError)
  end

  it "returns only the raw XML when the payload has no patient" do
    xml = "<cdsOutput><vmrOutput/></cdsOutput>"

    expect(described_class.new(body_for(xml)).data).to eq(raw_xml: xml)
  end

  it "leaves out patient fields the response does not include" do
    xml = "<cdsOutput><vmrOutput><patient><id extension=\"12345\"/></patient></vmrOutput></cdsOutput>"

    data = described_class.new(body_for(xml)).data

    expect(data[:patient]).to eq(id: "12345")
    expect(data.slice(:recommendations, :evaluations, :simplified_status)).to eq(
      recommendations: [], evaluations: [], simplified_status: {}
    )
  end

  it "reads intervals and supplemental reason text from a proposal" do
    xml = <<~XML
      <cdsOutput><vmrOutput><patient>
        <substanceAdministrationProposal>
          <substance><substanceCode code="400" codeSystem="2.16.840.1.113883.3.795.12.100.1"
                                    displayName="Polio Vaccine Group"/></substance>
          <proposedAdministrationTimeInterval low="20200301000000.000+0000"/>
          <validAdministrationTimeInterval low="20200201" high="20200401"/>
          <relatedClinicalStatement>
            <observationResult>
              <observationValue><concept code="RECOMMENDED" displayName="Recommended"/></observationValue>
              <interpretation code="DUE_NOW" displayName="Due Now" originalText="Give today"/>
            </observationResult>
          </relatedClinicalStatement>
        </substanceAdministrationProposal>
      </patient></vmrOutput></cdsOutput>
    XML

    recommendation = described_class.new(body_for(xml)).data[:recommendations].first

    expect(recommendation[:intervals]).to eq(
      proposed: { low: "2020-03-01" },
      valid: { low: "2020-02-01", high: "2020-04-01" }
    )
    expect(recommendation[:reasons]).to eq([{ code: "DUE_NOW", name: "Due Now", supplemental_text: "Give today" }])
  end
end
