local lattice = require("lattice")
local music = require("musicutil")

local m = midi.connect(1)
 
local lat = lattice:new()
local LFO_SHAPES = {"square", "sine", "triangle", "random"}
local SCALES = {}
for i = 1, #music.SCALES do
  table.insert(SCALES, string.lower(music.SCALES[i].name))
end
local scale = {}
local twin = {}
local twinstep = {1,1}
local note = {
  {0,0,0},
  {0,0,0},
}
local old_note = {
  {0,0,0},
  {0,0,0}
}

local twin_lfo_value = {
  {1,1,1,1},
  {1,1,1,1}
}

local LFO_RES = 1000
local lfo_counter = {
  {0,0,0,0},
  {0,0,0,0}
}
 
local div = {
  names = {"2x", "1x", "1/2", "1/4", "1/8", "1/16", "1/32"},
  options = {2,1,1/2,1/4,1/8,1/16,1/32}
}
 
local screen_dirty = false
 
function init()
  init_params()

  crow.output[2].action = "{to(".. 8 ..",0),to(0,".. 0.001 .. ")}"
  crow.output[4].action = "{to(".. 8 ..",0),to(0,".. 0.001 .. ")}"
 
  for i=1,2 do
    twin[i] = lat:new_pattern{
      action = function (x)
        twinstep[i] = util.wrap(twinstep[i] + 1,1,4) -- util.wrap does the same as compare + increment, which is rad!
        screen_dirty = true
      end,
      division = 1/4
    }
  end
 
  scale = music.generate_scale(params:get("root_note")-1, x, 10) 

  local main_metro = metro.init(count_and_act, 1/LFO_RES):start()
  lat:start()
  clock.run(redraw_clock)
end
 
function init_params()

  params:add_option("twinout", "twinoutput", {"midi", "crow "})

  params:add_option("scale","scale",SCALES,1)
  params:set_action("scale", function (x) 
    scale = music.generate_scale(params:get("root_note")-1, x, 10) 
  end)
  params:add_option("root_note", "root note", music.note_nums_to_names({0,1,2,3,4,5,6,7,8,9,10,11}),1)
  for i=1,2 do
    params:add_option("twin"..i.."div", "twin "..i.." division", div.names, 4)
    params:set_action("twin"..i.."div", function(x)
      twin[i]:set_division(div.options[x])
    end)
  end
  for i=1,2 do
    for j=1,4 do
      params:add_option("twin"..i.."lfo"..j.."shape", "twin "..i.." lfo "..j.." shape",LFO_SHAPES,4)
    end
  end
  for i=1,2 do
    for j=1,4 do
      params:add_control("twin"..i.."lfo"..j.."rate", "twin "..i.." lfo "..j.." rate", controlspec.new(0.1,50,"lin",0.001,math.random(1, 30)/10,"hz",1/10000))
    end
  end
  for i=1,2 do
    for j=1,4 do
      params:add_number("twin"..i.."lfo"..j.."off","twin "..i.." lfo offset "..j,-3,3,0)
    end
  end
  for i=1,2 do
    for j=1,4 do
      params:add_control("twin"..i.."lfo"..j.."amp","twin "..i.." lfo amp "..j,controlspec.new(0,5,"lin",0.01,1,"",1/100))
    end
  end
end

function count_and_act()
  for i=1,2 do
    for j=1,4 do
      lfo_counter[i][j] = lfo_counter[i][j] + 1
    end
  end
  for i=1,2 do
    --square
    if params:get("twin"..i.."lfo"..twinstep[i].."shape") == 1 then
      if lfo_counter[i][twinstep[i]] >= LFO_RES / (2*params:get("twin"..i.."lfo"..twinstep[i].."rate")) then
        twin_lfo_value[i][twinstep[i]] = twin_lfo_value[i][twinstep[i]] * -1
        play_lfo(math.floor(twin_lfo_value[i][twinstep[i]] + params:get("twin"..i.."lfo"..twinstep[i].."amp")) * 12 + 12*params:get("twin"..i.."lfo"..twinstep[i].."off"), i)
        lfo_counter[i][twinstep[i]] = 0
      end

    --sine
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 2 then
      twin_lfo_value[i][twinstep[i]] = params:get("twin"..i.."lfo"..twinstep[i].."amp") * math.sin((2*params:get("twin"..i.."lfo"..twinstep[i].."rate")*lfo_counter[i][twinstep[i]])/(LFO_RES))
      old_note[i][1] = note[i][1]
      note[i][1] = math.floor(12 * twin_lfo_value[i][twinstep[i]])
      if math.abs(old_note[i][1] - note[i][1]) >= 1 then play_lfo(note[i][1] + 12*params:get("twin"..i.."lfo"..twinstep[i].."off"), i) end
      if lfo_counter[i][twinstep[i]] >= 2*LFO_RES then lfo_counter[i][twinstep[i]] = 0 end

    --triangle
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 3 then
      local tempres = LFO_RES / params:get("twin"..i.."lfo"..twinstep[i].."rate")
      if lfo_counter[i][twinstep[i]]<= tempres then
        twin_lfo_value[i][twinstep[i]] = 1 - 2 * lfo_counter[i][twinstep[i]]/(tempres)
      elseif lfo_counter[i][twinstep[i]] <= 2*tempres then
        twin_lfo_value[i][twinstep[i]] = 2 * lfo_counter[i][twinstep[i]]/(tempres) - 3
      else
        lfo_counter[i][twinstep[i]]= 0
      end

      old_note[i][2] = note[i][2]
      
      note[i][2] = math.floor(params:get("twin"..i.."lfo"..twinstep[i].."amp") * 12 * twin_lfo_value[i][twinstep[i]]) 
      if math.abs(note[i][2] - old_note[i][2]) >= 1 then play_lfo(note[i][2] + 12*params:get("twin"..i.."lfo"..twinstep[i].."off"), i) end
      
    --random
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 4 then

      if lfo_counter[i][twinstep[i]]>= LFO_RES / (2*params:get("twin"..i.."lfo"..twinstep[i].."rate")) then
        twin_lfo_value[i][twinstep[i]] = math.random(120)/120
        old_note[i][3] = note[i][3]
        note[i][3] = math.floor(12 * twin_lfo_value[i][twinstep[i]] + params:get("twin"..i.."lfo"..twinstep[i].."amp") * 12)
        if math.abs(note[i][3] - old_note[i][3]) >= 1 then play_lfo(note[i][3] + 12*params:get("twin"..i.."lfo"..twinstep[i].."off"), i) end
        lfo_counter[i][twinstep[i]]= 0
      end
    end
  end
end
 
function redraw_clock()
  while true do
    clock.sleep(1/30)
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
  end
end
 
function redraw()
  screen.clear()
  for i=1,2 do
    screen.move(0,10*i)
    screen.text(twinstep[i])
  end
  screen.update()
end
 
function play_lfo(note, i)
  note = music.snap_note_to_array(60 + note,scale)
  if params:get("twinout") == 1 then
    m:note_off(note,100,i) --send midi to ch 1 or 2
    m:note_on(note,100,i)
    clock.run(midihang, note)
  elseif params:get("twinout") == 2 then
    crow.output[(i-1)*2 + 1].volts = (((note)-60)/12)
    crow.output[(i-1)*2 + 2].execute()
  end
end

function midihang(note)
  clock.sleep(0.01)
  m:note_off(note,100,1)
end
 
function rerun()
  norns.script.load(norns.state.script)
end