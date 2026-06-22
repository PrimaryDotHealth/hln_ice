# frozen_string_literal: true

RSpec.describe HlnIce do
  it "has a version number" do
    expect(HlnIce::VERSION).not_to be nil
  end

  it "loads the client" do
    expect(defined?(HlnIce::Client)).to eq("constant")
  end
end
