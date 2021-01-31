require 'spec_helper'
require 'cabal/session/spells'

SPELL_FILE = File.join(__dir__, "mocks", "spells.xml")

RSpec.describe Spells do
  it "fails" do
    pp Spells::Registry.load SPELL_FILE
  end
end
