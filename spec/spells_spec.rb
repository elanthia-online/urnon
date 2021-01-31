require 'spec_helper'
require 'urnon/spells/spells'

SPELL_FILE = File.join(__dir__, "mocks", "spells.xml")

RSpec.describe Spells do
  it "fails" do
    pp Spells::Registry.load SPELL_FILE
  end
end
