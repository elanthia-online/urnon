require 'spec_helper'
require 'timeout'
require 'urnon/script/script'
require 'urnon/session'
SCRIPT_DIR = File.join(__dir__, "scripts")

RSpec.describe Script do
  before(:each) do
    # kill running scripts
    Script.list.each(&:kill)
  end

  let(:session_1) {
    sess = Session.new("127.0.0.1", 8020, 8040)
    sess.set_socks client: StringIO.new
    sess
  }

  let(:session_2) {
    sess = Session.new("127.0.0.1", 8021, 8041)
    sess.set_socks client: StringIO.new
    sess
  }

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
    add = Script.run("add", "2 3", session: session_1)
    expect(add.value).to be(5)
    expect(Script.list.include?(add)).to be(false)
    expect(session_1.client_sock.string).to include(%[add exiting with status: ok in])
  end

  it "Script.start" do
    sleeper = Script.start("sleep", session: session_1)
    # if we kill the thread too fast it won't actually have spun up
    sleep 0.1
    expect(Script.running?("sleep")).to be(true)
    expect(Script.list).to include(sleeper)
    Script.kill(sleeper)
    expect(Script.list).to_not include(sleeper)
    output = session_1.client_sock.string
    expect(output).to include(%[sleep exiting with status: killed in])
  end

  it "Script.run / nested" do
    nested = Script.start("nested/run", session: session_1)
    sleep 0.1
    expect(Script.running?("nested/run")).to be(true)
    expect(Script.running?("sleep")).to be(true)
    Script.kill(nested)
    expect(Script.running?("nested/run")).to be(false)
    expect(Script.running?("sleep")).to be(true)
  end

  it "Script.start / exit" do
    exiter = Script.start("exit", session: session_1)
    sleep 0.1
    expect(Script.list.include?(exiter)).to be(false)
    expect(exiter.status).to eq(:bail)
  end

  it "Script.start / sub-thread" do
    subthread = Script.run("subthread", session: session_1)
    #expect($test.thread.alive?).to be(false)
    expect($test.thread.parent).to be(nil)
    expect(Script.list.include?(subthread)).to be(false)
  end

  it "Script.run / double" do
    Script.start("sleep", session: session_1)
    expect(Script.start("sleep", session: session_1)).to eq(:already_running)
  end

  it "Script.kill / before_dying" do
    script = Script.start("before_dying", session: session_1)
    # wait until the script has done some work
    sleep 0.1 until script.status.eql?("sleep")
    expect(script.at_exit_procs.size).to eq(1)
    Script.kill(script)
    expect($at_exit_called).to be(true)
    expect(Script.list).to_not include(script)
  end

  it "Script.kill / tight-loop" do
    script = Script.start("tight-loop", session: session_1)
    sleep 0.1 until $i == 0
    Script.kill(script)
    expect(script.status).to be(Script::Status::Killed)
    expect($i).to be(0)
  end

  it "Script.run / handles errors" do
    script = Script.run("err", session: session_1)
    expect(script.status).to be(Script::Status::Err)
  end

  it "Script.run + internal Script.kill / top-level is fine" do
    looper  = Script.start("tight-loop", session: session_1)
    sleep 0.1
    killer  = Script.run("killer", looper.name, session: session_1)
    case killer.value
    in {ok:}
      ok
    else
      fail "unknown outcome"
    end
  end

  it "Script.runtime / encapsulation between sessions" do
    run_1 = Script.run("scope", session: session_1)
    run_2 = Script.run("scope", session: session_2)
    scope_1 = run_1.value
    scope_2 = run_2.value
    expect(scope_1).not_to be(scope_2)
    expect(scope_1.uuid).not_to be_nil
    expect(scope_2.uuid).not_to be_nil
    expect(scope_1.uuid).not_to eq(scope_2.uuid)
    expect(session_1.client_sock.string).to include "urnon: scope exiting with status: ok in"
    expect(session_2.client_sock.string).to include "urnon: scope exiting with status: ok in"
  end
end
