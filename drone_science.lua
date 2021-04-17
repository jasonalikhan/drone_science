-- drone science
---multi-machine groovebox

engine.name = "grainloops"
machine_grainloop = include("drone_science/lib/machine_grainloop")
machine_midiloop = include("drone_science/lib/machine_midiloop")
machine_midigenstep = include("drone_science/lib/machine_genstep")
machine_delay = include("drone_science/lib/machine_delay")

-- input: arc required
local a = arc.connect(1)
local ui_metro = metro.init()

-- save params
local save_metro = metro.init()

-- the sequencer machines
local num_machines = 7
local machines = {}
local curr_machine

-- midi stuff
local midi_in_device


-- init
--
-- maint script init
--

function init()

  -- init the engine (load wavetables, boot lfos)

  engine.create_grainloop(3)

  -- allocate the machines
  machines[1] = machine_grainloop:new(1, 1)
  machines[2] = machine_grainloop:new(2, 2)
  machines[3] = machine_grainloop:new(3, 3)
  machines[4] = machine_midiloop:new(4)
  machines[5] = machine_midigenstep:new(5)
  machines[6] = machine_midigenstep:new(6)
  machines[7] = machine_delay:new()

  -- boot up each machine
  for i = 1, num_machines do
    machines[i]:init()
  end

  -- assign midi handler
  midi_in_device = midi.connect(1)
  midi_in_device.event = midi_data_handler

  curr_machine = 1
  machines[curr_machine]:foreground()

  -- arc led updates @ 30hz refresh
  ui_metro = metro.init()
  ui_metro.time = .03
  ui_metro.event = arc_redraw
  ui_metro:start()

  -- setup the params
  for i = 1, num_machines do
    machines[i]:add_params()
  end

  -- load default paramset
  params:default()
  for i = 1, num_machines do
    machines[i]:import_packed_params()
  end

  -- save machine data to params every 10 seconds
  save_metro = metro.init()
  save_metro.time = 10.0
  save_metro.event = save_machine_data
  save_metro:start()

  -- encoder1 sensitivity - make machine selection feel natural
  norns.enc.sens(1,3)
end

-- write_all_machine_states
--
-- write all machine states to paramset
--

function save_machine_data(c)
  for i = 1, num_machines do
    machines[i]:export_packed_params();
  end
end

-- midi_data_handler
--
-- process raw midi input
--
function midi_data_handler(data)
  local msg = midi.to_msg(data)

  machines[curr_machine]:midi_message_handler(msg)
end

-- cleanup
--
-- script cleanup
--

function cleanup()

  -- dealloc and cleanup all machines
  for i = 1, num_machines do
    machines[i]:cleanup()
  end
end

-- key
--
-- process norns keys
--

function key(n, z)

  machines[curr_machine]:key(n, z)
  redraw()

end

-- enc
--
-- process norns encoders
--

function enc(n, d)
  if n == 1 then
    curr_machine = util.clamp(curr_machine + d, 1, num_machines)
    for i = 1, num_machines do
      if i == curr_machine then machines[i]:foreground() else machines[i]:background() end
    end
  else
    machines[curr_machine]:enc(n, d)
  end

  redraw()
end

-- redraw
--
-- handle norns screen updates
--
function redraw()

  screen.clear()

  --local line_width = math.floor((128 + (num_machines - 1 ) * 2) / num_machines)
  local line_width = math.floor(128 / num_machines)

  -- draw current machine indicator
  for i = 1, num_machines do
    if i == curr_machine then
      screen.level(15)
      screen.line_width(4)
      yoffset = 0
    else
      screen.level(2)
      screen.line_width(1)
      yoffset = 1
    end
    screen.move( (i - 1) * line_width + 1, 1 + yoffset)
    screen.line( (i * line_width), 1 + yoffset)

    screen.stroke()
  end

  machines[curr_machine]:redraw()

  screen.update()
end

-- a.delta
--
--- process arc encoder inputs
--

function a.delta(n, d)
  machines[curr_machine]:arc_delta(n, d)
end

--  arc_redraw
--
--- process arc redraw
--
function arc_redraw()
  -- arc redraw
  a:all(0)
  machines[curr_machine]:arc_redraw(a)
  a:refresh()
end
