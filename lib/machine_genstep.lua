-- complex stoachastic pattern sequencer
-- @classmod machine_genstep

local machine_genstep = {}

--- constructor
function machine_genstep:new(machine_num)
  local o = {}
  self.__index = self
  setmetatable(o, self)

  o.machine_num = machine_num
  o.param_prefix = "gs"..machine_num

  -- output: assume first midi device
  o.midi_in_channel = 1
  o.midi_out_device = midi.connect(1)
  o.midi_out_channel = 1
  o.midi_thru = false

  o.note_str = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

  -- is set by parent class by foreground / background setter functions
  -- =machine will call redraw function if in foreground
  o.machine_foreground = false

  -- for k1 shift key
  o.k1_shift = false

  -- base parameters for note pattern generation
  o.root = {
    offset = 50,
    notes =  {0, -2, -5, -7, 3, 5, 3, 2, 7},
    length = 9,
    }

  -- base parameters for live definition of root params
  o.root_temp = {
    offset = 0,
    notes =  {} ,
    length = 0,
    }

  o.max_pattern_length = 64

  -- base template for trig pattern generation
  o.trig_pattern_template = {
    probability = {
      1, .7, 0, .7, 0, 1, .7, 0,
      0, 0, 1, 0, .7, 0, .3, .5,
      1, .7, 0, .7, 0, 1, .7, 0,
      0, 0, 1, 0, .7, 0, .3, .5,
      1, .7, 0, .7, 0, 1, .7, 0,
      0, 0, 1, 0, .7, 0, .3, .5,
      1, .7, 0, .7, 0, 1, .7, 0,
      0, 0, 1, 0, .7, 0, .3, .5},
    velocity = {
      .5, .5, .5, .5, .5, .5, .5, .5,
      .5, .5, .5, .5, .5, .5, .5, .5,
      .5, .5, .5, .5, .5, .5, .5, .5,
      .5, .5, .5, .5, .5, .5, .5, .5,
      .5, .5, .5, .5, .5, .5, .5, .5,
      .5, .5, .5, .5, .5, .5, .5, .5,
      .5, .5, .5, .5, .5, .5, .5, .5,
      .5, .5, .5, .5, .5, .5, .5, .5},
    duration = { -- note: this script doesn't use the duration array
      4, 4, 4, 4, 4, 4, 4, 4,
      4, 4, 4, 4, 4, 4, 4, 4,
      4, 4, 4, 4, 4, 4, 4, 4,
      4, 4, 4, 4, 4, 4, 4, 4,
      4, 4, 4, 4, 4, 4, 4, 4,
      4, 4, 4, 4, 4, 4, 4, 4,
      4, 4, 4, 4, 4, 4, 4, 4,
      4, 4, 4, 4, 4, 4, 4, 4},
    length = 64
  }

  -- play modes
  o.play_mode_labels = {"forward", "buddha"}

  -- time divisions
  o.time_divisions = {1/8, 1/4, 1/2, 5/8, 3/4, 1, 1.5, 2, 4, 6, 8}
  o.time_divisions_str = {"1/32", "1/16", "1/8", "5/8", "3/4","1", "6/4", "half", "whole", "6/4", "2 bars"}
  o.num_time_divisions = 11

  -- key shift divisions
  o.length_factors = {1/16, 1/8, 1/4, 1/2, 1}
  o.num_length_factors = 5

  -- params for editing sequences w/ enc2 and enc3
  o.enc2_delta = 0
  o.enc3_delta = 0

  -- the sequencer machine
  o.m = {
      -- live control params mapped to arc encoders
      ctl_slide = 0,
      ctl_length_factor = 1.0,
      ctl_scrub = 0,

      -- global sequencer vars
      pattern_length = 32,
      seq_current_step = 1,
      seq_note_pattern = 1,
      seq_trig_pattern = 1,
      seq_time_division = 2,
      seq_length_factor = 5,
      seq_stutter_step = 0,
      seq_stutter_count = 0,
      seq_pre_chaos_pattern = 0,
      seq_chaos_count = 0,
      seq_chaos = 0,
      seq_activity = 1,
      scale_definition_mode = false,

      -- sequencer clock control
      seq_state = 0, -- stop/edit, play = 1, define = 2
      seq_play_mode = 1, -- forward looping playback
      seq_coroutine_id = 0,

      -- pattern tables constructed through init code
      trig_patterns = {},
      num_trig_patterns = 16,
      note_patterns = {},
      num_note_patterns = 16,

      -- array of active notes, uses clock to schedule noteoff messages
      active_note = {},
      active_note_coroutines = {},
    }

  return o
end

-- init
--
-- main script init
--

function machine_genstep:init()

  self.midi_out_device.event = function() end

  -- fill note patterns
  self:init_note_pattern_table(m)
  self.m.seq_note_pattern = 1
  for i = 1, self.m.num_note_patterns do
    self:gen_rand_note_pattern(m, i)
  end

  -- fill trig patterns
  self:init_trig_pattern_table(m)
  self.m.seq_trig_pattern = 1
  for i = 1, self.m.num_trig_patterns do
    self:gen_rand_trig_pattern(m, i)
  end

  self:stop_sequencer_playback(m)

  -- init active notes table
  self.m.active_note = {n=128}
  self.m.active_note_coroutines = {n=128}
end

-- cleanup
--
-- main script cleanup
--
function machine_genstep:cleanup()
  self:all_notes_off()
end

-- foreground
--
-- call when machine is in foregound
-- visible on screen and taking encoder input
--
function machine_genstep:foreground()
  self.machine_foreground = true
end

-- background
--
-- call when machine if offscreen
--
function machine_genstep:background()
  self.machine_foreground = false
end

-- init_trig_pattern_table
--
-- main structure for generated/edited note patterns
--

function machine_genstep:init_note_pattern_table(m)
  for i=1,self.m.num_note_patterns do
    self.m.note_patterns[i] = {
      note = {n=self.max_pattern_length},
      offset = 0,
      shift_floor,
      shift_ceiling
    }
  end
end

-- clear_note_pattern
--
-- reset a note_pattern, useful when manually step sequencing
--

function machine_genstep:clear_note_pattern(m, num)
  local np = self.m.note_patterns[num]
  for i = 0, self.max_pattern_length do
    np.note[i] = 0
  end
end

-- clear_trig_pattern
--
-- reset a trig_pattern, useful when manually step sequencing
--

function machine_genstep:clear_trig_pattern(m, num)
  local tp = self.m.trig_patterns[num]
  for i = 0, self.max_pattern_length do
    tp.probability[i] = 0
    tp.velocity[i] = 0
    -- duration: not implemented yet
  end
end

-- midi_data_handler
--
-- process raw midi input
--
function machine_genstep:midi_data_handler(data)
  local msg = midi.to_msg(data)

  if (msg.ch == self.midi_in_channel) and (self.machine_foreground == true) then
    self:midi_message_handler(msg)
  end
end

-- midi_message_handler
--
-- process midi messages
--
function machine_genstep:midi_message_handler(msg)

  -- note on
  if msg.type == "note_on" then
    if self.midi_thru==true then self:play_note(msg.note, msg.vel, -1) end
    if self.m.seq_state == 0 then
      if self.m.scale_definition_mode == true then
        self:define_input_scale(msg.note, msg.vel)
      else
        self:define_input_step(msg.note, msg.vel)
      end
      if self.machine_foreground == true then redraw() end
    elseif self.m.seq_state == 2 then -- live edit the pattern
      self:define_input_step(msg.note, msg.vel)
    end
  -- note off
  elseif msg.type == "note_off" then
    if self.midi_thru==true then self:noteoff(msg.note) end

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

-- note on
--
-- play a note to midi and engine
--
function machine_genstep:noteon(note_num, note_vel)
  -- if note is already on, send a note off before retrig
  if self.m.active_note[note_num] == true then self:noteoff(note_num) end
  self.midi_out_device:note_on(note_num, note_vel, self.midi_out_channel)
  self.m.active_note[note_num] = true
end

-- note off
--
-- play a note to midi and engine
--
function machine_genstep:noteoff(note_num)
  self.midi_out_device:note_off(note_num, nil, self.midi_out_channel)
  self.m.active_note[note_num] = nil
end


-- init_trig_pattern_table
--
-- main structure for generated/edited trig patterns
--

function machine_genstep:init_trig_pattern_table(m)
  for i=1,self.m.num_trig_patterns do
    self.m.trig_patterns[i] = {
      probability = {n=self.max_pattern_length},
      velocity = {n=self.max_pattern_length},
      duration = {n=self.max_pattern_length},
    }
  end
end

-- cancel_note_clocks
--
-- for cleanup - stop all running note metros
--

function machine_genstep:cancel_note_clocks()
  for note, id in pairs(self.m.active_note_coroutines) do
    clock.cancel(id)
  end

  self.m.active_note_coroutines = {n=128}
  self.m.active_note = {n=128}
end

-- all_notes_off
--
-- outputs note off messages for all midi notes and clears
-- all pending note_off clock events
--

function machine_genstep:all_notes_off()
  for note_num=0, 127 do
    self.midi_out_device:note_off(note_num, nil, self.midi_out_channel)
  end

  self:cancel_note_clocks()
end

-- note_off_handler
--
-- does what it says!
--

function machine_genstep:note_off_handler(note_num, note_duration)
  clock.sleep(note_duration)
  self.m.active_note_coroutines[note_num] = nil
  self.m.active_note[note_num] = nil
  self.midi_out_device:note_off(note_num, nil, self.midi_out_channel)
end

-- play_note
--
-- play a note to midi out and handle scheduling of
-- note off messages using clock coroutines
--

function machine_genstep:play_note(note_num, note_vel, note_duration)

  -- cleanup existing note and clock if note already active (retrigger condition)
  id = self.m.active_note_coroutines[note_num]
  if id ~= nil then
    clock.cancel(id)
    self.m.active_note_coroutines[note_num] = nil
    self:noteoff(note_num)
  end

  -- play the midi note
  self:noteon(note_num, note_vel)
  self.m.active_note[note_num] = true

  if note_duration > 0 then
    -- schedule a note off message
    self.m.active_note_coroutines[note_num] = clock.run(function(num, dur) self:note_off_handler(num, dur) end, note_num, note_duration)
  end
end

-- seq_run_loop
--
-- sequencer co-routine, driven by clock
--

function machine_genstep:seq_run_loop(m)
  local dir = 1
  local alt_state = 0
  local alt_state_dur = 1

  while true do

    -- forward
    if self.m.seq_play_mode == 1 then
      clock.sync(self.time_divisions[self.m.seq_time_division])
      self:seq_play_next_note(m)
      self.m.seq_current_step = (self.m.seq_current_step % (self.m.pattern_length*self.length_factors[self.m.seq_length_factor])) + 1

    -- buddha
    elseif self.m.seq_play_mode == 2 then
      -- play random note lenghts and return to normal for 8 steps once and a while
      if alt_state == 0 then
        if math.random() > .93 then
          alt_state = 1
          alt_state_dur = 8
        end
      elseif alt_state == 1 then
        if alt_state_dur == 0 then
          alt_state = 0
        end
      end

      if alt_state == 0 then
        clock.sync(self.time_divisions[self.m.seq_time_division] * (1 + math.random(2)))
      elseif alt_state == 1 then
        clock.sync(self.time_divisions[self.m.seq_time_division])
        alt_state_dur = alt_state_dur - 1
      end

      self:seq_play_next_note(m)
      self.m.seq_current_step = self:delta_wrap(self.m.seq_current_step, dir, 1, (self.m.pattern_length*self.length_factors[self.m.seq_length_factor]))

      -- change direction 10% of the time
      if math.random() > .9 then dir = dir * -1 end
    end

    if self.machine_foreground == true then redraw() end
  end
end

-- delta_wrap
--
-- wrap values to range of min max
--
function machine_genstep:delta_wrap(v, d, min, max)
  v = v + d
  if v > max then
    v = v - max
  elseif v < min then
    v = max - v
  end
  return v
end

-- seq_play_next_note
--
-- complex playback of the next note with handling of chaos,
-- stutter and activity density
--

function machine_genstep:seq_play_next_note(m)
  local p = self.m.note_patterns[self.m.seq_note_pattern]
  local s = 0
  local note
  local vel

  np = self.m.note_patterns[self.m.seq_note_pattern]
  tp = self.m.trig_patterns[self.m.seq_trig_pattern]

  -- complex chaos and stutter effects in playback mode only
  if self.m.seq_state == 1 then
    -- chaos messes things up - fx are scaled in ranges across 100% of encoder's values
    -- stutter sometimes / two ranges: 0-50% and 50-100%
    -- random trig pattern: 50-75%
    -- random sequence pattern: 75% - 100%
    if (self.m.seq_chaos > 0) and self.m.seq_stutter_count == 0 then
      if math.random() > (1 - math.fmod(self.m.seq_chaos * 2, .5) / .5 ) then
        if math.random() > .5 then
          self.m.seq_stutter_step = self.m.seq_current_step
          self.m.seq_stutter_count = math.floor(math.random() * 4)
        end
      end
    end
    if self.m.seq_chaos >= .5 and self.m.seq_chaos <= .75 then
      if math.random() > (1 - (self.m.seq_chaos - .5) / .25) then
        -- randomly switch trig pattern
        self.m.seq_trig_pattern = math.floor(math.random() * self.m.num_trig_patterns) + 1
      end
    end
    if self.m.seq_chaos >= .75  then
      -- automatically switch note pattern
      if (self.m.seq_chaos_count == 0) and (math.random() > (1 - ((self.m.seq_chaos - .75) / .25))) then
        -- randomly switch note pattern for half pattern length
        self.m.seq_pre_chaos_pattern = self.m.seq_note_pattern
        self.m.seq_chaos_count = self.m.pattern_length * .5
        self.m.seq_note_pattern = math.floor(math.random() * self.m.num_note_patterns) + 1
      end
    end

    -- process note pattern chaos
    if self.m.seq_chaos_count > 0 then
      self.m.seq_chaos_count = self.m.seq_chaos_count - 1
      if self.m.seq_chaos_count == 0 then -- resume original pattern
        self.m.seq_note_pattern = self.m.seq_pre_chaos_pattern
        self.m.seq_pre_chaos_pattern = 0
      end
    end

    -- process stutter
    if self.m.seq_stutter_count > 0 then
      self.m.seq_stutter_count = self.m.seq_stutter_count - 1
      s = self.m.seq_stutter_step
    else
      s = self.m.seq_current_step
    end
  else -- simple step tracking in edit mode
    s = self.m.seq_current_step
  end

  -- calculate current note
  note = util.clamp(np.note[s] + np.offset, 0, 127)
  vel = math.floor(tp.velocity[s] * 127)

  if (self.m.seq_state == 1) or (self.m.seq_state == 2) then -- play or define mode
    -- trig with scaled activity and probability
    if math.random() > (1 - (tp.probability[s] * self.m.seq_activity)) then
      self:play_note(note, vel, self.time_divisions[self.m.seq_time_division])
    end
  elseif self.m.seq_state == 0 then -- edit mode
    self:play_note(note, vel, self.time_divisions[self.m.seq_time_division])
  end

  if self.machine_foreground == true then redraw() end
end

-- seq_edit_retrig_note
--
-- retrig a note during editing process
--

function machine_genstep:seq_edit_retrig_note(m)
  local p = self.m.note_patterns[self.m.seq_note_pattern]
  local s = 0
  local note
  local vel

  np = self.m.note_patterns[self.m.seq_note_pattern]
  tp = self.m.trig_patterns[self.m.seq_trig_pattern]
  s = self.m.seq_current_step

  -- calcuate current note
  note = util.clamp(np.note[s] + np.offset, 0, 127)
  vel = math.floor(tp.velocity[s] * 127)
  self:play_note(note, vel, tp.duration[s])
end

-- seq_edit_note
--
-- shift a note during editing process
--

function machine_genstep:seq_edit_note(m, delta)
  local np = self.m.note_patterns[self.m.seq_note_pattern]
  local s = self.m.seq_current_step
  local sorted = self.root.notes
  local i
  local curr
  local new

  -- sort the root note array
  table.sort(sorted)
  -- find the current note in the array
  -- if not found, default to root note in scale (root.note[1])
  curr = 1
  for i = 1, self.root.length do
    if np.note[s] == sorted[i] then
      curr = i
      break
    end
  end

  -- update the note value and limit range to root note set
  new = util.clamp(curr + delta, 1, self.root.length)
  np.note[s] = sorted[new]
end

-- seq_edit_trig
--
-- shift a note down during editing process
--

function machine_genstep:seq_edit_trig(m, delta)
  local tp = self.m.trig_patterns[self.m.seq_trig_pattern]
  local s = self.m.seq_current_step

  -- udpate trig value probability
  tp.probability[s] = util.clamp(tp.probability[s] + delta, 0, 1)
end

-- gen_rand_note_pattern
--
-- generate a note pattern through randomization of the root set
--

function machine_genstep:gen_rand_note_pattern(m, num)

  local root_len = self.root.length
  local np = self.m.note_patterns[num]

  -- create a pattern using random
  np.offset = self.root.offset

  -- fill pattern with random note selections
  for i = 1, self.max_pattern_length do
    n = math.floor(math.random()*root_len) + 1
    np.note[i] = self.root.notes[n]
  end

  -- calculate the floor and ceiling for pitch shifting
  local width = self.root.notes[self:max_key(self.root.notes)] - self.root.notes[self:min_key(self.root.notes)]
  np.shift_floor = width
  np.shift_ceiling = 127 - width

end

-- gen_rand_trig_pattern
--
-- generate a trig pattern through progressive morph
-- and randomization of the base template
--

function machine_genstep:gen_rand_trig_pattern(m, num)

  local tp = self.m.trig_patterns[num]
  local r = 0

  -- copy the template to slot 1 of the pattern table
  if num == 1 then -- copy seed template to first slot always
    for i = 1, self.max_pattern_length do
      tp.probability[i] = self.trig_pattern_template.probability[i]
      tp.velocity[i] = self.trig_pattern_template.velocity[i]
      tp.duration[i] = self.trig_pattern_template.duration[i]
    end
  else -- morph previous pattern
    local tp_prev = self.m.trig_patterns[num-1]
    for i = 1, self.max_pattern_length do
      -- keep hard trigs 90% of the time
      -- otherwise replace with conditional trig between 50%-90%
      if tp_prev.probability[i] == 1 then
        if math.random() > .1 then
          tp.probability[i] = 1
        else
          tp.probability[i] = math.random()*.4+.5
        end
      -- replace empty trigs 10% of the time with a hard trig
      elseif tp_prev.probability[i] == 0 then
        if math.random() >.9 then
          tp.probability[i] = 1
        else
          tp.probability[i] = 0
        end
      -- replace conditional trigs 10% of the time with a null trig
      -- otherwise replace 20% of the time with a new conditional trig 10%-100%
      -- otherwise copy previous value
      else
        if math.random() > .9 then
          tp.probability[i] = 0
        elseif math.random() > .8 then
          tp.probability[i] = util.clamp(math.random() * 1.1, 0, 1)
        else
          tp.probability[i] = tp_prev.probability[i]
        end
      end
      -- morph velocty and duration
      -- randomize velocity 20% of the time
      -- copy the previous pattern value 20% of the time
      -- and set to .5 for the remaining 60%
      r = math.random()
      if r > 0 and r <=.2 then
        tp.velocity[i] = math.random() * .4 + .1 -- between .1 and .5
      elseif r > .2 and r <= .4 then
        tp.velocity[i] = tp_prev.velocity[i]
      else
        tp.velocity[i] = .5
      end
      tp.duration[i] = tp_prev.duration[i] -- copy duration from template as is
    end
  end
end

-- regenerate_patterns
--
-- regenerate patterns from root (seed) scale
--

function machine_genstep:regenerate_patterns()
  for i = 1, self.m.num_note_patterns do
    self:gen_rand_note_pattern(m, i)
  end
  for i = 1, self.m.num_trig_patterns do
    self:gen_rand_trig_pattern(m, i)
  end
end

-- start_sequencer_playback
--
-- does what it says!
--

function machine_genstep:start_sequencer_playback(m)
  self.m.seq_state = 1
  self.m.seq_coroutine_id = clock.run(function(param) self:seq_run_loop(param) end, m)
end


-- stop_sequencer_playback
--
-- does what it says!
--

function machine_genstep:stop_sequencer_playback(m)
  clock.cancel(self.m.seq_coroutine_id)
  self.m.seq_state = 0
end

-- key
--
-- process norns keys
--

function machine_genstep:key(n, z)

  -- process k1 as a shift key for arc encoder input
  if n == 1 then
    if z == 1 then
      self.k1_shift = true
      if self.m.seq_state == 0 then -- enter scale definition mode
        self.m.scale_definition_mode = true
      end
    elseif z == 0 then
      self.k1_shift = false
      if self.m.scale_definition_mode == true then -- exit scale definition mode, commit and regen patterns
        self.m.scale_definition_mode = false
        local newdef = self:define_commit()
        if newdef == true then self:regenerate_patterns() end
      end
    end
  end

  if self.k1_shift == false then
    -- process k2 to stop and reset the sequencer clock
    if n==2 and z==1 then
      -- toggle start/stop
      if self.m.seq_state == 1 then
        self:stop_sequencer_playback(m)
        -- vars to accumulate delta movement of encoders during editing
        self.enc2_delta = 0 -- pitch
        self.enc3_delta = 0 -- probability
      elseif self.m.seq_state == 0 then
        self.m.seq_current_step = 1
      elseif self.m.seq_state == 2 then -- leave record mode
        self.m.seq_state = 1
      end
    end

    -- process k3 to play and record
    if n == 3 then
      if z == 1 then
        if self.m.seq_state == 0 then -- leave edit mode, start playback
          self:start_sequencer_playback(m)
        elseif self.m.seq_state == 1 then  -- start define
          self.m.seq_state = 2
          self:define_begin()
        elseif self.m.seq_state == 2 then -- end define
          self.m.seq_state = 1
        end
      elseif z == 0 then
        -- nothing
      end
    end
  else -- if k1_shift == define mode

    -- clear the current trig and note patterns in edit mode
    if n == 2 and z == 1 then
      if self.m.seq_state == 0 then -- in edit mode
        self:clear_note_pattern(m, self.m.seq_note_pattern)
        self:clear_trig_pattern(m, self.m.seq_trig_pattern)
      end
    end

    -- regenerate all patterns
    if n == 3 and z == 1 then
      if self.m.seq_state == 0 then -- in edit mode
        self:regenerate_patterns()
      end
    end
  end

  if self.machine_foreground == true then redraw() end
end

-- enc
--
-- process norns encoders
--

function machine_genstep:enc(n, d)

  if n == 2 then
    self.m.seq_play_mode = util.clamp(self.m.seq_play_mode + d, 1, #self.play_mode_labels)
  end

end

-- max_key
--
-- helper function: return key of max value for an integer table
--

function machine_genstep:max_key(t)
  -- find max value
  local highest_val = t[1]
  local highest_val_index = 1
  for k,v in pairs(t) do
    if t[k] > highest_val then
      highest_val_index = k
      highest_val = t[k]
    end
  end

  return highest_val_index
end

-- min_key
--
-- helper function: return key of min value for an integer table
--

function machine_genstep:min_key(t)
  -- find min value
  local lowest_val = t[1]
  local lowest_val_index = 1
  for k,v in pairs(t) do
    if t[k] < lowest_val then
      lowest_val_index = k
      lowest_val = t[k]
    end
  end

  return lowest_val_index
end

-- shift_pattern_down
--
-- shift pattern down by 1 octave one note at a time
--

function machine_genstep:shift_pattern_down(m, num)
  local p = self.m.note_patterns[num]

  -- find highest note
  local highest_note= 0
  for i=1, self.m.pattern_length do
    if p.note[i] > highest_note then highest_note = p.note[i] end
  end

  -- find lowest note
  local lowest_note= 128
  for i=1, self.m.pattern_length do
    if p.note[i] < lowest_note then lowest_note = p.note[i] end
  end

  -- cascading transposition
  -- handles patterns that span 2 octaves... anything wider will start to fold
  -- look ahead for collisions (depth 1) and slide the target down an octave
  for i=1, self.m.pattern_length do
    if p.note[i] == (highest_note - 12) then p.note[i] = p.note[i] - 12  end
  end

  -- transpose all instances of the highest note down one octave, if possible
  if (highest_note + p.offset) > p.shift_floor then
    for i=1, self.m.pattern_length do
      if p.note[i] == highest_note then p.note[i] = p.note[i] - 12 end
    end
  end

  -- if the average pitch < pattern offset root, also transpose offset
  -- and scale the entire pattern
  if ((highest_note + lowest_note) / 2 + p.offset) < p.offset then
    p.offset = p.offset - 12
    for i=1, self.m.pattern_length do
      p.note[i] = p.note[i] + 12
    end
  end

end

-- define_begin
--
-- start defining new root note table
--

function machine_genstep:define_begin()
  self.root_temp.offset = 0
  self.root_temp.notes = {}
  self.root_temp.length = 0
end


-- define_input_scale
--
-- input to the new root note table
--

function machine_genstep:define_input_scale(note, vel)
  if self.root_temp.length == 0 then -- first note is offset
    self.root_temp.offset = note
    self.root_temp.notes = {0}
    self.root_temp.length = 1
  else
    note = note - self.root_temp.offset
    -- table must not have duplicates - only insert new notes
    local has_note = false
    for i, val in ipairs(self.root_temp.notes) do
        if note == val then has_note = true end
    end
    if has_note == false then
      table.insert(self.root_temp.notes, note)
      self.root_temp.length = #self.root_temp.notes
    end
  end
end


-- define_input_step
--
-- input to the current pattern during edit mode
--

function machine_genstep:define_input_step(midinote, midivel)
  local np = self.m.note_patterns[self.m.seq_note_pattern]
  local tp = self.m.trig_patterns[self.m.seq_trig_pattern]
  local s = self.m.seq_current_step

  -- udpate the note and trig sequences
  tp.probability[s] = 1.0
  tp.velocity[s] = midivel / 127
  np.note[s] = midinote - np.offset

  -- update the scale
 end


-- define_commit
--
-- write the note table from temp to permanent
--

function machine_genstep:define_commit()
  local newdef = false

  if self.root_temp.length > 1 then -- input at least the root and one note
    newdef = true
    table.sort(self.root_temp.notes)
    self.root.offset = self.root_temp.offset
    self.root.notes = {}
    for i, val in ipairs(self.root_temp.notes) do
      self.root.notes[i] = self.root_temp.notes[i]
    end
    self.root.length = #self.root.notes
  end

  -- reset for the next edit
  self.root_temp.length = 0
  self.root_temp.notes = {}
  self.root_temp.offset = 0

return newdef
end

-- shift_pattern_up
--
-- shift pattern up by 1 octave one note at a time
--

function machine_genstep:shift_pattern_up(m, num)
  local p = self.m.note_patterns[num]

  -- find highest note
  local highest_note= 0
  for i=1, self.m.pattern_length do
    if p.note[i] > highest_note then highest_note = p.note[i] end
  end

  -- find lowest note
  local lowest_note= 128
  for i=1, self.m.pattern_length do
    if p.note[i] < lowest_note then lowest_note = p.note[i] end
  end

  -- cascading transposition
  -- handles patterns that span 2 octaves... anything wider will start to fold
  -- look ahead for collisions (depth 1) and slide the target up an octave
  for i=1, self.m.pattern_length do
    if p.note[i] == (lowest_note + 12) then p.note[i] = p.note[i] + 12 end
  end

  -- transpose all instances of the lowest note and up one octave, if possible
  if (lowest_note + p.offset) <= p.shift_ceiling then
    for i=1, self.m.pattern_length do
      if p.note[i] == lowest_note then p.note[i] = p.note[i] + 12 end
    end
  end

  -- if the average pitch > pattern offset root, also transpose offset
  -- and scale the entire pattern
  if ((highest_note + lowest_note) / 2 + p.offset) > p.offset then
    p.offset = p.offset + 12
    for i=1, self.m.pattern_length do
      p.note[i] = p.note[i] - 12
    end
  end

end

-- midi note to string
--
-- creates a printable note label from midi note #s
--
function machine_genstep:note_to_str(note_num)
  local s = self.note_str[note_num % 12 + 1]..(math.floor(note_num/12))
  return s
end

-- redraw
--
-- handle norns screen updates
--

function machine_genstep:redraw()

  local np = self.m.note_patterns[self.m.seq_note_pattern]
  local tp = self.m.trig_patterns[self.m.seq_trig_pattern]
  local w = math.floor(128 / self.m.pattern_length) -- width of a note rect

  -- display seq seq_state
  screen.level(15)
  screen.move(0,10)
  screen.font_size(8)
  if self.m.seq_state == 0 then
    if self.m.scale_definition_mode == true then screen.text("def") else screen.text("edit") end
    screen.move(32,10)
    screen.level(5)
    screen.text_center(self.m.seq_current_step.."/"..self.m.pattern_length)
  elseif self.m.seq_state == 1 then
    screen.text("play")
  elseif self.m.seq_state == 2 then
    screen.text("rec")
  end

  -- display seq play mode
  screen.level(15)
  screen.move(64, 55)
  screen.text_center("algo: "..self.play_mode_labels[self.m.seq_play_mode])

  if self.m.seq_state == 0 then -- edit/def modes
    -- display pattern selections
    screen.level(15)
    screen.move(128, 10)
    screen.text_right("pat "..self.m.seq_note_pattern..":"..self.m.seq_trig_pattern)
  else -- play/rec modes
    -- display time division
    screen.level(15)
    screen.move(128, 10)
    screen.text_right(self.time_divisions_str[self.m.seq_time_division])
  end

  -- display root note set
  screen.level(5)
  screen.move(56,10)
  if self.m.scale_definition_mode == true then
    screen.text_center(self:note_to_str(self.root_temp.offset))
    screen.move(72,10)
    screen.text_center(self.root_temp.length.. "n")
  else
    screen.text_center(self:note_to_str(self.root.offset))
    screen.move(72,10)
    screen.text_center(self.root.length.. "n")
  end

  -- display note sequence
  screen.level(5)
  screen.move(1, 32)
  screen.line(128,32)
  screen.stroke()
  for s = 1, self.m.pattern_length do
    if s == self.m.seq_current_step then screen.level(15) else screen.level(5) end
    screen.rect((s-1)*w+1, 32, w-1, np.note[s] * -1)
    if s == self.m.seq_current_step then screen.fill() else screen.stroke() end
  end

  -- display trig sequence
  for s = 1, self.m.pattern_length do
    if s == self.m.seq_current_step then
      screen.level(15)
      screen.move((s-1)*w+1, 58)
      screen.line(s*w-1, 58)
      screen.stroke()
    end

    if s == self.m.seq_current_step then screen.level(15) else screen.level(5) end
    if tp.probability[s] == 1 then
      screen.rect((s-1)*w+1, 59, w-1, 5)
      screen.fill()
    elseif tp.probability[s] > 0 then
      screen.rect((s-1)*w+1, 60, w-1, 4)
      screen.stroke()
    end
  end
end

-- a.delta
--
--- process arc encoder inputs
--

function machine_genstep:arc_delta(n, d)

  if self.k1_shift == false then

    -- enc 1: slide - measure relative changes to shift
    if n ==1 then
      self.m.ctl_slide = self.m.ctl_slide + d / 25

      if self.m.ctl_slide > 1 then
        self:shift_pattern_up(m, self.m.seq_note_pattern)
        self.m.ctl_slide = 0
      elseif self.m.ctl_slide < -1 then
        self:shift_pattern_down(m, self.m.seq_note_pattern)
        self.m.ctl_slide = 0
      end
    end

    if self.m.seq_state == 1 then -- play mode
      -- enc 2: selects note pattern
      if n == 2 then
        params:delta(self.param_prefix.."_seq_note_pattern", d)
          if self.machine_foreground == true then redraw() end
      end

      -- enc 3: selects trig pattern
      if n == 3 then
        params:delta(self.param_prefix.."_trig_note_pattern", d)
        if self.machine_foreground == true then redraw() end
      end
    elseif self.m.seq_state == 0 then -- edit mode
      -- enc 2: selects the note
      if n == 2 then
        self.enc2_delta = self.enc2_delta + d / 25

        if self.enc2_delta > 1 then
          self:seq_edit_note(m, 1)
          self:seq_edit_retrig_note(m)
          self.enc2_delta = 0
        elseif self.enc2_delta < -1 then
          self:seq_edit_note(m, -1)
          self:seq_edit_retrig_note(m)
          self.enc2_delta = 0
        end
        if self.machine_foreground == true then redraw() end
      end

      -- enc 3: selects the trig
      if n == 3 then
        self.enc3_delta = self.enc3_delta + d / 5

        if self.enc3_delta > 1 then
          self:seq_edit_trig(m, .01)
          self.enc3_delta = 0
        elseif self.enc3_delta < -1 then
          self:seq_edit_trig(m, -.01)
          self.enc3_delta = 0
        end
      end
      if self.machine_foreground == true then redraw() end
    end

    -- enc 4: scrub through sequence when playback stopped
    if self.m.seq_state == 0 and n == 4 then
      self.m.ctl_scrub = self.m.ctl_scrub + d / 50

      if self.m.ctl_scrub > 1 then
        self.m.ctl_scrub = 0
        -- incr to next step + loop
        if self.m.seq_current_step >= self.m.pattern_length then self.m.seq_current_step = 1 else self.m.seq_current_step = self.m.seq_current_step + 1 end
        self:seq_play_next_note(m)
      elseif self.m.ctl_scrub < -1 then
        self.m.ctl_scrub = 0
        if self.m.seq_current_step == 1 then self.m.seq_current_step = self.m.pattern_length else self.m.seq_current_step = self.m.seq_current_step - 1 end
        self:seq_play_next_note(m)
      end
    end
  else -- shift functions
    -- enc1: key shift
    if n == 1 then
      self.m.ctl_length_factor = util.clamp(self.m.ctl_length_factor + d/1000, 0, 1)
      self.m.seq_length_factor = util.clamp(math.floor((self.m.ctl_length_factor * self.num_length_factors) + 1), 1, self.num_length_factors)
    end

    -- enc 2: chaos
    if n == 2 then
      params:delta(self.param_prefix.."_seq_chaos", d)
    end

    -- enc 3: activity
    if n == 3 then
      params:delta(self.param_prefix.."_seq_activity", d)
    end

    -- enc4: time division
    if n == 4 then
      params:delta(self.param_prefix.."_seq_time_division", d)

--      self.m.ctl_time_division = util.clamp(self.m.ctl_time_division + d/1000, 0, 1)
--      self.m.seq_time_division = util.clamp(math.floor((self.m.ctl_time_division * num_time_divisions) + 1), 1, num_time_divisions)
      if self.machine_foreground == true then redraw() end
    end
  end
end

-- arc_redraw_handler
--
-- refresh arc leds, driven by fast metro
--

function machine_genstep:arc_redraw(a)
  local val
  local np = self.m.note_patterns[self.m.seq_note_pattern]
  local tp = self.m.trig_patterns[self.m.seq_trig_pattern]

  if self.k1_shift == false then

    -- enc1: pattern notes + shifting
    for i=1, self.m.pattern_length do
      a:led(1, math.floor((np.note[i]+np.offset)/2)+1, 5)
    end

    -- enc1: active notes
    for n, _ in pairs(self.m.active_note) do
      if self.m.active_note[n] == true then
        a:led(1, math.floor(tonumber(n)/2)+1, 15)
      end
    end

    if self.m.seq_state == 1 then -- play mode
      -- enc2: note pattern param
      val = self.m.seq_note_pattern - 1
      a:segment(2, (val / self.m.num_note_patterns * 2 * math.pi), ((val + 1) / self.m.num_note_patterns * 2 * math.pi), 15)

      -- enc3: trig pattern param
      val = self.m.seq_trig_pattern - 1
      a:segment(3, (val / self.m.num_trig_patterns * 2 * math.pi), ((val + 1) / self.m.num_trig_patterns * 2 * math.pi), 15)
    elseif self.m.seq_state == 0 then -- edit mode
        -- enc2: note offset
        a:led(2, math.floor((np.note[self.m.seq_current_step])+32), 15)

        -- enc3: trig probability
        local prob = tp.probability[self.m.seq_current_step]
        if prob == 1 then prob = .9999 end -- display a full segment ring
        a:segment(3, 0, prob * 2 * math.pi, 15)
    end

     -- enc4: global play head
    a:segment(4, ((self.m.seq_current_step - 1) / self.m.pattern_length * 2 * math.pi), ((self.m.seq_current_step) / self.m.pattern_length * 2 * math.pi), 15)

  else -- shift function
    -- enc1: key shift param
    val = self.m.seq_length_factor - 1
    a:segment(1, (val / self.num_length_factors * 2 * math.pi) - math.pi, ((val + 1) / self.num_length_factors * 2 * math.pi) - math.pi, 15)

    -- enc2: chaos param
    a:segment(2, 0, (self.m.seq_chaos * 0.999 * 2 * math.pi), 5)
    a:led(2, 33, 15)
    a:led(2, 49, 15)

    -- enc3: activity param
    a:segment(3, 0, (self.m.seq_activity * 0.999 * 2 * math.pi), 15)

    -- enc4: time division  param
    val = self.m.seq_time_division - 1
    a:segment(4, (val / self.num_time_divisions * 2 * math.pi), ((val + 1) / self.num_time_divisions * 2 * math.pi), 15)
  end
end

-- add_params
--
-- add this machine's params to paramset
--
function machine_genstep:add_params()

  -- SEQUENCER AND MIDI PARAMS
  params:add_group("genstep"..self.machine_num.." SETTINGS", 5 )

  cs_PATTERN_LEN = controlspec.new(1, self.max_pattern_length, 'lin' ,1 ,32 ,'' ,0.01 , false)
  params:add{type="control", id=self.param_prefix.."_pattern_length", name="pattern length", controlspec=cs_PATTERN_LEN, action=function(x) self.m.pattern_length=x end}

  cs_MIDI_CH = controlspec.new(1, 16, 'lin' ,1 ,1 ,'' ,0.01 , false)
  params:add{type="control", id=self.param_prefix.."_midi_out", name="midi out channel", controlspec=cs_MIDI_CH, action=function(x) self.midi_out_channel=x end}
  params:add{type="control", id=self.param_prefix.."_midi_in", name="midi in channel", controlspec=cs_MIDI_CH, action=function(x) self.midi_in_channel=x end}

  params:add_option(self.param_prefix.."_midi_thru", "midi thru", {"off","on"}, 1)
  params:set_action(self.param_prefix.."_midi_thru", function(x) if (x-1) == 0 then self.midi_thru=false else self.midi_thru=true end end)

  cs_MIDI_PGM = controlspec.new(1, 128, 'lin' ,1 ,1 ,'' ,0.01 , false)
  params:add{type="control", id=self.param_prefix.."_midi_pgm", name="midi program", controlspec=cs_MIDI_PGM, action=function(x) self.midi_out_device:program_change(x-1, self.midi_out_channel) end}


  -- SEQUENCER DATA
  params:add_group("gs"..self.machine_num.."data", 6 + self.m.num_trig_patterns + self.m.num_note_patterns)

  cs_PATTERN_SEL = controlspec.new(1, 16, 'lin' ,1 ,1 ,'' ,0.001 , true)
  params:add{type="control", id=self.param_prefix.."_seq_note_pattern", name="note pattern", controlspec=cs_PATTERN_SEL, action=function(x) self.m.seq_note_pattern=x end}
  params:add{type="control", id=self.param_prefix.."_trig_note_pattern", name="trig pattern", controlspec=cs_PATTERN_SEL, action=function(x) self.m.seq_trig_pattern=x end}

  cs_PATTERN_TIMEDIV = controlspec.new(1, #self.time_divisions, 'lin' ,1 ,2 ,'' ,0.001 , false)
  params:add{type="control", id=self.param_prefix.."_seq_time_division", name="time division", controlspec=cs_PATTERN_TIMEDIV, action=function(x) self.m.seq_time_division=x end}

  cs_SEQ_ACTIVITY = controlspec.new(0, 1, 'lin' ,0.001 ,1.0 ,'' ,0.001 , false)
  params:add{type="control", id=self.param_prefix.."_seq_activity", name="activity prob", controlspec=cs_SEQ_ACTIVITY, action=function(x) self.m.seq_activity=x end}

  cs_SEQ_CHAOS = controlspec.new(0, 1, 'lin' ,0.001 ,0 ,'' ,0.001 , false)
  params:add{type="control", id=self.param_prefix.."_seq_chaos", name="chaos level", controlspec=cs_SEQ_CHAOS, action=function(x) self.m.seq_chaos=x end}

  -- root scale
  params:add{type="text", id=self.param_prefix.."_root", name="root", action=function(x) end}

  -- pattern tables
  for i=1,self.m.num_trig_patterns do
    params:add{type="text", id=self.param_prefix.."_tp"..i, name="tp"..i, action=function(x) end}
  end
  for i=1,self.m.num_note_patterns do
    params:add{type="text", id=self.param_prefix.."_np"..i, name="np"..i, action=function(x) end}
  end
end

-- export_data
--
-- write patterns to paramset
--
function machine_genstep:export_packed_params()

  params:set(self.param_prefix.."_root", self:root_notes_to_str(self.root))

  for i=1,self.m.num_trig_patterns do
    params:set(self.param_prefix.."_tp"..i, self:trig_pattern_to_str(self.m.trig_patterns[i]))
  end

  for i=1,self.m.num_note_patterns do
    params:set(self.param_prefix.."_np"..i, self:note_pattern_to_str(self.m.note_patterns[i]))
  end
end

-- trig_pattern_to_str
--
-- for storing pattern data in a param text field
--
function machine_genstep:trig_pattern_to_str(tp)
  local str = ""
  local step

  for i = 1, self.m.pattern_length do
    step = math.floor(tp.probability[i]*1000)..":"..math.floor(tp.velocity[i]*1000)..":"..tp.duration[i]
    str = str..step
    if i < self.m.pattern_length then str = str.."," end
  end
  return str
end

-- note_pattern_to_str
--
-- for storing pattern data in a param text field
--
function machine_genstep:note_pattern_to_str(np)
  local str = ""
  local step

  -- second param used to be key shift - left in for reverse compatibility
  str = np.offset..":0:"..np.shift_floor..":"..np.shift_ceiling..","

  for i = 1, self.m.pattern_length do
    str = str..np.note[i]
    if i < self.m.pattern_length then str = str.."," end
  end
  return str
end

-- root_to_str
--
-- for storing pattern data in a param text field
--
function machine_genstep:root_notes_to_str(r)
  local str = ""

  str = r.offset..","

  for i = 1, #r.notes do
    str = str..r.notes[i]
    if i < #r.notes then str = str.."," end
  end
  return str
end

-- import_data
--
-- read packed data from paramset
--
function machine_genstep:import_packed_params()
  local str

  -- only do this if there is previously saved data to load
  str = params:get(self.param_prefix.."_root")
  if string.len(str) > 0 then
    self:str_to_root_notes(str, self.root)
  end

  -- only do this if there is previously saved data to load
  str = params:get(self.param_prefix.."_tp1")
  if string.len(str) > 0 then
    for i=1,self.m.num_trig_patterns do
      str = params:get(self.param_prefix.."_tp"..i)
      self:str_to_trig_pattern(str, self.m.trig_patterns[i])
    end
    for i=1,self.m.num_note_patterns do
      str = params:get(self.param_prefix.."_np"..i)
      self:str_to_note_pattern(str, self.m.note_patterns[i])
    end
  end
end

-- str_to_trig_pattern
--
-- for reading pattern from param text field
--
function machine_genstep:str_to_trig_pattern(str, tp)
  local params = self:splitstr(str, ",")
  local step_vals

  for i = 1, self.m.pattern_length do
    step_vals = self:splitstr(params[i], ":")
    tp.probability[i] = tonumber(step_vals[1]) / 1000
    tp.velocity[i] = tonumber(step_vals[2]) / 1000
    tp.duration[i] = tonumber(step_vals[3])
  end
end

-- str_to_note_pattern
--
-- for reading pattern data from a param text field
--
function machine_genstep:str_to_note_pattern(str, np)
  local values = self:splitstr(str, ",")

  -- first value is header pack of some scaling vars
  local header = self:splitstr(values[1], ":")
  np.offset = tonumber(header[1])
  --np.key_shift = tonumber(header[2]) -- left in for reverse compatibility
  np.shift_floor = tonumber(header[3])
  np.shift_ceiling = tonumber(header[4])

  for i = 1, self.m.pattern_length do
    np.note[i] = tonumber(values[i + 1])
  end
end

-- str_to_root_notes
--
-- for reading root note data from a param text field
--
function machine_genstep:str_to_root_notes(str)
  local values = self:splitstr(str, ",")

  -- first value is header pack of some scaling vars
  self.root.offset = tonumber(values[1])

  for i = 1, (#values-1) do
    self.root.notes[i] = tonumber(values[i+1])
  end
end

-- splitstr
--
-- utility function
--

function machine_genstep:splitstr(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t={}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end


return machine_genstep
