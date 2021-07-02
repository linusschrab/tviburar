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
local SEQ_OPTIONS = {"->", "<-", ">-<", "~"}
local ALT_KEY = false
local pend_dir = {1, 1}
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

local LFO_RES = 500
local lfo_counter = {
  {0,0,0,0},
  {0,0,0,0}
}
 
local div = {
  names = {"4x", "3x", "2x", "1x", "1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32"},
  options = {4, 3, 2, 1, 1/2, 1/3, 1/4, 1/6, 1/8, 1/12, 1/16, 1/24, 1/3}
}
 
local screen_dirty = false

local sel_lfo = 0
 
function init()
  crow.send("ii.wsyn.ar_mode(1)")
  init_params()
  wsyn_add_params()
  crow.output[2].action = "{to(".. 8 ..",0),to(0,".. 0.001 .. ")}"
  crow.output[4].action = "{to(".. 8 ..",0),to(0,".. 0.001 .. ")}"
 
  for i=1,2 do
    twin[i] = lat:new_pattern{
      action = function (x)
        if params:get("twin"..i.."direction") == 1 then --forward
          twinstep[i] = util.wrap(twinstep[i] + 1,1,4) -- util.wrap does the same as compare + increment, which is rad!
        elseif params:get("twin"..i.."direction") == 2 then --backwards
          twinstep[i] = util.wrap(twinstep[i] - 1,1,4)
        elseif params:get("twin"..i.."direction") == 3 then --pendulum
          if (twinstep[i] == 4 and pend_dir[i] == 1) or (twinstep[i] == 1 and pend_dir[i] == -1) then
            pend_dir[i] = pend_dir[i] * -1
          end
          twinstep[i] = util.wrap(twinstep[i] + pend_dir[i],1,4)
        elseif params:get("twin"..i.."direction") == 4 then --random
          twinstep[i] = math.random(1,4)
        end
        --lfo_counter[i][twinstep[i]] = 0
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

  params:add_option("twin1out", "twin 1 output", {"mute", "engine", "midi", "crow 1/2", "w/syn"}, 3)
  params:set_action("twin1out", function(x)
    for i=0,127 do
      m:note_off(i,100,params:get("midi_ch_1"))
    end
  end)
  params:add_option("twin2out", "twin 2 output", {"mute", "engine", "midi", "crow 3/4", "w/syn"}, 3)
  params:set_action("twin2out", function(x)
    for i=0,127 do
      m:note_off(i,100,params:get("midi_ch_2"))
    end
  end)
  params:add_number("mididevice","midi device",1,#midi.vports,1)
  params:set_action("mididevice", function (x)
    m = midi.connect(x)
  end)
  params:add_number("midi_ch_1","midi ch twin 1",1,#midi.vports,1)
  params:add_number("midi_ch_2","midi ch twin 2",1,#midi.vports,2)
  
  params:add_number("note_lim_low","lower note limit", 0, 127,0)
  params:set_action("note_lim_low", function (x)
    if x >= params:get("note_lim_high") then
      params:set("note_lim_low", params:get("note_lim_high"))
    end
  end)
  params:add_number("note_lim_high","upper note limit", 0,127,127)
  params:set_action("note_lim_high", function (x)
    if x <= params:get("note_lim_low") then
      params:set("note_lim_high", params:get("note_lim_low"))
    end
  end)
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
    params:add_option("twin"..i.."direction", "twin "..i.." direction", SEQ_OPTIONS, 1)
  end
  for i=1,2 do
    params:add_control("influence_"..i.."_"..util.wrap(i+1,1,2), "twinfluence "..i.." <- "..util.wrap(i+1,1,2), controlspec.new(0,1,"lin",0.001,0,"/ 1.0",1/100))
    params:add_group("twin lfo "..i.." tweaks",16)
    for j=1,4 do
      params:add_option("twin"..i.."lfo"..j.."shape", "twin "..i.." lfo "..j.." shape",LFO_SHAPES,2)
      params:add_control("twin"..i.."lfo"..j.."rate", "twin "..i.." lfo "..j.." rate", controlspec.new(0.01,25,"exp",0.001,math.random(1, 30)/10,"hz",1/1000))
      params:add_number("twin"..i.."lfo"..j.."off","twin "..i.." lfo offset "..j,-12,12,0)
      params:add_control("twin"..i.."lfo"..j.."amp","twin "..i.." lfo amp "..j,controlspec.new(0,5,"lin",0.01,1,"",1/100))
    end
  end
end

function wsyn_add_params()
  params:add_group("w/syn",12)
  params:add {
    type = "option",
    id = "wsyn_ar_mode",
    name = "AR mode",
    options = {"off", "on"},
    default = 2,
    action = function(val) 
      crow.send("ii.wsyn.ar_mode(".. (val-1) ..")")
    end
  }
  params:add {
    type = "control",
    id = "wsyn_vel",
    name = "Velocity",
    controlspec = controlspec.new(0, 5, "lin", 0, 2.5, "v"),
    action = function(val) 
      pset_wsyn_vel = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_curve",
    name = "Curve",
    controlspec = controlspec.new(-5, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.curve(" .. val .. ")") 
      pset_wsyn_curve = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_ramp",
    name = "Ramp",
    controlspec = controlspec.new(-5, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.ramp(" .. val .. ")") 
      pset_wsyn_ramp = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_fm_index",
    name = "FM index",
    controlspec = controlspec.new(0, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.fm_index(" .. val .. ")") 
      pset_wsyn_fm_index = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_fm_env",
    name = "FM env",
    controlspec = controlspec.new(-5, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.fm_env(" .. val .. ")") 
      pset_wsyn_fm_env = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_fm_ratio_num",
    name = "FM ratio numerator",
    controlspec = controlspec.new(1, 20, "lin", 1, 2),
    action = function(val) 
      crow.send("ii.wsyn.fm_ratio(" .. val .. "," .. params:get("wsyn_fm_ratio_den") .. ")") 
      pset_wsyn_fm_ratio_num = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_fm_ratio_den",
    name = "FM ratio denominator",
    controlspec = controlspec.new(1, 20, "lin", 1, 1),
    action = function(val) 
      crow.send("ii.wsyn.fm_ratio(" .. params:get("wsyn_fm_ratio_num") .. "," .. val .. ")") 
      pset_wsyn_fm_ratio_den = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_lpg_time",
    name = "LPG time",
    controlspec = controlspec.new(-5, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.lpg_time(" .. val .. ")") 
      pset_wsyn_lpg_time = val
    end
  }
  params:add {
    type = "control",
    id = "wsyn_lpg_symmetry",
    name = "LPG symmetry",
    controlspec = controlspec.new(-5, 5, "lin", 0, 0, "v"),
    action = function(val) 
      crow.send("ii.wsyn.lpg_symmetry(" .. val .. ")") 
      pset_wsyn_lpg_symmetry = val
    end
  }
  params:add{
    type = "trigger",
    id = "wsyn_pluckylog",
    name = "Pluckylogger >>>",
    action = function()
      params:set("wsyn_curve", math.random(-40, 40)/10)
      params:set("wsyn_ramp", math.random(-5, 5)/10)
      params:set("wsyn_fm_index", math.random(-50, 50)/10)
      params:set("wsyn_fm_env", math.random(-50, 40)/10)
      params:set("wsyn_fm_ratio_num", math.random(1, 4))
      params:set("wsyn_fm_ratio_den", math.random(1, 4))
      params:set("wsyn_lpg_time", math.random(-28, -5)/10)
      params:set("wsyn_lpg_symmetry", math.random(-50, -30)/10)
    end
  }
  params:add{
    type = "trigger",
    id = "wsyn_randomize",
    name = "Randomize",
    allow_pmap = false,
    action = function()
      params:set("wsyn_curve", math.random(-50, 50)/10)
      params:set("wsyn_ramp", math.random(-50, 50)/10)
      params:set("wsyn_fm_index", math.random(0, 50)/10)
      params:set("wsyn_fm_env", math.random(-50, 50)/10)
      params:set("wsyn_fm_ratio_num", math.random(1, 20))
      params:set("wsyn_fm_ratio_den", math.random(1, 20))
      params:set("wsyn_lpg_time", math.random(-50, 50)/10)
      params:set("wsyn_lpg_symmetry", math.random(-50, 50)/10)
    end
  }
  params:add{
    type = "trigger",
    id = "wsyn_init",
    name = "Init",
    action = function()
      params:set("wsyn_curve", pset_wsyn_curve)
      params:set("wsyn_ramp", pset_wsyn_ramp)
      params:set("wsyn_fm_index", pset_wsyn_fm_index)
      params:set("wsyn_fm_env", pset_wsyn_fm_env)
      params:set("wsyn_fm_ratio_num", pset_wsyn_fm_ratio_num)
      params:set("wsyn_fm_ratio_den", pset_wsyn_fm_ratio_den)
      params:set("wsyn_lpg_time", pset_wsyn_lpg_time)
      params:set("wsyn_lpg_symmetry", pset_wsyn_lpg_symmetry)
    end
  }
  params:hide("wsyn_init")
end

function key(k, z)
  if k == 1 and z == 1 then
    ALT_KEY = true
  elseif k == 1 and z == 0 then
    ALT_KEY = false
  end
end

function enc(n, d)
  if n == 1 then
    sel_lfo = util.wrap(sel_lfo + d, 1, 8)
    screen_dirty = true
  end
end

function count_and_act()
  --for i=1,2 do
  --  for j=1,4 do
  --    lfo_counter[i][j] = lfo_counter[i][j] + 1
  --  end
  --end
  for i=1,2 do
    lfo_counter[i][twinstep[i]] = lfo_counter[i][twinstep[i]] + 1
    --square
    if params:get("twin"..i.."lfo"..twinstep[i].."shape") == 1 then
      twin_lfo_value[i][twinstep[i]] = 0
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 2 then
      if lfo_counter[i][twinstep[i]] >= LFO_RES / (2*params:get("twin"..i.."lfo"..twinstep[i].."rate")) then
        twin_lfo_value[i][twinstep[i]] = twin_lfo_value[i][twinstep[i]] * -1
        
        play_lfo(math.floor(
            
              12 * (twin_lfo_value[i][twinstep[i]]
              * params:get("twin"..i.."lfo"..twinstep[i].."amp"))
              * (1 + (params:get("influence_"..i.."_"..util.wrap(i+1,1,2)) * twin_lfo_value[util.wrap(i+1,1,2)][twinstep[util.wrap(i+1,1,2)]] * params:get("twin"..util.wrap(i+1,1,2).."lfo"..twinstep[util.wrap(i+1,1,2)].."amp")))
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
          * (1 + (params:get("influence_"..i.."_"..util.wrap(i+1,1,2)) * twin_lfo_value[util.wrap(i+1,1,2)][twinstep[util.wrap(i+1,1,2)]] * params:get("twin"..util.wrap(i+1,1,2).."lfo"..twinstep[util.wrap(i+1,1,2)].."amp")))
          + params:get("twin"..i.."lfo"..twinstep[i].."off")
        )
        if math.abs(note[i][1] - old_note[i][1]) >= 1 or params:get("twin"..i.."lfo"..twinstep[i].."amp") == 0 then 
          play_lfo((note[i][1]), i) 
        end
        lfo_counter[i][twinstep[i]]= 0
      end

    --triangle
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 4 then
      local tempres = LFO_RES / params:get("twin"..i.."lfo"..twinstep[i].."rate")
      if params:get("twin"..i.."lfo"..twinstep[i].."amp") == 0 then
        if lfo_counter[i][twinstep[i]] >= tempres then
          lfo_counter[i][twinstep[i]]= 0
          play_lfo(old_note[i][2] + params:get("twin"..i.."lfo"..twinstep[i].."off"),i)
        end
      else
        if lfo_counter[i][twinstep[i]]<= tempres/2 then
          twin_lfo_value[i][twinstep[i]] = 1 - 2 * lfo_counter[i][twinstep[i]]/(tempres)
        elseif lfo_counter[i][twinstep[i]] <= tempres then
          twin_lfo_value[i][twinstep[i]] = 2 * lfo_counter[i][twinstep[i]]/(tempres) - 3
        else
          lfo_counter[i][twinstep[i]]= 0
        end
        old_note[i][2] = note[i][2]
      
        note[i][2] = math.floor(    
        12 * (twin_lfo_value[i][twinstep[i]]
        * params:get("twin"..i.."lfo"..twinstep[i].."amp"))
        * (1 + (params:get("influence_"..i.."_"..util.wrap(i+1,1,2)) * twin_lfo_value[util.wrap(i+1,1,2)][twinstep[util.wrap(i+1,1,2)]] * params:get("twin"..util.wrap(i+1,1,2).."lfo"..twinstep[util.wrap(i+1,1,2)].."amp")))
        + params:get("twin"..i.."lfo"..twinstep[i].."off")
        )
      
        if math.abs(note[i][2] - old_note[i][2]) >= 1 then 
          play_lfo((note[i][2]), i) end
      end
      
      
    --sine
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 5 then
      if params:get("twin"..i.."lfo"..twinstep[i].."amp") == 0 then
        if lfo_counter[i][twinstep[i]] >= LFO_RES / params:get("twin"..i.."lfo"..twinstep[i].."rate") then
          lfo_counter[i][twinstep[i]]= 0
          play_lfo(old_note[i][2] + params:get("twin"..i.."lfo"..twinstep[i].."off"),i)
        end
      else
        twin_lfo_value[i][twinstep[i]] = params:get("twin"..i.."lfo"..twinstep[i].."amp") * math.sin((2*params:get("twin"..i.."lfo"..twinstep[i].."rate")*lfo_counter[i][twinstep[i]])/(LFO_RES))
        old_note[i][3] = note[i][3]
        note[i][3] = math.floor(
              
          12 * (twin_lfo_value[i][twinstep[i]]
          * params:get("twin"..i.."lfo"..twinstep[i].."amp"))
          * (1 + (params:get("influence_"..i.."_"..util.wrap(i+1,1,2)) * twin_lfo_value[util.wrap(i+1,1,2)][twinstep[util.wrap(i+1,1,2)]] * params:get("twin"..util.wrap(i+1,1,2).."lfo"..twinstep[util.wrap(i+1,1,2)].."amp")))
          + params:get("twin"..i.."lfo"..twinstep[i].."off")
        )
        if math.abs(old_note[i][3] - note[i][3]) >= 1 or params:get("twin"..i.."lfo"..twinstep[i].."amp") == 0 then 
          play_lfo((note[i][3]), i) 
        end
        if lfo_counter[i][twinstep[i]] >= 2*LFO_RES then lfo_counter[i][twinstep[i]] = 0 end
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
  screen.move(64, 10)
  screen.level(8)
  screen.text_center("t v i b u r a r")
  for y=1,2 do
    for x=1,4 do
      screen.rect(2+x*10,25+(y-1)*10,8,8)
      if twinstep[y] == x then screen.level(15) else screen.level(5) end
      screen.fill()
    end
  end

  if ALT_KEY then
    screen.level(8)
    screen.move(126, 30)
    screen.text_right("timing: 1/4")
    screen.level(15)
    screen.move(126, 40)
    screen.level(8)
    screen.text_right("direction: ->")
    screen.move(126, 50)
    screen.text_right("offset: 7 st")
    screen.move(126, 60)
    screen.text_right("amp: 1.7")
  else
    screen.level(8)
    screen.move(126, 30)
    screen.text_right("shape: square")
    screen.level(15)
    screen.move(126, 40)
    screen.level(8)
    screen.text_right("rate: 2.5 hz")
    screen.move(126, 50)
    screen.text_right("offset: 7 st")
    screen.move(126, 60)
    screen.text_right("amp: 1.7")
  end

  screen.update()
end
 
function play_lfo(note, i)
  note = util.wrap(60 + note, params:get("note_lim_low"), params:get("note_lim_high"))
  note = music.snap_note_to_array(note, scale)
  if params:get("twin"..i.."out") == 2 then
    engine.hz(music.note_num_to_freq(note))
    --engine.noteOn(note, music.note_num_to_freq(note),100)
    --clock.run(eng_hang, note,i)
  elseif params:get("twin"..i.."out") == 3 then
    m:note_off(note,100,params:get("midi_ch_"..i)) --send midi to ch 1 or 2
    m:note_on(note,100,params:get("midi_ch_"..i))
    --m:note_off(note,100,ch)
    clock.run(midihang, note, ch, i)
  elseif params:get("twin"..i.."out") == 4 then
    crow.output[(i-1)*2 + 1].volts = (((note)-60)/12)
    crow.output[(i-1)*2 + 2]()
  elseif params:get("twin"..i.."out") == 5 then
    crow.send("ii.wsyn.play_note(".. ((note)-60)/12 ..", " .. params:get("wsyn_vel") .. ")")
  end
end

function midihang(note, ch, i)
  clock.sleep(1 / (2 * params:get("twin"..i.."lfo"..twinstep[i].."rate")))
  m:note_off(note,100,ch)
end

function eng_hang(note,i)
  clock.sleep(0.001)
  engine.noteOff(note)
end                               
 
function rerun()
  norns.script.load(norns.state.script)
end