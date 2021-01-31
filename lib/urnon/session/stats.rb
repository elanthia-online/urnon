require 'urnon/util/sessionize'

class Stats
  extend Sessionize.new receiver: :stats

  attr_accessor :race, :prof, :gender, :age, :level,
                :str, :con, :dex, :agi, :dis, :aur, :log, :int, :wis, :inf,
                :enhanced_str, :enhanced_con, :enhanced_dex, :enhanced_agi, :enhanced_dis,
                :enhanced_aur, :enhanced_log, :enhanced_int, :enhanced_wis, :enhanced_inf

  def initialize()
    @race ||= 'unknown'
    @prof ||= 'unknown'
    @gender ||= 'unknown'
    @age ||= 0
    @level ||= 0
    @str ||= [0,0]
    @con ||= [0,0]
    @dex ||= [0,0]
    @agi ||= [0,0]
    @dis ||= [0,0]
    @aur ||= [0,0]
    @log ||= [0,0]
    @int ||= [0,0]
    @wis ||= [0,0]
    @inf ||= [0,0]
    @enhanced_str ||= [0,0]
    @enhanced_con ||= [0,0]
    @enhanced_dex ||= [0,0]
    @enhanced_agi ||= [0,0]
    @enhanced_dis ||= [0,0]
    @enhanced_aur ||= [0,0]
    @enhanced_log ||= [0,0]
    @enhanced_int ||= [0,0]
    @enhanced_wis ||= [0,0]
    @enhanced_inf ||= [0,0]
  end

  def exp
    if Session.current.xml_data.next_level_text =~ /until next level/
      exp_threshold = [ 2500, 5000, 10000, 17500, 27500, 40000, 55000, 72500, 92500, 115000, 140000, 167000, 197500, 230000, 265000, 302000, 341000, 382000, 425000, 470000, 517000, 566000, 617000, 670000, 725000, 781500, 839500, 899000, 960000, 1022500, 1086500, 1152000, 1219000, 1287500, 1357500, 1429000, 1502000, 1576500, 1652500, 1730000, 1808500, 1888000, 1968500, 2050000, 2132500, 2216000, 2300500, 2386000, 2472500, 2560000, 2648000, 2736500, 2825500, 2915000, 3005000, 3095500, 3186500, 3278000, 3370000, 3462500, 3555500, 3649000, 3743000, 3837500, 3932500, 4028000, 4124000, 4220500, 4317500, 4415000, 4513000, 4611500, 4710500, 4810000, 4910000, 5010500, 5111500, 5213000, 5315000, 5417500, 5520500, 5624000, 5728000, 5832500, 5937500, 6043000, 6149000, 6255500, 6362500, 6470000, 6578000, 6686500, 6795500, 6905000, 7015000, 7125500, 7236500, 7348000, 7460000, 7572500 ]
      exp_threshold[Session.current.xml_data.level] - Session.current.xml_data.next_level_text.slice(/[0-9]+/).to_i
    else
      Session.current.xml_data.next_level_text.slice(/[0-9]+/).to_i
    end
  end

  def serialize
    [@race,@prof,@gender,@age,exp,@level,@str,@con,@dex,@agi,@dis,@aur,@log,@int,@wis,@inf]
  end

  def load_serialized=(array)
    @race,@prof,@gender,@age = array[0..3]
    @level,@str,@con,@dex,@agi,@dis,@aur,@log,@int,@wis,@inf = array[5..15]
  end
end
