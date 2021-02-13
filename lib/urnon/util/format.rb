module Format
  def self.time(seconds)
    return milliseconds(seconds) if seconds < 5
    days    = (seconds / 86_400).floor
    seconds = seconds - (days * 86_400)
    hours   = (seconds / 3_600).floor
    seconds = seconds - (hours * 3_600)
    minutes = (seconds / 60).floor
    seconds = (seconds - (minutes * 60)).floor


    [days, hours, minutes, seconds]
      .zip(%w(d h m s))
      .select { |f| f.first > 0 }
      .map {|f| f.first.to_s.rjust(2, "0") + f.last }
      .reduce("") { |acc, col| acc + " " + col }
      .strip
  end

  def self.milliseconds(seconds)
    "%s ms" % ((seconds * 1_000).round).to_i
  end
end
