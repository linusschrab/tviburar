local lattice = require("lattice")
local music = require("musicutil")
--local MollyThePoly = require "molly_the_poly/lib/molly_the_poly_engine"
--engine.name = "MollyThePoly"
thebangs = include('thebangs/lib/thebangs_engine')
local Thebangs = require "thebangs/lib/thebangs_engine"
engine.name = "Thebangs"

local m = midi.connect(1)
 
local lat = lattice:new()
local LFO_SHAPES = {"mute", "square", "random", "triangle", "sine"}
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
  names = {"4x", "3x", "2x", "1x", "1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32"},
  options = {4, 3, 2, 1, 1/2, 1/3, 1/4, 1/6, 1/8, 1/12, 1/16, 1/24, 1/3}
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

  --params:add_group("molly the poly", 46)
  --MollyThePoly.add_params()

  params:add_option("twin1out", "twin 1 output", {"mute", "engine", "midi", "crow 1/2"}, 3)
  params:add_option("twin2out", "twin 2 output", {"mute", "engine", "midi", "crow 3/4"}, 3)
  params:add_number("mididevice","midi device",1,#midi.vports,1)
  params:set_action("mididevice", function (x)
    m = midi.connect(x)
  end)
  params:add_number("midi_ch_1","midi ch twin 1",1,#midi.vports,1)
  params:add_number("midi_ch_2","midi ch twin 2",1,#midi.vports,1)
  

  params:add_option("scale","scale",SCALES,5) --dorian
  params:set_action("scale", function (x) 
    scale = music.generate_scale(params:get("root_note")-1, x, 10) 
  end)
  params:add_option("root_note", "root note", music.note_nums_to_names({0,1,2,3,4,5,6,7,8,9,10,11}),1)
  for i=1,2 do
    --params:add_option("twin"..i.."div", "twin "..i.." division", div.names, 7)
    params:add_number("twin"..i.."div", "twin "..i.." timing 1/x", 1,48,4)
    params:set_action("twin"..i.."div", function(x)
      --twin[i]:set_division(div.options[x])
      twin[i]:set_division(1/x)
    end)
  end
  for i=1,2 do
    for j=1,4 do
      params:add_option("twin"..i.."lfo"..j.."shape", "twin "..i.." lfo "..j.." shape",LFO_SHAPES,2)
    end
  end
  for i=1,2 do
    for j=1,4 do
      params:add_control("twin"..i.."lfo"..j.."rate", "twin "..i.." lfo "..j.." rate", controlspec.new(0.01,50,"exp",0.001,math.random(1, 30)/10,"hz",1/1000))
    end
  end
  for i=1,2 do
    for j=1,4 do
      params:add_number("twin"..i.."lfo"..j.."off","twin "..i.." lfo offset "..j,-12,12,0)
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
      --do nothing
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 2 then
      if lfo_counter[i][twinstep[i]] >= LFO_RES / (2*params:get("twin"..i.."lfo"..twinstep[i].."rate")) then
        twin_lfo_value[i][twinstep[i]] = twin_lfo_value[i][twinstep[i]] * -1
        
        play_lfo(math.floor(
            
              12 * (twin_lfo_value[i][twinstep[i]]
              * params:get("twin"..i.."lfo"..twinstep[i].."amp"))
              + params:get("twin"..i.."lfo"..twinstep[i].."off")
          ), i
        )
        lfo_counter[i][twinstep[i]] = 0
      end
    
    --random
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 3 then

      if lfo_counter[i][twinstep[i]]>= LFO_RES / (2*params:get("twin"..i.."lfo"..twinstep[i].."rate")) then
        twin_lfo_value[i][twinstep[i]] = math.random(120)/120
        old_note[i][1] = note[i][1]
        note[i][1] = math.floor(
            
          12 * (twin_lfo_value[i][twinstep[i]]
          * params:get("twin"..i.."lfo"..twinstep[i].."amp"))
          + params:get("twin"..i.."lfo"..twinstep[i].."off")
        )
        if math.abs(note[i][1] - old_note[i][1]) >= 1 then play_lfo((note[i][1]), i) end
        lfo_counter[i][twinstep[i]]= 0
      end

    --triangle
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 4 then
      local tempres = LFO_RES / params:get("twin"..i.."lfo"..twinstep[i].."rate")
      if lfo_counter[i][twinstep[i]]<= tempres then
        twin_lfo_value[i][twinstep[i]] = 1 - 2 * lfo_counter[i][twinstep[i]]/(tempres)
      elseif lfo_counter[i][twinstep[i]] <= 2*tempres then
        twin_lfo_value[i][twinstep[i]] = 2 * lfo_counter[i][twinstep[i]]/(tempres) - 3
      else
        lfo_counter[i][twinstep[i]]= 0
      end

      old_note[i][2] = note[i][2]
      
      note[i][2] = math.floor(
            
        12 * (twin_lfo_value[i][twinstep[i]]
        * params:get("twin"..i.."lfo"..twinstep[i].."amp"))
        + params:get("twin"..i.."lfo"..twinstep[i].."off")
      )
      
      if math.abs(note[i][2] - old_note[i][2]) >= 1 then 
        play_lfo((note[i][2]), i) end
      
    --sine
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 5 then
      twin_lfo_value[i][twinstep[i]] = params:get("twin"..i.."lfo"..twinstep[i].."amp") * math.sin((2*params:get("twin"..i.."lfo"..twinstep[i].."rate")*lfo_counter[i][twinstep[i]])/(LFO_RES))
      old_note[i][3] = note[i][3]
      note[i][3] = math.floor(
            
        12 * (twin_lfo_value[i][twinstep[i]]
        * params:get("twin"..i.."lfo"..twinstep[i].."amp"))
        + params:get("twin"..i.."lfo"..twinstep[i].."off")
      )
      if math.abs(old_note[i][3] - note[i][3]) >= 1 then play_lfo((note[i][3]), i) end
      if lfo_counter[i][twinstep[i]] >= 2*LFO_RES then lfo_counter[i][twinstep[i]] = 0 end
      
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
  screen.move(64, 10)
  screen.level(8)
  screen.text_center("t v i b u r a r")
  for y=1,2 do
    for x=1,4 do
      screen.rect(34+x*10,22+(y-1)*10,8,8)
      if twinstep[y] == x then screen.level(15) else screen.level(5) end
      screen.fill()
    end
  end
  screen.update()
end
 
function play_lfo(note, i)
  note = music.snap_note_to_array(60 + note,scale)
  if params:get("twin"..i.."out") == 2 then
    engine.hz(music.note_num_to_freq(note))
    --engine.noteOn(note, music.note_num_to_freq(note),100)
    --clock.run(eng_hang, note,i)
  elseif params:get("twin"..i.."out") == 3 then
    m:note_off(note,100,params:get("midi_ch_"..i)) --send midi to ch 1 or 2
    m:note_on(note,100,params:get("midi_ch_"..i))
    clock.run(midihang, note, ch)
  elseif params:get("twin"..i.."out") == 4 then
    crow.output[(i-1)*2 + 1].volts = (((note)-60)/12)
    crow.output[(i-1)*2 + 2].execute()
  end
end

function midihang(note, ch)
  clock.sleep(0.01)
  m:note_off(note,100,ch)
end

function eng_hang(note,i)
  clock.sleep(0.01)
  engine.noteOff(note)
end                               
 
function rerun()
  norns.script.load(norns.state.script)
end