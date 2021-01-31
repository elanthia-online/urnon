require 'urnon/util/sessionize'

class GameObj
  # put GameObj in global space for backwards compatibility
  extend Sessionize.new receiver: :game_obj_registry

  class Registry
    attr_reader :loot, :npcs, :npc_status, :pcs, :pc_status, :inv, :contents,
                :right_hand, :left_hand, :room_desc, :fam_loot, :fam_npcs,
                :fam_pcs, :fam_room_desc, :type_data, :sellable_data

    def initialize()
      @loot          = Array.new
      @npcs          = Array.new
      @npc_status    = Hash.new
      @pcs           = Array.new
      @pc_status     = Hash.new
      @inv           = Array.new
      @contents      = Hash.new
      @right_hand    = nil
      @left_hand     = nil
      @room_desc     = Array.new
      @fam_loot      = Array.new
      @fam_npcs      = Array.new
      @fam_pcs       = Array.new
      @fam_room_desc = Array.new
      @type_data     = Hash.new
      @sellable_data = Hash.new
    end

    def [](val)
      if val.class == String
          if val =~ /^\-?[0-9]+$/
            return @inv.find { |o| o.id == val } || @loot.find { |o| o.id == val } || @npcs.find { |o| o.id == val } || @pcs.find { |o| o.id == val } || [ @right_hand, @left_hand ].find { |o| o.id == val } || @room_desc.find { |o| o.id == val }
          elsif val.split(' ').length == 1
            return @inv.find { |o| o.noun == val } || @loot.find { |o| o.noun == val } || @npcs.find { |o| o.noun == val } || @pcs.find { |o| o.noun == val } || [ @right_hand, @left_hand ].find { |o| o.noun == val } || @room_desc.find { |o| o.noun == val }
          else
            return @inv.find { |o| o.name == val } || @loot.find { |o| o.name == val } || @npcs.find { |o| o.name == val } || @pcs.find { |o| o.name == val } || [ @right_hand, @left_hand ].find { |o| o.name == val } || @room_desc.find { |o| o.name == val } || @inv.find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || @loot.find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || @npcs.find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || @pcs.find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || [ @right_hand, @left_hand ].find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || @room_desc.find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || @inv.find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i } || @loot.find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i } || @npcs.find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i } || @pcs.find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i } || [ @right_hand, @left_hand ].find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i } || @room_desc.find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i }
          end
      elsif val.class == Regexp
          return @inv.find { |o| o.name =~ val } || @loot.find { |o| o.name =~ val } || @npcs.find { |o| o.name =~ val } || @pcs.find { |o| o.name =~ val } || [ @right_hand, @left_hand ].find { |o| o.name =~ val } || @room_desc.find { |o| o.name =~ val }
      end
    end

    def new_npc(session, id, noun, name, status=nil)
      obj = GameObj.new(session, id, noun, name)
      @npcs.push(obj)
      @npc_status[id] = status
      obj
    end

    def new_loot(session, id, noun, name)
      obj = GameObj.new(session, id, noun, name)
      @loot.push(obj)
      obj
    end

    def new_pc(session, id, noun, name, status=nil)
      obj = GameObj.new(session, id, noun, name)
      @pcs.push(obj)
      @pc_status[id] = status
      obj
    end

    def new_inv(session, id, noun, name, container=nil, before=nil, after=nil)
      obj = GameObj.new(session, id, noun, name, before, after)
      if container
          @contents[container].push(obj)
      else
          @inv.push(obj)
      end
      obj
    end

    def new_room_desc(session, id, noun, name)
      obj = GameObj.new(session, id, noun, name)
      @room_desc.push(obj)
      obj
    end

    def new_fam_room_desc(session, id, noun, name)
      obj = GameObj.new(session, id, noun, name)
      @fam_room_desc.push(obj)
      obj
    end

    def new_fam_loot(session, id, noun, name)
      obj = GameObj.new(session, id, noun, name)
      @fam_loot.push(obj)
      obj
    end

    def new_fam_npc(session, id, noun, name)
      obj = GameObj.new(session, id, noun, name)
      @fam_npcs.push(obj)
      obj
    end

    def new_fam_pc(session, id, noun, name)
      obj = GameObj.new(session, id, noun, name)
      @fam_pcs.push(obj)
      obj
    end

    def new_right_hand(session, id, noun, name)
      @right_hand = GameObj.new(session, id, noun, name)
    end

    def new_left_hand(session, id, noun, name)
      @left_hand = GameObj.new(session, id, noun, name)
    end

    def clear_loot
      @loot.clear
    end

    def clear_npcs
      @npcs.clear
      @npc_status.clear
    end

    def clear_pcs
      @pcs.clear
      @pc_status.clear
    end

    def clear_inv
      @inv.clear
    end

    def clear_room_desc
      @room_desc.clear
    end

    def clear_fam_room_desc
      @fam_room_desc.clear
    end

    def clear_fam_loot
      @fam_loot.clear
    end

    def clear_fam_npcs
      @fam_npcs.clear
    end

    def clear_fam_pcs
      @fam_pcs.clear
    end

    def clear_container(container_id)
      @contents[container_id] = Array.new
    end

    def delete_container(container_id)
      @contents.delete(container_id)
    end

    def targets
      @npcs.select { |n| Session.current.xml_data.current_target_ids.include?(n.id) }
    end

    def dead
      @npcs.select {|npc| npc.status.eql?("dead")}
    end

    def load_data(filename=nil)
      filename = "#{DATA_DIR}/gameobj-data.xml" if filename.nil?
      if File.exists?(filename)
        begin
          @type_data = Hash.new
          @sellable_data = Hash.new
          File.open(filename) { |file|
              doc = REXML::Document.new(file.read)
              doc.elements.each('data/type') { |e|
                if type = e.attributes['name']
                    @type_data[type] = Hash.new
                    @type_data[type][:name]    = Regexp.new(e.elements['name'].text) unless e.elements['name'].text.nil? or e.elements['name'].text.empty?
                    @type_data[type][:noun]    = Regexp.new(e.elements['noun'].text) unless e.elements['noun'].text.nil? or e.elements['noun'].text.empty?
                    @type_data[type][:exclude] = Regexp.new(e.elements['exclude'].text) unless e.elements['exclude'].text.nil? or e.elements['exclude'].text.empty?
                end
              }
              doc.elements.each('data/sellable') { |e|
                if sellable = e.attributes['name']
                    @sellable_data[sellable] = Hash.new
                    @sellable_data[sellable][:name]    = Regexp.new(e.elements['name'].text) unless e.elements['name'].text.nil? or e.elements['name'].text.empty?
                    @sellable_data[sellable][:noun]    = Regexp.new(e.elements['noun'].text) unless e.elements['noun'].text.nil? or e.elements['noun'].text.empty?
                    @sellable_data[sellable][:exclude] = Regexp.new(e.elements['exclude'].text) unless e.elements['exclude'].text.nil? or e.elements['exclude'].text.empty?
                end
              }
          }
          true
        rescue
          @type_data = nil
          @sellable_data = nil
          echo "error: GameObj.load_data: #{$!}"
          respond $!.backtrace[0..1]
          false
        end
      else
        @type_data = nil
        @sellable_data = nil
        echo "error: GameObj.load_data: file does not exist: #{filename}"
        false
      end
    end
  end
end
