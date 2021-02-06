class Spells
  module Registry
    @mutex  ||= Mutex.new
    @spells ||= []

    def self.load(filename=nil)
      Script.current
      filename = filename.is_a?(String) ? filename : File.join(DATA_DIR, "spell-list.xml")

      @mutex.synchronize {
        return true unless @spells.empty?
        begin

          File.open(filename) { |file|
            xml_doc = REXML::Document.new(file)
            xml_root = xml_doc.root
            xml_root.elements.each { |xml_spell|
              @spells << Spells::Record.new(xml_spell)
            }
          }

          return true
        rescue
          respond "--- Lich: error: Spell.load: #{$!}"
          Lich.log "error: Spell.load: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
          @spells.clear
          return false
        end
      }
    end

    def self.spells()
      @spells
    end

    def self.query(q)
      case q
      when Integer
        @spells.find {|spell| spell.num.eql?(q)}
      when /\d+/
        @spells.find {|spell| spell.num.eql?(q.to_i) }
      else
        @spells.find {|spell| spell.name.start_with?(q)}
      end
    end
  end
end
