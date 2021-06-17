local lattice = require("lattice")
local music = require("musicutil")

local m = midi.connect(1)
local lfo_resolution = 1000
local saved_lfo_val = 0
local current_lfo_val = 1
local lfo_res_step = 0

local scales = {}
local scale = {}

function init()

  for i = 1, #music.SCALES do
    table.insert(scales, string.lower(music.SCALES[i].name))
  end
  
  init_params()
  scale = music.generate_scale(params:get("root_note")-1, x, 10) 

  lane_1 = {
    division = 1/4,
    active_lfo = 1,
    lfos = {
      lfo_1 = {
        shape = 'square',
        amp = 1.5
      },
      lfo_2 = {
        shape = 'square',
        amp = 2
      },
      lfo_3 = {
        shape = 'square',
        amp = 1
      },
      lfo_4 = {
        shape = 'square',
        amp = 0.5
      }
    }
  }
  lane_2 = {
    division = 1/4,
    active_lfo = 1,
    lfos = {
      lfo_1 = {
        rate = 100,
        shape = 'square',
        amp = 1
      },
      lfo_2 = {
        rate = 100,
        shape = 'square',
        amp = 1
      },
      lfo_3 = {
        rate = 100,
        shape = 'square',
        amp = 1
      },
      lfo_4 = {
        rate = 100,
        shape = 'square',
        amp = 1
      }
    }
  }

  for i=0,127 do
    m:note_off(i,0,1)
  end
  time_handler = lattice:new()
  lane_1_timer = time_handler:new_pattern{
    action = function (x)
      lane_1['active_lfo'] = lane_1['active_lfo'] + 1
      lfo_res_step = 0
      if lane_1['active_lfo'] > 4 then lane_1['active_lfo'] = 1 end
      --print(lane_1['active_lfo'])
    end,
    division = lane_1['division']
  }
  lane_2_timer = time_handler:new_pattern{
    action = function (x) 
      lane_2['active_lfo'] = lane_2['active_lfo'] + 1
      if lane_2['active_lfo'] > 4 then lane_2['active_lfo'] = 1 end
    end,
    division = lane_2['division']
  }
  time_handler:start()
  metro.init(update_lfos, 1 / lfo_resolution):start()
end

function init_params()
  params:add_option("scale","scale",scales,1)
  params:set_action("scale", function (x) 
    scale = music.generate_scale(params:get("root_note")-1, x, 10) 
  end)
  params:add_option("root_note", "root note", music.note_nums_to_names({0,1,2,3,4,5,6,7,8,9,10,11}),1)
  for i=1,2 do
    for j=1,4 do
      params:add_control("lane_"..i.."_lfo_"..j.."_rate","lane "..i.." lfo rate"..j,controlspec.new(0.1,50,"lin",0.001,1,"hz",1/10000))
      --params:hide("lane_"..i.."_lfo_"..j.."_rate")
    end
  end
  for i=1,2 do
    for j=1,4 do
      params:add_control("lane_"..i.."_lfo_"..j.."_amp","lane "..i.." lfo amp"..j,controlspec.new(0,5,"lin",0.08,1,"hz",1/25))
    end
  end
end

function update_lfos()
    lfo_res_step = lfo_res_step + 1
    if lane_1['lfos']['lfo_'..lane_1['active_lfo']]['shape'] == 'square' then
      --if lane_1['active_lfo'] == 1 then
      --  print("res step: " .. lfo_res_step * 2 .. " lfo: " .. math.floor(lfo_resolution / params:get("lane_1_lfo_"..lane_1['active_lfo'].."_rate")))
      --end
      if lfo_res_step * 2 == math.floor(lfo_resolution / params:get("lane_1_lfo_"..lane_1['active_lfo'].."_rate")) then
      --lane_1['lfos']['lfo_'..lane_1['active_lfo']]['rate']) then
        
        current_lfo_val = current_lfo_val * -1
        lfo_res_step = 0
        play(math.floor(current_lfo_val * params:get("lane_1_lfo_"..lane_1['active_lfo'].."_amp") * 12))
        --lane_1['lfos']['lfo_'..lane_1['active_lfo']]['amp']*12))
      end
    end
end

function play(note)
  --print(note)
  note = music.snap_note_to_array(note,scale)
  --m:note_off(note + 72,100,1)
  m:note_on(note + 60,100,1)
  --m:note_off(note + 72,100,1)
end






function rerun()
  norns.script.load(norns.state.script)
end

--lfo_res_step = lfo_res_step + 1
--    if lfo_res_step / lfo_resolution > 1 / (2 * lane_1['lfos']['lfo_'..lane_1['active_lfo']]['rate']) then
--      saved_lfo_val = current_lfo_val
--      current_lfo_val = current_lfo_val * -1
      --print(lane_1['lfos']['lfo_'..lane_1['active_lfo']]['rate'])
      --print(math.floor(current_lfo_val * 12))
--      play(math.floor(current_lfo_val * 12))
--    end
--    if lfo_res_step > lane_1['lfos']['lfo_'..lane_1['active_lfo']]['rate'] then lfo_res_step = 0 end
--  end
--]]