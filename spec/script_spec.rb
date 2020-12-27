require 'spec_helper'
load 'lib/script.rb'
SCRIPT_DIR = File.join(__dir__, "scripts")

describe Script do
  before(:each) do
    # kill running scripts
    Script.list.each(&:kill)
    # cleanup game output
    game_output
  end

  it "Script.match" do
    expect(Script.match("ad").size).to eq(1)
  end

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
    expect(game_output).to include(%[add exiting with status: ok in])
  end

  it "Script.start" do
    sleeper = Script.start("sleep")
    expect(Script.running?("sleep")).to be(true)
    expect(Script.list).to include(sleeper)
    sleeper.kill
    expect(game_output).to include(%[sleep exiting with status: killed in])
    expect(Script.list).to_not include(sleeper)
  end

  it "Script.run / nested" do
    nested = Script.start("nested/run")
    sleep 0.1
    expect(Script.running?("nested/run")).to be(true)
    expect(Script.running?("sleep")).to be(true)
    nested.kill
    expect(Script.running?("nested/run")).to be(false)
    expect(Script.running?("sleep")).to be(true)
  end

  it "Script.start / exit" do
    exiter = Script.start("exit")
    sleep 0.1
    expect(Script.list.include?(exiter)).to be(false)
    expect(exiter.status).to eq(:bail)
  end
end
