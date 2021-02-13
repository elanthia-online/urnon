require 'urnon/util/sessionize'

class Society
  extend Sessionize.new receiver: :society

  attr_accessor :rank, :status

  def initialize(session)
    @status  = ""
    @rank    = 0
    @session = session
  end

  def rank=(val)
    if val =~ /Master/
      if @status =~ /Voln/
        @rank = 26
      elsif @status =~ /Council of Light|Guardians of Sunfist/
        @rank = 20
      else
        @rank = val.to_i
      end
    else
      @rank = val.slice(/[0-9]+/).to_i
    end
  end

  def task
    Session.current.xml_data.society_task
  end

  def serialize
    [@status,@rank]
  end

  def load_serialized=(val)
    @status,@rank = val
  end
end
