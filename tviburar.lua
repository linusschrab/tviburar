local lattice = require("lattice")
local music = require("musicutil")
local polysub = include 'we/lib/polysub'
engine.name = "PolySub"

local m = midi.connect(1)
 
local lat = lattice:new()
local LFO_SHAPES = {"mute", "square", "random", "triangle", "ramp up", "ramp down", "sine"}
local SEQ_OPTIONS = {"->", "<-", ">-<", "~"}
local SCREEN_EDITS = {"shape", "rate", "off", "amp"}
local sel_screen_edit = 1
local ALT_SCREEN_EDITS = {"timing", "direction", "twinfluence"}
local sel_alt_screen_edit = 1
local ALT_KEY = false
local pend_dir = {1, 1}
local SCALES = {}
for i = 1, #music.SCALES do
  table.insert(SCALES, string.lower(music.SCALES[i].name))
end
local time = {
  names = {},
  modes = {}
}
for i=1,3 do
  time["names"][i] = "/"..(5-i)
  time["modes"][i] = 5-i
end
for i=1,16 do
  time["names"][i+3] = "x"..i
  time["modes"][i+3] = 1/i
end
local scale = {}
local twin = {}
local twinstep = {1,1}
local note = {
  {0,0,0,0},
  {0,0,0,0},
}
local old_note = {
  {0,0,0,0},
  {0,0,0,0}
}

local twin_lfo_value = {
  {1,1,1,1},
  {1,1,1,1}
}

local LFO_RES = 100
local lfo_counter = {
  {0,0,0,0},
  {0,0,0,0}
}
 
local div = {
  names = {"4x", "3x", "2x", "1x", "1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32"},
  options = {4, 3, 2, 1, 1/2, 1/3, 1/4, 1/6, 1/8, 1/12, 1/16, 1/24, 1/3}
}
 
local screen_dirty = false

local sel_lfo = 1
local sel_lane = 1
 
function init()
  for i=1,3 do
    --norns.encoders.set_accel(i,false)
    norns.encoders.set_sens(i,8)
  end
  crow.send("ii.wsyn.ar_mode(1)")
  init_params()
  params:add_group("polysub", 19)
  polysub.params()
  wsyn_add_params()
  
  crow.output[2].action = "{to(".. 8 ..",0),to(0,".. 0.001 .. ")}"
  crow.output[4].action = "{to(".. 8 ..",0),to(0,".. 0.001 .. ")}"
 
  for i=1,2 do
    twin[i] = lat:new_pattern{
      action = function (x)
        if params:get("twin"..i.."direction") == 1 then --forward
          twinstep[i] = util.wrap(twinstep[i] + 1,1,4)
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
        screen_dirty = true
      end,
      division = time.modes[params:get("twin"..i.."div")]
    }
  end
 
  scale = music.generate_scale(params:get("root_note")-1, x, 10) 
  local main_metro = metro.init(count_and_act, 1/LFO_RES)
  main_metro:start()
  screen_clock = clock.run(redraw_clock)
  lat:start()
  params:bang()
end
 
function init_params()
  params:add_group("midi & outputs", 5)
  params:add_option("twin1out", "twin 1 output", {"mute", "polysub", "midi", "crow 1/2", "w/syn", "jf"}, 2)
  params:set_action("twin1out", function(x)
    for i=0,127 do
      m:note_off(i,100,params:get("midi_ch_1"))
    end
    if x == 6 then crow.ii.jf.mode(1) else crow.ii.jf.mode(0) end
  end)
  params:add_option("twin2out", "twin 2 output", {"mute", "polysub", "midi", "crow 3/4", "w/syn", "jf"}, 1)
  params:set_action("twin2out", function(x)
    for i=0,127 do
      m:note_off(i,100,params:get("midi_ch_2"))
    end
    if x == 6 then crow.ii.jf.mode(1) else crow.ii.jf.mode(0) end
  end)
  params:add_number("mididevice","midi device",1,#midi.vports,1)
  params:set_action("mididevice", function (x)
    m = midi.connect(x)
  end)
  params:add_number("midi_ch_1","midi ch twin 1",1,#midi.vports,1)
  params:add_number("midi_ch_2","midi ch twin 2",1,#midi.vports,2)
  
  params:add_group("scale and note options", 6)
  params:add_option("scale","scale",SCALES,5) --dorian
  params:set_action("scale", function (x) 
    scale = music.generate_scale(params:get("root_note")-1, x, 10) 
  end)
  params:add_option("root_note", "root note", music.note_nums_to_names({0,1,2,3,4,5,6,7,8,9,10,11}),1)
  for i=1,2 do
    params:add_number("note_lim_low_"..i,"twin "..i.." lower note limit", 0, 127,0)
    params:set_action("note_lim_low_"..i, function (x)
      if x >= params:get("note_lim_high_"..i) then
        params:set("note_lim_low_"..i, params:get("note_lim_high_"..i))
      end
    end)
    params:add_number("note_lim_high_"..i,"twin "..i.." upper note limit", 0,127,127)
    params:set_action("note_lim_high_"..i, function (x)
      if x <= params:get("note_lim_low_"..i) then
        params:set("note_lim_high_"..i, params:get("note_lim_low_"..i))
      end
    end)
  end
  
  params:add_group("sequencer options", 6)
  for i=1,2 do
    params:add_option("twin"..i.."div", "twin "..i.." speed", time.names,4)
    params:set_action("twin"..i.."div", function(x)
      twin[i]:set_division(time.modes[x])
    end)
    params:add_option("twin"..i.."direction", "twin "..i.." direction", SEQ_OPTIONS, 1)
    params:add_control("twinfluence"..i, "twinfluence "..i.." <- "..util.wrap(i+1,1,2), controlspec.new(0,1,"lin",0.001,0,"/ 1.0",1/100))
  end
  for i=1,2 do
  end
  for i=1,2 do
    params:add_group("twin lfo "..i.." tweaks",16)
    for j=1,4 do
      params:add_option("twin"..i.."lfo"..j.."shape", "twin "..i.." lfo "..j.." shape",LFO_SHAPES,2)
      params:add_control("twin"..i.."lfo"..j.."rate", "twin "..i.." lfo "..j.." rate", controlspec.new(0.01,10,"exp",0.001,math.random(33,66)/100,"hz",1/1000))
      params:add_number("twin"..i.."lfo"..j.."off","twin "..i.." lfo "..j.." offset",-12,12,0)
      params:add_control("twin"..i.."lfo"..j.."amp","twin "..i.." lfo "..j.." amp",controlspec.new(0,5,"lin",0.01,1,"",1/100))
    end
  end
end

function wsyn_add_params()
  params:add_group("w/syn",11)
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
end

function key(k, z)
  if (k == 1 or k == 2 or k == 3) and z == 1 then
    ALT_KEY = true
  elseif (k == 1 or k == 2 or k == 3) and z == 0 then
    ALT_KEY = false
  end
  screen_dirty = true
end

function enc(n, d)
  if n == 1 then
    if ALT_KEY then
      sel_lane = util.clamp(sel_lane + d, 1, 2)
    else
      sel_lfo = util.clamp(sel_lfo + d, 1, 4)
    end
    screen_dirty = true
  end
  if n == 2 then
    if ALT_KEY then
      sel_alt_screen_edit = util.clamp(sel_alt_screen_edit + d, 1, #ALT_SCREEN_EDITS)
    else
      sel_screen_edit = util.clamp(sel_screen_edit + d, 1, #SCREEN_EDITS)
    end
    screen_dirty = true
  end
  if n == 3 then
    if ALT_KEY then
      if sel_alt_screen_edit == 1 then
        params:set("twin"..sel_lane.."div", util.clamp(params:get("twin"..sel_lane.."div") + d, 1, #time.modes))
      elseif sel_alt_screen_edit == 2 then
        params:set("twin"..sel_lane.."direction", util.clamp(params:get("twin"..sel_lane.."direction") + d, 1, #SEQ_OPTIONS))
      elseif sel_alt_screen_edit == 3 then
        params:set("twinfluence"..sel_lane, util.clamp(params:get("twinfluence"..sel_lane) + d/100, 0, 1))
      end
    else
      if sel_screen_edit == 1 then
        params:set("twin"..sel_lane.."lfo"..sel_lfo.."shape", util.clamp(params:get("twin"..sel_lane.."lfo"..sel_lfo.."shape") + d, 1, #LFO_SHAPES))
      elseif sel_screen_edit == 2 then
        params:set("twin"..sel_lane.."lfo"..sel_lfo.."rate", util.clamp(params:get("twin"..sel_lane.."lfo"..sel_lfo.."rate") + d/100, 0.01, 10))
      elseif sel_screen_edit == 3 then
        params:set("twin"..sel_lane.."lfo"..sel_lfo.."off", util.clamp(params:get("twin"..sel_lane.."lfo"..sel_lfo.."off") + d, -12, 12))
      elseif sel_screen_edit == 4 then
        params:set("twin"..sel_lane.."lfo"..sel_lfo.."amp", util.clamp(params:get("twin"..sel_lane.."lfo"..sel_lfo.."amp") + d/100, 0, 5))
      end
    end
    screen_dirty = true
  end
end

function count_and_act()
  for i=1,2 do
    for j=1,4 do
      lfo_counter[i][j] = lfo_counter[i][j] + 1 --advance all lfos
      if lfo_counter[i][j] >= (LFO_RES / params:get("twin"..i.."lfo"..j.."rate")) then
        lfo_counter[i][j] = 0
      end
    end
    
    --mute
    if params:get("twin"..i.."lfo"..twinstep[i].."shape") == 1 then
      twin_lfo_value[i][twinstep[i]] = 0 --center the note when mute is active

    --square
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 2 then
      twin_lfo_value[i][twinstep[i]] = math.sin((2 * math.pi) * lfo_counter[i][twinstep[i]]/(LFO_RES / params:get("twin"..i.."lfo"..twinstep[i].."rate")))
      twin_lfo_value[i][twinstep[i]] = util.round(twin_lfo_value[i][twinstep[i]],1)
      if twin_lfo_value[i][twinstep[i]] ~= 0 then
        twin_lfo_value[i][twinstep[i]] = ampoffandtwinfluence(i)
        old_note[i][twinstep[i]] = note[i][twinstep[i]]
        note[i][twinstep[i]] = math.floor(12 * twin_lfo_value[i][twinstep[i]])
        if math.abs(note[i][twinstep[i]] - old_note[i][twinstep[i]]) >= 1 or params:get("twin"..i.."lfo"..twinstep[i].."amp") == 0 then 
          play_lfo(note[i][twinstep[i]], i)
        end
      end
    
    --random
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 3 then
      if lfo_counter[i][twinstep[i]] == 0 then
        lfo_counter[i][twinstep[i]] = 0
        twin_lfo_value[i][twinstep[i]] = math.random(120)/120
        twin_lfo_value[i][twinstep[i]] = ampoffandtwinfluence(i)
        old_note[i][twinstep[i]] = note[i][twinstep[i]]
        note[i][twinstep[i]] = math.floor(12 * twin_lfo_value[i][twinstep[i]])
        if math.abs(note[i][twinstep[i]] - old_note[i][twinstep[i]]) >= 1 or params:get("twin"..i.."lfo"..twinstep[i].."amp") == 0 then 
          play_lfo((note[i][twinstep[i]]), i)
        end
      end

    --triangle
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 4 then
      if lfo_counter[i][twinstep[i]] <= LFO_RES / (2*params:get("twin"..i.."lfo"..twinstep[i].."rate")) then
        twin_lfo_value[i][twinstep[i]] = 4 * lfo_counter[i][twinstep[i]] / (LFO_RES / params:get("twin"..i.."lfo"..twinstep[i].."rate")) - 1
      else
        twin_lfo_value[i][twinstep[i]] = 3 - 4 * lfo_counter[i][twinstep[i]] / (LFO_RES / params:get("twin"..i.."lfo"..twinstep[i].."rate"))
      end
      twin_lfo_value[i][twinstep[i]] = ampoffandtwinfluence(i)
      old_note[i][twinstep[i]] = note[i][twinstep[i]]
      note[i][twinstep[i]] = math.floor(12 * twin_lfo_value[i][twinstep[i]])
      if math.abs(note[i][twinstep[i]] - old_note[i][twinstep[i]]) >= 1 or params:get("twin"..i.."lfo"..twinstep[i].."amp") == 0 then 
        play_lfo(note[i][twinstep[i]], i)
      end


    --ramp up
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 5 then
      twin_lfo_value[i][twinstep[i]] = 2 * lfo_counter[i][twinstep[i]] / (LFO_RES / params:get("twin"..i.."lfo"..twinstep[i].."rate")) - 1
      twin_lfo_value[i][twinstep[i]] = ampoffandtwinfluence(i)
      old_note[i][twinstep[i]] = note[i][twinstep[i]]
      note[i][twinstep[i]] = math.floor(12 * twin_lfo_value[i][twinstep[i]])
      if math.abs(note[i][twinstep[i]] - old_note[i][twinstep[i]]) >= 1 or params:get("twin"..i.."lfo"..twinstep[i].."amp") == 0 then 
        play_lfo(note[i][twinstep[i]], i)
      end

    --ramp down
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 6 then
      twin_lfo_value[i][twinstep[i]] = 1 - 2 * lfo_counter[i][twinstep[i]] / (LFO_RES / params:get("twin"..i.."lfo"..twinstep[i].."rate"))
      twin_lfo_value[i][twinstep[i]] = ampoffandtwinfluence(i)
      old_note[i][twinstep[i]] = note[i][twinstep[i]]
      note[i][twinstep[i]] = math.floor(12 * twin_lfo_value[i][twinstep[i]])
      if math.abs(note[i][twinstep[i]] - old_note[i][twinstep[i]]) >= 1 or params:get("twin"..i.."lfo"..twinstep[i].."amp") == 0 then 
        play_lfo(note[i][twinstep[i]], i)
      end
    --sine
    elseif params:get("twin"..i.."lfo"..twinstep[i].."shape") == 7 then
      twin_lfo_value[i][twinstep[i]] = math.sin((2 * math.pi) * lfo_counter[i][twinstep[i]]/(LFO_RES / params:get("twin"..i.."lfo"..twinstep[i].."rate")))
      twin_lfo_value[i][twinstep[i]] = ampoffandtwinfluence(i)
      old_note[i][twinstep[i]] = note[i][twinstep[i]]
      note[i][twinstep[i]] = math.floor(12 * twin_lfo_value[i][twinstep[i]])
      if math.abs(note[i][twinstep[i]] - old_note[i][twinstep[i]]) >= 1 or params:get("twin"..i.."lfo"..twinstep[i].."amp") == 0 then 
        play_lfo(note[i][twinstep[i]], i)
      end
    end
  end
end

function ampoffandtwinfluence(i)
  return ((twin_lfo_value[i][twinstep[i]]
      * params:get("twin"..i.."lfo"..twinstep[i].."amp"))
      + (params:get("twin"..i.."lfo"..twinstep[i].."off") / 12))
      + ((params:get("twinfluence"..i) 
      * twin_lfo_value[util.wrap(i+1,1,2)][twinstep[util.wrap(i+1,1,2)]]))
end

function play_lfo(note, i)
  note = util.wrap(60 + note, params:get("note_lim_low_"..i), params:get("note_lim_high_"..i))
  note = music.snap_note_to_array(note, scale)
  if params:get("twin"..i.."out") == 2 then
    engine.start(i,music.note_num_to_freq(note))
      clock.run(eng_hang, note, i)
  elseif params:get("twin"..i.."out") == 3 then
    m:note_off(note,100,params:get("midi_ch_"..i))
    m:note_on(note,100,params:get("midi_ch_"..i))
    clock.run(midihang, note, ch, i)
  elseif params:get("twin"..i.."out") == 4 then
    crow.output[(i-1)*2 + 1].volts = (((note)-60)/12)
    crow.output[(i-1)*2 + 2]()
  elseif params:get("twin"..i.."out") == 5 then
    crow.send("ii.wsyn.play_note(".. ((note)-60)/12 ..", " .. params:get("wsyn_vel") .. ")")
  elseif params:get("twin"..i.."out") == 6 then
    crow.ii.jf.play_note(((note)-60)/12,5)
  end
end

function midihang(note, ch, i)
  clock.sleep(1 / (2 * params:get("twin"..i.."lfo"..twinstep[i].."rate")))
  m:note_off(note,100,ch)
end   

function eng_hang(note,i)
  clock.sleep(1 / (2 * params:get("twin"..i.."lfo"..twinstep[i].."rate")))
  engine.stop(i)
end
 
function redraw_clock()
  while true do
    clock.sleep(1/15)
    if screen_dirty then
      redraw()
    end
  end
end
 
function redraw()
  screen.clear()
  screen.move(64, 14)
  screen.level(8)
  screen.text_center("' ' ' ' ' t v i b u r a r ' ' ' ' '")
  for y=1,2 do
    for x=1,4 do
      screen.rect(6+(x-1)*10,25+(y-1)*10,8,8)
      if twinstep[y] == x then screen.level(15) else screen.level(5) end
      screen.fill()
    end
  end

  if ALT_KEY then
    screen.level(15)
    screen.move(4, 25+(sel_lane-1)*10)
    screen.line (4, 33+(sel_lane-1)*10)
    screen.stroke()
  else
    screen.level(15)
    screen.move(6+(sel_lfo-1)*10, 23+(sel_lane-1)*23)
    screen.line (14+(sel_lfo-1)*10, 23+(sel_lane-1)*23)
    screen.stroke()
  end
  
  if ALT_KEY then
    screen.level(sel_alt_screen_edit == 1 and 15 or 2)
    screen.move(98, 40)
    screen.text_right("speed:")
    screen.move(102, 40)
    screen.text(time.names[params:get("twin"..sel_lane.."div")])
    screen.level(sel_alt_screen_edit == 2 and 15 or 2)
    screen.move(98, 50)
    screen.text_right("direction:")
    screen.move(102, 50)
    screen.text(SEQ_OPTIONS[params:get("twin"..sel_lane.."direction")])
    screen.level(sel_alt_screen_edit == 3 and 15 or 2)
    screen.move(98, 60)
    screen.text_right("twinfluence "..sel_lane.." <- "..util.wrap(sel_lane+1,1,2)..":")
    screen.move(102,60)
    screen.text(params:get("twinfluence"..sel_lane))
  else
    screen.level(sel_screen_edit == 1 and 15 or 2)
    screen.move(78, 30)
    screen.text_right("shape:")
    screen.move(82, 30)
    screen.text(LFO_SHAPES[params:get("twin"..sel_lane.."lfo"..sel_lfo.."shape")])
    screen.level(sel_screen_edit == 2 and 15 or 2)
    screen.move(78, 40)
    screen.text_right("rate:")
    screen.move(82, 40)
    screen.text(params:get("twin"..sel_lane.."lfo"..sel_lfo.."rate").." hz")
    screen.level(sel_screen_edit == 3 and 15 or 2)
    screen.move(78, 50)
    screen.text_right("offset:")
    screen.move(82, 50)
    screen.text(params:get("twin"..sel_lane.."lfo"..sel_lfo.."off").." st")
    screen.level(sel_screen_edit == 4 and 15 or 2)
    screen.move(78, 60)
    screen.text_right("amplitude:")
    screen.move(82, 60)
    screen.text(params:get("twin"..sel_lane.."lfo"..sel_lfo.."amp"))
  end
  screen_dirty = false
  screen.update()
end                       
 
function rerun()
  norns.script.load(norns.state.script)
end