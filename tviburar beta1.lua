local screen_dirty = true
local m = midi.connect()
local music = require("musicutil")
local lattice = require("lattice")
local scales = {}
local scale = {}
local current_beat = 0
local lfo_val = 0
local lfo_tim = 0

function init()
  for i = 1, #music.SCALES do
    table.insert(scales, string.lower(music.SCALES[i].name))
  end

  time_handler = lattice:new()
  global_timer = time_handler:new_pattern{
    action = function (x) 
        current_beat = current_beat + 1
        if current_beat > 4 then current_beat = 1 end
        play(note)
        clock.run(midi_hang,note,params:get("midi_channel"))
        screen_dirty = true
    end,
    division = 1/4
  }

  add_params()
  scale = music.generate_scale(params:get("root_note")-1, x, 10) 
  time_handler:start()
  clock.run(go)
  clock.run(lfo_updater)
end

function add_params()
  params:add_option("scale","scale",scales,1)
  params:set_action("scale", function (x) 
    scale = music.generate_scale(params:get("root_note")-1, x, 10) 
  end)
  params:add_option("root_note", "root note", music.note_nums_to_names({0,1,2,3,4,5,6,7,8,9,10,11}),1)
  params:add_number("midi_device", "midi device", 1, #midi.vports, 1)
  m = midi.connect(params:get("midi_device"))
  params:set_action("midi_device", function (x) 
    m = midi.connect(x)
  end)
  params:add_number("midi_channel", "midi channel", 1, 16, 1)
  params:add_number("gate_length", "gate length %", 0, 100, 50)
end

function redraw()
  screen.clear()
  screen.font_face(0)
  screen.font_size(16)
  screen.level(15)
  screen.move(10,20)
  screen.text(current_beat)
  screen.update()
end

function go()
    while true do
        clock.sleep(1/15)
        if screen_dirty then 
            redraw()
            screen_dirty = false
        end
    end
end

function lfo_updater()
  while true do
    clock.sleep(1/32)
    lfo_tim = lfo_tim + 1
    if lfo_tim >= 32 then lfo_tim = 0 end
    local current_lfo_val = lfo_val
    lfo_val = math.sin(lfo_tim)
    if math.abs(lfo_val * 120 - current_lfo_val * 120) > 1 then play(note) end
    print(lfo_val)
  end
end

function play(note)
  note = math.random(48,60)
  note = music.snap_note_to_array(note,scale)
  local playnote = note + math.floor(lfo_val * 12)
  m:note_on(playnote,100,params:get("midi_channel"))
end

function key(k, z)
  if k == 2 or k == 3 then
    if z == 1 then
      play(note)
    elseif z == 0 then      
      clock.run(midi_hang,note,params:get("midi_channel"))
    end
  end
end

function midi_hang(note, channel)
  clock.sleep(params:get("gate_length")/100)
  m:note_off(note,0,channel)
end

function rerun()
  norns.script.load(norns.state.script)
end