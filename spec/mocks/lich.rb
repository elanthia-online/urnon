$fake_game_output = ""

def respond(*args)
  $fake_game_output = $fake_game_output + "\n" + args.join("\n")
end

def game_output
  buffered = $fake_game_output.dup
  $fake_game_output = ""
  return buffered
end
