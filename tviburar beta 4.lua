local m = midi.connect(1)

local LFO_RES = 1000

local lfo_rate = 100

function init()

  lfo_counter = 0

  main_metro = metro.init(count_and_act, 1/LFO_RES):start()

  clock.run(redraw_clock)
end

function redraw_clock()
  clock.sleep(1/30)
  --if screen_dirty then
    redraw()
    --screen_dirty = false
  --end
end

function redraw()
  screen.clear()
  screen.move(10,10)
  --screen.text(lfo_counter)
  screen.update()
  --screen_dirty = false
end

function count_and_act()
  lfo_counter = lfo_counter + 1
  if lfo_counter >= (LFO_RES / (2*lfo_rate)) then
    m:note_off(60,100,1)
    m:note_on(60,100,1)
    lfo_counter = 0
  end
  --print(lfo_counter)
  --screen_dirty = true
end

function midihang(note)
  clock.sleep(0.01)
  m:note_off(note,100,1)
end

