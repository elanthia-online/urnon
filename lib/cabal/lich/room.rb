class Room < Map
  def Room.method_missing(*args)
     super(*args)
  end
end