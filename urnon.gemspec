# frozen_string_literal: true

require_relative "lib/urnon/version"

Gem::Specification.new do |spec|
  spec.name          = "urnon"
  spec.version       = Urnon::VERSION
  spec.authors       = ["Benjamin Clos"]
  spec.email         = ["benjamin.clos@gmail.com"]
  spec.summary       = "Gemstone IV scripting engine"
  spec.description   = "Gemstone IV scripting engine"
  spec.homepage      = "https://github.com/elanthia-online/urnon"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/elanthia-online/urnon"
  #spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  spec.add_dependency "xdg"
  spec.add_dependency "thor"
  spec.add_dependency "rexml"
  spec.add_dependency "sequel"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
