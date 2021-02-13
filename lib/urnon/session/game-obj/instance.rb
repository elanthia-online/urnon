class GameObj
  attr_reader :id, :session, :noun, :name, :before_name, :after_name

  def initialize(session, id, noun, name, before=nil, after=nil)
    @session = session
    @id = id
    @noun = noun
    @noun = 'lapis' if @noun == 'lapis lazuli'
    @noun = 'hammer' if @noun == "Hammer of Kai"
    @noun = 'mother-of-pearl' if (@noun == 'pearl') and (@name =~ /mother\-of\-pearl/)
    @name = name
    @before_name = before
    @after_name = after
  end

  def type
    @session.game_obj_registry.load_data if @session.game_obj_registry.type_data.empty?
    list = @session.game_obj_registry.type_data.keys.find_all { |t| (@name =~ @session.game_obj_registry.type_data[t][:name] or @noun =~ @session.game_obj_registry.type_data[t][:noun]) and (@session.game_obj_registry.type_data[t][:exclude].nil? or @name !~ @session.game_obj_registry.type_data[t][:exclude]) }
    if list.empty?
      nil
    else
      list.join(',')
    end
  end

  def sellable
    @session.game_obj_registry.load_data if @session.game_obj_registry.sellable_data.empty?
    list = @session.game_obj_registry.sellable_data.keys.find_all { |t| (@name =~ @session.game_obj_registry.sellable_data[t][:name] or @noun =~ @session.game_obj_registry.sellable_data[t][:noun]) and (@session.game_obj_registry.sellable_data[t][:exclude].nil? or @name !~ @session.game_obj_registry.sellable_data[t][:exclude]) }
    if list.empty?
      nil
    else
      list.join(',')
    end
  end

  def status
    if @session.game_obj_registry.npc_status.keys.include?(@id)
      @session.game_obj_registry.npc_status[@id]
    elsif @session.game_obj_registry.pc_status.keys.include?(@id)
      @session.game_obj_registry.pc_status[@id]
    elsif @session.game_obj_registry.loot.find { |obj| obj.id == @id } or @session.game_obj_registry.inv.find { |obj| obj.id == @id } or @session.game_obj_registry.room_desc.find { |obj| obj.id == @id } or @session.game_obj_registry.fam_loot.find { |obj| obj.id == @id } or @session.game_obj_registry.fam_npcs.find { |obj| obj.id == @id } or @session.game_obj_registry.fam_pcs.find { |obj| obj.id == @id } or @session.game_obj_registry.fam_room_desc.find { |obj| obj.id == @id } or (@session.game_obj_registry.right_hand.id == @id) or (@session.game_obj_registry.left_hand.id == @id) or @session.game_obj_registry.contents.values.find { |list| list.find { |obj| obj.id == @id  } }
      nil
    else
      'gone'
    end
  end

  def status=(val)
    if @session.game_obj_registry.npcs.any? { |npc| npc.id == @id }
      @session.game_obj_registry.npc_status[@id] = val
    elsif @session.game_obj_registry.pcs.any? { |pc| pc.id == @id }
      @session.game_obj_registry.pc_status[@id] = val
    else
      nil
    end
  end

  def to_s
    @noun
  end

  def empty?
    false
  end

  def contents
    @session.game_obj_registry.contents[@id].dup
  end

  def full_name
    "#{@before_name}#{' ' unless @before_name.nil? or @before_name.empty?}#{name}#{' ' unless @after_name.nil? or @after_name.empty?}#{@after_name}"
  end
end
