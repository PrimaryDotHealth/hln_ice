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
      <cdsOutput><vmrOutput><patient><clinicalStatements><substanceAdministrationProposals>
        <substanceAdministrationProposal>
          <substance><substanceCode code="400" codeSystem="2.16.840.1.113883.3.795.12.100.1"
                                    displayName="Polio Vaccine Group"/></substance>
          <proposedAdministrationTimeInterval low="20200301000000.000+0000"/>
          <validAdministrationTimeInterval low="20200201" high="20200401"/>
          <relatedClinicalStatement>
            <observationResult>
              <observationFocus code="400" codeSystem="2.16.840.1.113883.3.795.12.100.1"/>
              <observationValue><concept code="RECOMMENDED" displayName="Recommended"/></observationValue>
              <interpretation code="DUE_NOW" displayName="Due Now" originalText="Give today"/>
            </observationResult>
          </relatedClinicalStatement>
        </substanceAdministrationProposal>
      </substanceAdministrationProposals></clinicalStatements></patient></vmrOutput></cdsOutput>
    XML

    recommendation = described_class.new(body_for(xml)).data[:recommendations].first

    expect(recommendation[:intervals]).to eq(
      proposed: { low: "2020-03-01" },
      valid: { low: "2020-02-01", high: "2020-04-01" }
    )
    expect(recommendation[:reasons]).to eq([{ code: "DUE_NOW", name: "Due Now", supplemental_text: "Give today" }])
  end

  describe "anchoring to the vMR structure" do
    def proposal(statements, code: "400", name: "Polio Vaccine Group")
      <<~XML
        <substanceAdministrationProposal>
          <substance><substanceCode code="#{code}" codeSystem="2.16.840.1.113883.3.795.12.100.1"
                                    displayName="#{name}"/></substance>
          #{statements}
        </substanceAdministrationProposal>
      XML
    end

    def status_statement(status: "RECOMMENDED", reason: "DUE_NOW", nested: "")
      <<~XML
        <relatedClinicalStatement><observationResult>
          <observationFocus code="400" codeSystem="2.16.840.1.113883.3.795.12.100.1"/>
          <observationValue><concept code="#{status}" codeSystem="2.16.840.1.113883.3.795.12.100.5"/></observationValue>
          <interpretation code="#{reason}" codeSystem="2.16.840.1.113883.3.795.12.100.6"/>
          #{nested}
        </observationResult></relatedClinicalStatement>
      XML
    end

    def series_statement(selections)
      <<~XML
        <relatedClinicalStatement><observationResult>
          <observationFocus code="SERIES_DISPLAY_OPTIONS" codeSystem="2.16.840.1.113883.3.795.12.100.500"/>
          #{selections}
        </observationResult></relatedClinicalStatement>
      XML
    end

    def selection(type, series, extra: "")
      <<~XML
        <relatedClinicalStatement><observationResult>
          <observationFocus code="#{type}" codeSystem="2.16.840.1.113883.3.795.12.100.501"/>
          <observationValue>
            <concept code="#{series}" codeSystem="2.16.840.1.113883.3.795.12.100.10" displayName="#{series} name"/>
          </observationValue>
          #{extra}
        </observationResult></relatedClinicalStatement>
      XML
    end

    def data_for(proposals)
      xml = <<~XML
        <cdsOutput><vmrOutput><patient><clinicalStatements>
          <substanceAdministrationProposals>#{proposals}</substanceAdministrationProposals>
        </clinicalStatements></patient></vmrOutput></cdsOutput>
      XML

      described_class.new(body_for(xml)).data
    end

    def recommendation_for(statements)
      data_for(proposal(statements))[:recommendations].first
    end

    it "takes reasons only from the status observation's own interpretations" do
      nested_interpretation = <<~XML
        <relatedClinicalStatement><observationResult>
          <observationFocus code="OTHER" codeSystem="2.16.840.1.113883.3.795.12.100.500"/>
          <interpretation code="NESTED" codeSystem="2.16.840.1.113883.3.795.12.100.6"/>
        </observationResult></relatedClinicalStatement>
      XML
      series = series_statement(selection("SERIES_DISPLAY_UNAMBIGUOUS", "S", extra: nested_interpretation))

      recommendation = recommendation_for(series + status_statement(nested: nested_interpretation))

      expect(recommendation[:reasons]).to eq([{ code: "DUE_NOW", name: nil }])
    end

    it "takes schedule authorities only from the proposal's own authorities observation" do
      nested_authorities = <<~XML
        <relatedClinicalStatement><observationResult>
          <observationFocus code="ICE_VACCINE_GROUP_SCHEDULE_AUTHORITIES"
                            codeSystem="2.16.840.1.113883.3.795.12.100.500"/>
          <interpretation code="NESTED" codeSystem="2.16.840.1.113883.3.795.12.100.12"/>
        </observationResult></relatedClinicalStatement>
      XML
      series = series_statement(selection("SERIES_DISPLAY_UNAMBIGUOUS", "S", extra: nested_authorities))

      expect(recommendation_for(series + status_statement)).not_to have_key(:schedule_authorities)
    end

    it "skips a proposal with no vaccine group status observation" do
      series = series_statement(selection("SERIES_DISPLAY_UNAMBIGUOUS", "S"))

      expect(data_for(proposal(series))[:recommendations]).to eq([])
    end

    it "does not treat a vMR element nested inside a statement as a patient or proposal" do
      nested = "<relatedClinicalStatement>#{proposal(status_statement, code: "999", name: "Nested")}" \
               "<patient><id extension=\"other\"/></patient></relatedClinicalStatement>"

      data = data_for(proposal(status_statement + nested))

      expect(data[:patient]).to eq({})
      expect(data[:recommendations].map { _1[:vaccine][:name] }).to eq(["Polio Vaccine Group"])
    end

    it "ignores a patient element outside vmrOutput" do
      xml = "<cdsOutput><other><patient><id extension=\"other\"/></patient></other></cdsOutput>"

      expect(described_class.new(body_for(xml)).data).to eq(raw_xml: xml)
    end
  end
end
