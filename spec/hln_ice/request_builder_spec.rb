# frozen_string_literal: true

require "base64"

RSpec.describe HlnIce::RequestBuilder do
  let(:patient_data) do
    {
      patient: { id: "12345", date_of_birth: "2020-01-01", gender: "F" },
      immunizations: [
        {
          clinicalStatements: {
            substanceAdministrationEvents: [
              {
                id: "1",
                substance: { substanceCode: { code: "10", displayName: "Polio" } },
                administrationTimeInterval: { low: "2020-03-01", high: "2020-03-02" }
              },
              {
                substance: { substanceCode: { code: "141", displayName: "Influenza" } },
                administrationTimeInterval: { low: "2020-10-01", high: "2020-10-01" }
              },
              { substance: {}, administrationTimeInterval: { low: "2020-11-01", high: "2020-11-01" } }
            ]
          }
        }
      ]
    }
  end

  let(:builder) { described_class.new(patient_data) }
  let(:doc) { Nokogiri::XML(builder.xml).tap(&:remove_namespaces!) }
  let(:events) { doc.xpath("//substanceAdministrationEvent") }

  it "writes the patient's demographics, with dates in ICE format" do
    expect(doc.at_xpath("//patient/id")["extension"]).to eq("12345")
    expect(doc.at_xpath("//birthTime")["value"]).to eq("20200101")
    expect(doc.at_xpath("//gender")["code"]).to eq("F")
  end

  it "defaults a blank gender to 'U'" do
    patient_data[:patient][:gender] = " "

    expect(doc.at_xpath("//gender")["code"]).to eq("U")
  end

  it "writes one event per immunization with a substance code" do
    expect(events.map { |e| e.at_xpath("./substance/substanceCode")["code"] }).to eq(%w[10 141])
    expect(events.first.at_xpath("./administrationTimeInterval").to_h).to eq("low" => "20200301", "high" => "20200302")
  end

  it "uses the caller's event id, or a generated UUID when there is none" do
    allow(SecureRandom).to receive(:uuid).and_return("generated")

    expect(events.map { |e| e.at_xpath("./id")["root"] }).to eq(%w[1 generated])
  end

  it "writes an empty event list when there are no immunizations" do
    patient_data.delete(:immunizations)

    expect(events).to be_empty
  end

  it "carries the XML base64 encoded in the payload" do
    encoded = builder.payload.dig("evaluationRequest", "dataRequirementItemData", 0, "data", "base64EncodedPayload", 0)

    expect(Base64.decode64(encoded)).to eq(builder.xml)
  end
end
