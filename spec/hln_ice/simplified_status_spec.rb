# frozen_string_literal: true

RSpec.describe HlnIce::SimplifiedStatus do
  def recommendation(group, status, reasons = [])
    { vaccine: { name: group }, status: { code: status }, reasons: }
  end

  def status_for(*recommendations)
    described_class.new(recommendations).to_h
  end

  it "maps ICE statuses to our statuses" do
    expect(
      status_for(
        recommendation("Polio Vaccine Group", "RECOMMENDED"),
        recommendation("MMR Vaccine Group", "FUTURE_RECOMMENDED"),
        recommendation("HPV Vaccine Group", "NOT_RECOMMENDED"),
        recommendation("Hep B Vaccine Group", "CONDITIONAL")
      )
    ).to eq(ipv_opv: "overdue", mmr: "compliant", hpv: "compliant", hep_b: "conditional")
  end

  it "treats an unknown status as overdue" do
    expect(status_for(recommendation("Polio Vaccine Group", "SOMETHING_NEW"))).to eq(ipv_opv: "overdue")
  end

  it "marks a conditional recommendation with a medical exemption as medically exempt" do
    exempt = recommendation("Varicella Vaccine Group", "CONDITIONAL", [{ code: "MEDICAL_EXEMPTION" }])

    expect(status_for(exempt)).to eq(var: "medically_exempt")
  end

  it "skips vaccine groups we have no key for" do
    expect(status_for(recommendation("Zoster Vaccine Group", "RECOMMENDED"))).to eq({})
  end
end
