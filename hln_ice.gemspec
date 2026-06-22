# frozen_string_literal: true

require_relative "lib/hln_ice/version"

Gem::Specification.new do |spec|
  spec.name = "hln_ice"
  spec.version = HlnIce::VERSION
  spec.authors = ["Sam Sohn"]
  spec.email = ["sam@primary.health"]

  spec.summary = "Ruby client for the HLN ICE (Immunization Calculation Engine) OpenCDS service."
  spec.description = "Evaluates a patient's immunization history against the HLN ICE forecasting " \
                     "rules and returns both the raw recommendations and a simplified status mapping."
  spec.homepage = "https://github.com/PrimaryDotHealth/hln_ice"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "httparty", "~> 0.21"
  spec.add_dependency "nokogiri", "~> 1.15"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
