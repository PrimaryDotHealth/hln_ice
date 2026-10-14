# frozen_string_literal: true

RSpec.describe HlnIce::ResponseParser do
  # Recorded from a real ICE 2.59.1 server with ICE_OUTPUTSERIESINFORMATION and
  # ICE_OUTPUTNUMBEROFDOSESREMAINING on. Synthetic patient (born 1990-01-01,
  # F) with input events "e1" (CVX 43 Hep B) and "e2" (CVX 03 MMR), both given
  # on 2025-01-01. The reordered variant is the same response with every group
  # of sibling observations reversed, so each series block swaps places with
  # its status block.
  def fixture_data(name)
    described_class.new(File.read(File.expand_path("../fixtures/ice/#{name}.json", __dir__))).data
  end

  def by_vaccine(recommendations)
    recommendations.to_h { |recommendation| [recommendation[:vaccine][:name], recommendation] }
  end

  let(:data) { fixture_data("evaluate_series_output") }
  let(:recommendations) { by_vaccine(data[:recommendations]) }

  it "reads each recommendation's status and reasons from its vaccine group observation" do
    statuses = data[:recommendations].to_h do |recommendation|
      [recommendation[:vaccine][:name], [recommendation[:status][:code], recommendation[:reasons].map { _1[:code] }]]
    end

    expect(statuses).to eq(
      "HPV Vaccine Group" => ["CONDITIONAL", %w[CLINICAL_PATIENT_DISCRETION SUPPLEMENTAL_TEXT]],
      "Tdap" => ["RECOMMENDED", %w[DUE_NOW]],
      "Hep A Vaccine Group" => ["CONDITIONAL", %w[HIGH_RISK]],
      "Polio Vaccine Group" => ["CONDITIONAL", %w[HIGH_RISK SUPPLEMENTAL_TEXT]],
      "Cholera Vaccine Group" => ["CONDITIONAL", %w[HIGH_RISK SUPPLEMENTAL_TEXT]],
      "Mpox Vaccine Group" => ["CONDITIONAL", %w[HIGH_RISK]],
      "COVID-19 Vaccine Group" => ["RECOMMENDED", %w[DUE_NOW]],
      "Pneumococcal Vaccine Group" => ["FUTURE_RECOMMENDED",
                                       %w[DUE_IN_FUTURE ADMINISTER_PCV15_PCV20_OR_PCV21 SUPPLEMENTAL_TEXT]],
      "Hep B Vaccine Group" => ["RECOMMENDED", %w[DUE_NOW]],
      "Rotavirus Vaccine Group" => ["NOT_RECOMMENDED", %w[TOO_OLD_TO_INITIATE]],
      "Zoster recombinant" => ["FUTURE_RECOMMENDED", %w[DUE_IN_FUTURE]],
      "Varicella Vaccine Group" => ["RECOMMENDED", %w[DUE_NOW]],
      "Meningococcal ACWY Vaccine Group" => ["CONDITIONAL", %w[HIGH_RISK]],
      "Yellow Fever Vaccine Group" => ["CONDITIONAL", %w[HIGH_RISK SUPPLEMENTAL_TEXT]],
      "Influenza Vaccine Group" => ["RECOMMENDED", %w[DUE_NOW]],
      "Japanese Encephalitis Vaccine Group" => ["CONDITIONAL", %w[HIGH_RISK SUPPLEMENTAL_TEXT]],
      "Typhoid Vaccine Group" => ["CONDITIONAL", %w[HIGH_RISK SUPPLEMENTAL_TEXT]],
      "RSV Vaccine Group" => ["FUTURE_RECOMMENDED", %w[DUE_IN_FUTURE SUPPLEMENTAL_TEXT]],
      "MMR Vaccine Group" => ["NOT_RECOMMENDED", %w[COMPLETE_HIGH_RISK]],
      "Meningococcal B Vaccine Group" => ["CONDITIONAL", %w[HIGH_RISK]],
      "Hib Vaccine Group" => ["CONDITIONAL", %w[HIGH_RISK]]
    )
  end

  it "never reports a series code as a status" do
    statuses = %w[RECOMMENDED FUTURE_RECOMMENDED CONDITIONAL NOT_RECOMMENDED]

    expect(data[:recommendations].map { _1[:status][:code] }).to all(satisfy { statuses.include?(_1) })
  end

  it "parses the Hep B recommendation, whose series block precedes its status" do
    expect(recommendations["Hep B Vaccine Group"]).to eq(
      vaccine: { code: "100", code_system: "2.16.840.1.113883.3.795.12.100.1", name: "Hep B Vaccine Group" },
      status: { code: "RECOMMENDED", name: "Recommended" },
      reasons: [{ code: "DUE_NOW", name: "Due now." }],
      intervals: { proposed: { low: "2025-01-29" }, valid: { low: "2025-01-29" } },
      schedule_authorities: [
        { code: "AAP", name: "American Academy of Pediatrics" },
        { code: "AAFP", name: "American Academy of Family Physicians" }
      ]
    )
  end

  it "parses the same result whatever order ICE puts the observation blocks in" do
    reordered = fixture_data("evaluate_series_output_reordered")

    expect(reordered[:raw_xml]).not_to eq(data[:raw_xml])
    expect(reordered.except(:raw_xml)).to eq(data.except(:raw_xml))
  end
end
