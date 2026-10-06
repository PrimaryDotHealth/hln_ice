# frozen_string_literal: true

module HlnIce
  # Maps parsed recommendations to a simplified status keyed by our
  # immunization keys, e.g. { ipv_opv: "overdue", mmr: "compliant" }.
  class SimplifiedStatus
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

    def initialize(recommendations)
      @recommendations = recommendations
    end

    def to_h
      # Create simplified immunization status mapping
      simplified_status = {}

      # Process all recommendations to create the simplified mapping
      recommendations.each do |recommendation|
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

      simplified_status
    end

    private
      attr_reader :recommendations
  end
end
