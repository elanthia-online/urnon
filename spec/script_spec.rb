require 'spec_helper'
require 'timeout'
load 'lib/script/script.rb'
SCRIPT_DIR = File.join(__dir__, "scripts")

RSpec.describe Script do
  before(:each) do
    # kill running scripts
    Script.list.each(&:kill)
    # cleanup game output
    game_output
  end

  it "Script.match" do
    expect(Script.match("add").size).to eq(1)
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
    Script.kill(sleeper)
    expect(Script.list).to_not include(sleeper)
    output = game_output
    expect(output).to include(%[sleep exiting with status: killed in])
  end

  it "Script.run / nested" do
    nested = Script.start("nested/run")
    sleep 0.1
    expect(Script.running?("nested/run")).to be(true)
    expect(Script.running?("sleep")).to be(true)
    Script.kill(nested)
    expect(Script.running?("nested/run")).to be(false)
    expect(Script.running?("sleep")).to be(true)
  end

  it "Script.start / exit" do
    exiter = Script.start("exit")
    sleep 0.1
    expect(Script.list.include?(exiter)).to be(false)
    expect(exiter.status).to eq(:bail)
  end

  it "Script.start / sub-thread" do
    subthread = Script.run("subthread")
    #expect($test.thread.alive?).to be(false)
    expect($test.thread.parent).to be(nil)
    expect(Script.list.include?(subthread)).to be(false)
  end

  it "Script.run / double" do
    Script.start("sleep")
    expect(Script.start("sleep")).to eq(:already_running)
  end

  it "Script.kill / before_dying" do
    script = Script.start("before_dying")
    # wait until the script has done some work
    sleep 0.1 until script.status.eql?("sleep")
    expect(script.at_exit_procs.size).to eq(1)
    Script.kill(script)
    expect($at_exit_called).to be(true)
    expect(Script.list).to_not include(script)
  end

  it "Script.kill / tight-loop" do
    script = Script.start("tight-loop")
    sleep 0.1 until $i == 0
    Script.kill(script)
    expect(script.status).to be(Script::Status::Killed)
    expect($i).to be(0)
  end

  it "Script.run / handles errors" do
    script = Script.run("err")
    expect(script.status).to be(Script::Status::Err)
  end

  it "Script.run + internal Script.kill / top-level is fine" do
    looper  = Script.start("tight-loop")
    sleep 0.1
    killer  = Script.run("killer", looper.name)
    case killer.value
    in {ok:}
      ok
    else
      fail "unknown outcome"
    end
  end
end
