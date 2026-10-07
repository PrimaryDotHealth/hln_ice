# frozen_string_literal: true

RSpec.describe HlnIce::EvaluationsParser do
  def evaluations_for(events_xml)
    xml = <<~XML
      <patient>
        <clinicalStatements>
          <substanceAdministrationEvents>#{events_xml}</substanceAdministrationEvents>
        </clinicalStatements>
      </patient>
    XML

    described_class.new(Nokogiri::XML(xml).at_xpath("/patient")).evaluations
  end

  def component(status: true, is_valid: nil)
    <<~XML
      <relatedClinicalStatement>
        <substanceAdministrationEvent>
          <administrationTimeInterval low="20200301000000.000+0000"/>
          #{is_valid && %(<isValid value="#{is_valid}"/>)}
          <relatedClinicalStatement>
            <observationResult>
              <observationFocus code="400" displayName="Polio Vaccine Group"/>
              #{status && '<observationValue><concept code="ACCEPTED" displayName="Accepted Dose"/></observationValue>'}
            </observationResult>
          </relatedClinicalStatement>
        </substanceAdministrationEvent>
      </relatedClinicalStatement>
    XML
  end

  def event(components)
    %(<substanceAdministrationEvent><id root="1"/>#{components}</substanceAdministrationEvent>)
  end

  it "skips a vaccine group with no evaluation status observation" do
    evaluations = evaluations_for(event(component(status: false) + component))

    expect(evaluations.size).to eq(1)
    expect(evaluations.first[:status]).to eq(code: "ACCEPTED", name: "Accepted Dose")
  end

  it "returns nil validity when ICE omits isValid" do
    expect(evaluations_for(event(component)).first[:valid]).to be_nil
  end

  it "reads isValid as a boolean" do
    expect(evaluations_for(event(component(is_valid: "false"))).first[:valid]).to be(false)
  end
end
