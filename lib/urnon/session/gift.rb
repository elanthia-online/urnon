class Gift
  def initialize()
    @gift_start  ||= Time.now
    @pulse_count ||= 0
  end

  def started
    @gift_start = Time.now
    @pulse_count = 0
  end

  def pulse
    @pulse_count += 1
  end

  def remaining
    ([360 - @pulse_count, 0].max * 60).to_f
  end

  def restarts_on
    @gift_start + 594000
  end

  def serialize
    [@gift_start, @pulse_count]
  end

  def load_serialized=(array)
    @gift_start = array[0]
    @pulse_count = array[1].to_i
  end

  def ended
    @pulse_count = 360
  end
end
