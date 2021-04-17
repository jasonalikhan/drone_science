-- midi pattern looper machine
-- @classmod machine_midiloop

event_pattern = include 'drone_science/lib/event_pattern'

local machine_midiloop = {}

--- constructor
function machine_midiloop:new(machine_num)
  local o = {}
  self.__index = self
  setmetatable(o, self)

  -- output: assume first midi device
  o.midi_in_channel = 1
  o.midi_out_device = midi.connect(1)
  o.midi_out_channel = 1
  o.midi_thru = false
  o.machine_num = machine_num
  o.param_prefix = "ml"..machine_num

  -- user interface stuff
  o.machine_foreground = false -- true if machine is in foreground (in view)
  o.k1_shift = false -- for secondary functions
  --o.ctl_arc4 = 0
  o.ctl_arc4_updatetime = 0

  -- the sequencer machine
  o.m = {
    -- sequencer clock control
    seq_state = 0, -- stop/edit = 0, play = 1, 2 = record, 3 = overdub

    -- pattern recorders
    num_patterns = 8,
    patterns = {},
    time_factor = 1.0,
    curr_pattern = 1,

    -- list of active notes
    active_note = {},
  }

  return o
end

-- init
--
-- main script init
--

function machine_midiloop:init()

  self.midi_out_device.event = function() end

  -- init all patterns
  for i = 1, self.m.num_patterns do
    self.m.patterns[i] = event_pattern:new()
--    self.m.patterns[i].process = self.midi_message_handler
    self.m.patterns[i].process = function(msg) self:midi_message_handler(msg, true) end
  end

  -- init active notes table
  self.m.active_note = {n=128}
end

-- cleanup
--
-- main script cleanup
--
function machine_midiloop:cleanup()
  self:all_notes_off()
end

-- foreground
--
-- call when machine is in foregound
-- visible on screen and taking encoder input
--
function machine_midiloop:foreground()
  self.machine_foreground = true
end

-- background
--
-- call when machine if offscreen
--
function machine_midiloop:background()
  self.machine_foreground = false
end

-- all_notes_off
--
-- outputs note off messages for all midi notes and clears
-- all pending note_off clock events
--

function machine_midiloop:all_notes_off()
  for note_num=0, 127 do
    self.midi_out_device:note_off(note_num, nil, self.midi_out_channel)
  end
end

-- active_notes_off
--
-- outputs note off messages for all midi notes and clears
-- all pending note_off clock events
--
function machine_midiloop:active_notes_off()
  for n, _ in pairs(self.m.active_note) do
    if self.m.active_note[n] == true then
      self.midi_out_device:note_off(n, nil, self.midi_out_channel)
      self.m.active_note[n] = nil
    end
  end
end

-- midi_data_handler
--
-- process raw midi input
--
function machine_midiloop:midi_data_handler(data)
  local msg = midi.to_msg(data)

  if (msg.ch == self.midi_in_channel) and (self.machine_foreground == true) then
    self:midi_message_handler(msg, false)
  end
end

-- midi_message_handler
--
-- process midi messages
--
function machine_midiloop:midi_message_handler(msg, sequencer_event)

  if (self.midi_thru==true) or (sequencer_event==true) then
    -- note on
    if msg.type == "note_on" then
      self:noteon(msg.note, msg.vel)
      -- note off
    elseif msg.type == "note_off" then
      self:noteoff(msg.note)
      -- key pressure
    elseif msg.type == "key_pressure" then

      -- channel pressure
    elseif msg.type == "channel_pressure" then

      -- pitch bend
    elseif msg.type == "pitchbend" then
      local bend_st = (util.round(msg.val / 2)) / 8192 * 2 -1 -- Convert to -1 to 1
      -- CC
    elseif msg.type == "cc" then
      -- mod wheel
      if msg.cc == 1 then
      end
    end
  end

  -- record msg events
  if (self.m.seq_state == 2) or (self.m.seq_state == 3) then
    self.m.patterns[self.m.curr_pattern]:watch(msg)
  end
end

-- note on
--
-- play a note to midi and engine
--

function machine_midiloop:noteon(note_num, note_vel)
  -- if note is already on, send a note off before retrig
  if self.m.active_note[note_num] == true then self:noteoff(note_num) end
  self.midi_out_device:note_on(note_num, note_vel, self.midi_out_channel)
  self.m.active_note[note_num] = true
end

-- note off
--
-- play a note to midi and engine
--
function machine_midiloop:noteoff(note_num)
  self.midi_out_device:note_off(note_num, nil, self.midi_out_channel)
  self.m.active_note[note_num] = nil
end

-- clear all patterns
--
-- does what it says!
--
function machine_midiloop:clear_all_patterns()
  for i = 1, self.m.num_patterns do
    self.m.patterns[i]:clear()
  end
end

-- key
--
-- process norns keys
--

function machine_midiloop:key(n, z)

  -- process k1 as a shift key for arc encoder input
  if n == 1 then
    if z == 1 then
      self.k1_shift = true
    elseif z == 0 then
      self.k1_shift = false
    end
  end

  local pattern = self.m.patterns[self.m.curr_pattern]

  -- K2: stop transport + clear pattern
  if (n == 2 and z == 1) and (self.k1_shift == false) then
    -- toggle record on/off
    if(self.m.seq_state == 0) then -- clear pattern
      if pattern.count > 0 then pattern:clear() end
    elseif (self.m.seq_state == 1) then -- stop playback
      self.m.seq_state = 0
      pattern:stop()
      self:active_notes_off()
    elseif self.m.seq_state == 2 then -- stop recording
      self.m.seq_state = 0
      pattern:rec_stop()
    elseif self.m.seq_state == 3 then
      self.m.seq_state = 0
      pattern:set_overdub(0)
      pattern:stop()
      self:active_notes_off()
    end
  end

  -- K3: toggle record on/off
  if (n == 3 and z == 1) and (self.k1_shift == false) then
    if (self.m.seq_state == 0) and (pattern.count > 0) then -- start pattern playback
      pattern:start()
      self.m.seq_state = 1
    elseif (self.m.seq_state == 0) and (pattern.count == 0) then -- start recording
        self.m.seq_state = 2
        pattern:rec_start()
    elseif self.m.seq_state == 1 then -- start overdub
        self.m.seq_state = 3
        pattern:set_overdub(1)
    elseif self.m.seq_state == 2 then -- stop recording
      self.m.seq_state = 1
      pattern:rec_stop()
      self:active_notes_off()
      if pattern.count > 0 then pattern:start() end
    elseif self.m.seq_state == 3 then -- stop overdub
      self.m.seq_state = 1
      pattern:set_overdub(0)
    end
  end

  if self.machine_foreground == true then redraw() end
end

-- enc
--
-- process norns encoders
--

function machine_midiloop:enc(n, d)

  -- select patterns when machine is stopped
  if (n == 3) and (self.m.seq_state == 0) then
    self.m.curr_pattern = util.clamp(self.m.curr_pattern + d, 1, self.m.num_patterns)
  end

  if self.machine_foreground == true then redraw() end
end

-- redraw
--
-- handle norns screen updates
--

function machine_midiloop:redraw()
  local pattern = self.m.patterns[self.m.curr_pattern]

  screen.level(15)
  screen.move(0,10)
  screen.font_size(8)
  if self.m.seq_state == 0 then
    if pattern.count > 0 then
      screen.text("stop")
    else
      screen.text("empty")
    end
  elseif self.m.seq_state == 1 then
    screen.text("play")
  elseif self.m.seq_state == 2 then
    screen.text("record")
  elseif self.m.seq_state == 3 then
    screen.text("overdub")
  end

  screen.level(15)
  screen.move(128, 10)
  screen.text_right("midi loop "..self.m.curr_pattern)

  if pattern.count > 0  then
    -- duration
    screen.move(15,40)
    screen.font_size(16)
    screen.text(string.format("%.2f", pattern.duration * pattern.time_factor).."s")
    -- time factor
    screen.move(80,40)
    screen.font_size(16)
    screen.text(string.format("%.2f", pattern.time_factor).."x")
  end
end


-- a.delta
--
--- process arc encoder inputs
--

function machine_midiloop:arc_delta(n, d)

  local pattern =  self.m.patterns[self.m.curr_pattern]

  if self.k1_shift == false then
    if n == 4 then
      pattern.time_factor = util.clamp(pattern.time_factor + pattern.time_factor * (d / 400), 1/4, 8)
      self.ctl_arc4_updatetime = util.time()
    end
  else -- shift functions

  end

  if self.machine_foreground == true then redraw() end

end

-- arc_redraw_handler
--
-- refresh arc leds, driven by fast metro
--

function machine_midiloop:arc_redraw(a)

  -- enc1: active notes
  for n, _ in pairs(self.m.active_note) do
    if self.m.active_note[n] == true then
      a:led(1, math.floor(tonumber(n)/2)+1, 15)
    end
  end

  -- enc4: global play head + and time ratio (+/- 10x)
  local pattern =  self.m.patterns[self.m.curr_pattern]

  if self.ctl_arc4_updatetime == 0 then -- no recent value updates,
    if pattern.play == 1 then
      a:segment(4, 0, pattern.pos * 2 * math.pi, 15)
    end
  else -- recently updated value
    local t = util.time()
    if t - self.ctl_arc4_updatetime > 0.25 then -- return to displaying the play pos
      self.ctl_arc4_updatetime = 0
    end
  end
end

-- add_params
--
-- add this machine's params to paramset
--
function machine_midiloop:add_params()
  params:add_group("midiloop"..self.machine_num.." SETTINGS", 3)

  cs_MIDI_CH = controlspec.new(1, 16, 'lin' ,1 ,1 ,'' ,0.01 , false)
  params:add{type="control", id=self.param_prefix.."_midi_in", name="midi in channel", controlspec=cs_MIDI_CH, action=function(x) self.midi_in_channel=x end}
  params:add{type="control", id=self.param_prefix.."_midi_out", name="midi out channel", controlspec=cs_MIDI_CH, action=function(x) self.midi_out_channel=x end}
  params:add_option(self.param_prefix.."_midi_thru", "midi thru", {"off","on"}, 1)
  params:set_action(self.param_prefix.."_midi_thru", function(x) if (x-1) == 0 then self.midi_thru=false else self.midi_thru=true end end)
end

-- export_packed_params
--
-- write patterns to paramset
--
function machine_midiloop:export_packed_params()
  -- do nothing
end

-- import_data
--
-- read packed data from paramset
--
function machine_midiloop:import_packed_params()
    -- to do
end


return machine_midiloop
