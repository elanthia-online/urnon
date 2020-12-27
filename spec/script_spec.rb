require 'spec_helper'
load 'lib/script.rb'
SCRIPT_DIR = File.join(__dir__, "scripts")

describe Script do
  it "Script.exists?" do
    expect(Script.exists?("noop")).to be(true)
    expect(Script.exists?("404")).to be(false)
    expect(Script.exists?("nested")).to be(false)
    expect(Script.exists?("nested/example")).to be(true)
    expect(Script.exists?("example")).to be(true)
  end

  it "Script.run -> value" do
    add = Script.run("add", "2 3")
    expect(add.value).to be(5)
    expect(Script.list.include?(add)).to be(false)
    expect(game_output).to include(%[add exiting with status: 0 in])
  end

  it "Script.start" do
    sleeper = Script.start("sleep")
    expect(Script.running?("sleep")).to be(true)
    expect(Script.list).to include(sleeper)
    sleeper.kill
  end
end
