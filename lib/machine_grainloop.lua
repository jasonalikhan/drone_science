-- grainloop synth
-- @classmod machine_grainloop

local machine_grainloop = {}

--- constructor
function machine_grainloop:new(machine_num,voice_num)
  local o = {}
  self.__index = self
  setmetatable(o, self)

  o.param_prefix = "gl"..machine_num
  o.v = voice_num -- global supercollider voice (synth supports 4 concurrent)
  o.machine_num = machine_num
  o.midi_in_channel = 1 -- input: assume first midi channel

  -- user interface stuff
  o.machine_foreground = false -- true if machine is in foreground (in view)
  o.k1_shift = false -- for secondary functions
  o.k2_state = 0 -- for setting loop start-end positions
  o.live_mode = false -- play from files by default
  o.live_buffer_state = 0 -- 0 play, 1 armed, 2 record

  -- synth params
  o.synth_param_ids = {"gain", "send", "jitter", "pitch", "pitch_rand", "spread", "pan", "pan_rand", "size", "density", "density_mod_amt", "envscale", "lp_freq", "lp_q", "hp_freq", "hp_q"}
  o.synth_param_names = {"gain", "send", "jitter", "pitch", "pitch random", "spread", "pan", "pan random", "grain size", "density", "density mod amt", "envelope", "lp freq", "lp q", "hp freq", "hp q"}
  o.curr_synth_param = 1
  o.voice_position = -1
  o.voice_level = 0
  o.arc3val_synth = 0

  -- play algorithms
  o.algo_names = {"linear playback", "freeze", "subloop fw", "subloop bf", "subloop glitch", "tides", "midikeys", "off"}
  o.curr_algo = 1
  o.prev_algo = 1
  o.algo_param = 0
  o.algo_metro = nil
  o.algo_rate = 10 -- 10 hz
  o.algo_metro = metro.init(function(c) o:algo_process(c) end, 1 / o.algo_rate)
  o.curr_algo_clock = 0
  o.next_algo_event = 0
  o.algo_tide_duration = 0
  o.prev_speed = 0
  o.loop_start = 0
  o.loop_end = 1
  o.last_note = 0

  return o
end

-- get_sample_name
--
-- UI helper function
--
function machine_grainloop:get_sample_name()
  -- strips the path and extension from filenames
  -- if filename is over 15 chars, returns a folded filename
  local long_name = string.match(params:get(self.param_prefix.."sample"), "[^/]*$")
  local short_name = string.match(long_name, "(.+)%..+$")
  if short_name == nil then short_name = "(load file)" end
  if string.len(short_name) >= 15 then
    return string.sub(short_name, 1, 4) .. '...' .. string.sub(short_name, -4)
  else
    return short_name
  end
end

-- init
--
-- main script init
--

function machine_grainloop:init()

  -- engine param polls
    local phase_poll = poll.set('phase_'..self.v, function(pos) self.voice_position = pos end)
    phase_poll.time = 0.025
    phase_poll:start()

    local level_poll = poll.set('level_'..self.v , function(lvl) self.voice_level = lvl end)
    level_poll.time = 0.05
    level_poll:start()

    self.algo_metro:start()
end

-- cleanup
--
-- main script cleanup
--
function machine_grainloop:cleanup()

end

-- foreground
--
-- call when machine is in foregound
-- visible on screen and taking encoder input
--
function machine_grainloop:foreground()
  self.machine_foreground = true
end

-- background
--
-- call when machine if offscreen
--
function machine_grainloop:background()
  self.machine_foreground = false
end

-- midi_data_handler
--
-- process raw midi input
--
function machine_grainloop:midi_data_handler(data)
  local msg = midi.to_msg(data)
  if (msg.ch == self.midi_in_channel) and (self.machine_foreground == true) then
    self:midi_message_handler(msg)
  end
end

-- midi_message_handler
--
-- process midi messages
--
function machine_grainloop:midi_message_handler(msg)

  -- note on
  if msg.type == "note_on" then
    if (self.curr_algo == 7) then self:noteon(msg.note, msg.vel) end

  -- note off
  elseif msg.type == "note_off" then
    if (self.curr_algo == 7) then self:noteoff(msg.note) end

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

function machine_grainloop:noteon(note_num, note_vel)
  params:set(self.param_prefix.."pitch", note_num - 60)
  self.last_note = note_num
  if self.curr_algo == 7 then params:set(self.param_prefix.."play", "2") end
  if self.machine_foreground == true then redraw() end
end

-- note off
--
-- play a note to midi and engine
--
function machine_grainloop:noteoff(note_num)
  --if (self.curr_algo == 7) and (self.last_note == note_num) then params:set(self.param_prefix.."play", "1") end
  --if self.machine_foreground == true then redraw() end
end

-- key
--
-- process norns keys
--

function machine_grainloop:key(n, z)

  -- process k1 as a shift key for arc encoder input
  if n == 1 then
    if z == 1 then
      self.k1_shift = true
    elseif z == 0 then
      self.k1_shift = false
    end
  end

  if n == 2 and z == 1 then
    if self.k1_shift == false then
      if self.live_mode == false or (self.live_mode == true and self.live_buffer_state == 0) then
        self.loop_start = self.voice_position
      else
        -- cancel and re-arm
        self.live_buffer_state = 0
      end
    else
      self.live_mode = false
      engine.file_mode(self.v)
    end
  end

  if n == 2 and z == 0 then
    if self.k1_shift == false then
      if self.live_mode == false or (self.live_mode == true and self.live_buffer_state == 0) then
        self.loop_end = self.voice_position
      end
    end
  end

  if n == 3 and z == 1 then
    if self.k1_shift == false then
      if self.live_mode == true then
        -- toggle through record + play states
        if self.live_buffer_state == 0 then
          self.live_buffer_state = 1 -- go to armed state
        elseif self.live_buffer_state == 1 then
          engine.live_buffer_record_start(self.v, 30) -- start recording 15ms fadein/out
          self.live_buffer_state = 2
        elseif self.live_buffer_state == 2 then
          -- reset some params post recording
          engine.live_buffer_record_end(self.v)
          self.curr_algo = 1
          params:set(self.param_prefix.."speed", 100)
          params:set(self.param_prefix.."pitch", 0)
          self.live_buffer_state = 0 -- return to play state
        end
      end
    else
      -- clear live buffer
      self.live_buffer_state = 0
      self.live_mode = true
      engine.live_mode(self.v)
    end
  end

  if self.machine_foreground == true then redraw() end
end

-- enc
--
-- process norns encoders
--

function machine_grainloop:enc(n, d)

  if n == 2 then
    self.curr_algo = util.clamp(self.curr_algo + d, 1, #self.algo_names)
    params:set(self.param_prefix.."algo_num", self.curr_algo, 0)
  end

  if n == 3 then
    params:delta(self.param_prefix.."self.algo_param", d / 10)
  end

  if self.machine_foreground == true then redraw() end
end

-- redraw
--
-- handle norns screen updates
--

function machine_grainloop:redraw()
  local gate_state = params:get(self.param_prefix.."play")
  local event_countdown

  screen.level(15)
  screen.move(1,10)
  screen.font_size(8)
  if self.live_mode == false then
    screen.text(self:get_sample_name())
  else
    if self.live_buffer_state == 0 then
      screen.text("live buffer")
    elseif self.live_buffer_state == 1 then
      screen.text("live buffer :: ARMED")
    elseif self.live_buffer_state == 2 then
      screen.text("live buffer :: RECORDING")
    end
  end

  if self.live_mode == true and (self.live_buffer_state == 1 or self.live_buffer_state == 2) then
    -- is recording in live mode
  else
    if self.curr_algo == 6 then
      screen.move(25, 60)
      screen.level(5)
      if gate_state == 2 then
        screen.text("high")
        event_countdown = math.floor(100 * (self.next_algo_event - self.curr_algo_clock) / self.algo_tide_duration)
      else
        screen.text(" low")
        event_countdown = 100 - math.floor(100 * (self.next_algo_event - self.curr_algo_clock) / self.algo_tide_duration)
      end
      if self.next_algo_event ~= 0 then
        screen.move(45, 60)
        screen.text(event_countdown)
      end
    end

    screen.level(5)
    screen.move(1, 25)
    screen.text("play speed")
    screen.level(15)
    screen.move(1, 35)
    screen.text(math.floor(params:get(self.param_prefix.."speed")).."%")

    screen.level(5)
    screen.move(128, 25)
    screen.text_right(self.synth_param_names[self.curr_synth_param])
    screen.level(15)
    screen.move(128, 35)
    screen.text_right(string.format("%.3f", params:get(self.param_prefix..self.synth_param_ids[self.curr_synth_param])))

    screen.level(5)
    screen.move(1, 50)
    screen.text("algo")
    screen.level(15)
    screen.move(1, 60)
    screen.text(self.algo_names[self.curr_algo])

    screen.level(5)
    screen.move(128, 50)
    screen.text_right("algo param")
    screen.level(15)
    screen.move(128, 60)
    screen.text_right(string.format("%.3f", params:get(self.param_prefix.."self.algo_param")))
  end
end


-- a.delta
--
--- process arc encoder inputs
--

function machine_grainloop:arc_delta(n, d)

  -- slide loop points around in loop algo mode
  -- or update play pos value in all other modes
  if n == 1 then
    if (self.curr_algo == 3) or (self.curr_algo == 4) then -- in loop modes
      self.loop_start = math.fmod(self.loop_start + d / 1000, 1.0)
      self.loop_end = math.fmod(self.loop_end + d / 1000, 1.0)
    else -- all other algos
      params:delta(self.param_prefix.."pos", d)
    end
  end

  -- update speed value
  if n == 2 then params:delta(self.param_prefix.."speed", d) end

  -- select param to edit
  if n == 3 then
    self.arc3val_synth = util.clamp(self.arc3val_synth + d / 100, 1, #self.synth_param_ids)
    self.curr_synth_param = math.floor(self.arc3val_synth)
  end

  -- update param value
  if n == 4 then params:delta(self.param_prefix..self.synth_param_ids[self.curr_synth_param], d / 10) end

  if self.machine_foreground == true then redraw() end

end

-- arc_redraw_handler
--
-- refresh arc leds, driven by fast metro
--

function machine_grainloop:arc_redraw(a)
  local val

  -- encoder 1: position
  val = self.voice_position * 2 * math.pi
  a:segment(1, val - 0.1, val + 0.1, 15)
  a:led(1, math.floor(self.loop_start * 64) + 1, 15)
  a:led(1, math.floor(self.loop_end * 64) + 1, 15)

  -- encoder 2: speed
  local speed = math.floor(params:get(self.param_prefix.."speed"))
  if speed == 0 then
    a:segment(2, -.25, .25, 15)
  elseif speed > 0 then
    a:segment(2, 0, (speed / 300 * math.pi), 15)
  elseif speed < 0 then
    a:segment(2, math.pi*2 + (speed / 300 * math.pi), math.pi*2 * 0.999, 15)
  end

  -- encoder 3: param
  a:segment(3, ((self.curr_synth_param - 1) / #self.synth_param_ids * 2 * math.pi), (self.curr_synth_param / #self.synth_param_ids * 2 * math.pi), 15)

  -- encoder 4: value

end

-- add_params
--
-- add this machine's params to paramset
--
function machine_grainloop:add_params()
  params:add_group("grainloop"..self.machine_num.." SETTINGS", 22)

  params:add_file(self.param_prefix.."sample", "sample")
  params:set_action(self.param_prefix.."sample", function(file) engine.read(self.v, file) end)

  params:add_option(self.param_prefix.."play", "play", {"off","on"}, 1)
  params:set_action(self.param_prefix.."play", function(x) engine.gate(self.v, x-1) end)

  params:add_control(self.param_prefix.."gain", "gain", controlspec.new(0.0, 1.0, "lin", 0.01, 0.0))
  params:set_action(self.param_prefix.."gain", function(value) engine.gain(self.v, value) end)

  params:add_control(self.param_prefix.."pos", "pos", controlspec.new(0, 1, "lin", 0.0001, 0, "", 0.001, true))
  params:set_action(self.param_prefix.."pos", function(value) engine.pos(self.v, value) end)

  params:add_taper(self.param_prefix.."speed", "speed", -300, 300, 0, 0, "%")
  params:set_action(self.param_prefix.."speed", function(value) engine.speed(self.v, value / 100) end)

  params:add_taper(self.param_prefix.."jitter", "jitter", 0, 5000, 0, 10, "ms")
  params:set_action(self.param_prefix.."jitter", function(value) engine.jitter(self.v, value / 1000) end)

  params:add_taper(self.param_prefix.."size", "size", 1, 500, 100, 5, "ms")
  params:set_action(self.param_prefix.."size", function(value) engine.size(self.v, value / 1000) end)

  params:add_taper(self.param_prefix.."density", "density", 0, 512, 20, 6, "hz")
  params:set_action(self.param_prefix.."density", function(value) engine.density(self.v, value) end)

  params:add_control(self.param_prefix.."density_mod_amt", "density mod amt", controlspec.new(0, 1, "lin", 0, 0))
  params:set_action(self.param_prefix.."density_mod_amt", function(value) engine.density_mod_amt(self.v, value) end)

  params:add_control(self.param_prefix.."pitch", "pitch", controlspec.new(-36.00, 36.00, "lin", 0.01, 0, "st", 0.001, false))
  params:set_action(self.param_prefix.."pitch", function(value) engine.pitch(self.v, math.pow(0.5, -value / 12)) end)

  params:add_control(self.param_prefix.."pitch_rand", "pitch_rand", controlspec.new(0.0, 1.00, "lin", 0.001, 0))
  params:set_action(self.param_prefix.."pitch_rand", function(value) engine.pitch_rand(self.v, value) end)

  params:add_control(self.param_prefix.."spread", "spread", controlspec.new(0.0, 1.00, "lin", 0.001, 0))
  params:set_action(self.param_prefix.."spread", function(value) engine.spread(self.v, value) end)

  params:add_control(self.param_prefix.."pan", "pan", controlspec.new(-1.00, 1.00, "lin", 0.01, 0))
  params:set_action(self.param_prefix.."pan", function(value) engine.pan(self.v, value) end)

  params:add_control(self.param_prefix.."pan_rand", "pan rand", controlspec.new(0.0, 1.00, "lin", 0.001, 0))
  params:set_action(self.param_prefix.."pan_rand", function(value) engine.pan_rand(self.v, value) end)

  params:add_control(self.param_prefix.."lp_freq", "lpf cutoff", controlspec.new(0.0, 1.0, "lin", 0.01, 1))
  params:set_action(self.param_prefix.."lp_freq", function(value) engine.lp_freq(self.v, value) end)

  params:add_control(self.param_prefix.."lp_q", "lpf q", controlspec.new(0.00, 1.00, "lin", 0.01, 1))
  params:set_action(self.param_prefix.."lp_q", function(value) engine.lp_q(self.v, value) end)

  params:add_control(self.param_prefix.."hp_freq", "hpf cutoff", controlspec.new(0.0, 1.0, "lin", 0.01, 0))
  params:set_action(self.param_prefix.."hp_freq", function(value) engine.hp_freq(self.v, value) end)

  params:add_control(self.param_prefix.."hp_q", "hpf q", controlspec.new(0.00, 1.00, "lin", 0.01, 1))
  params:set_action(self.param_prefix.."hp_q", function(value) engine.hp_q(self.v, value) end)

  params:add_control(self.param_prefix.."send", "delay send", controlspec.new(0.0, 1.0, "lin", 0.01, 0.0))
  params:set_action(self.param_prefix.."send", function(value) engine.send(self.v, value) end)

  params:add_control(self.param_prefix.."envscale", "envelope time", controlspec.new(0.0, 60.0, "lin", 0.01, 0.0))
  params:set_action(self.param_prefix.."envscale", function(value) engine.envscale(self.v, value) end)

  params:add_number(self.param_prefix.."algo_num", "algo num", 1, #self.algo_names, 1, 1)
  params:set_action(self.param_prefix.."algo_num", function(value) self.curr_algo = value end)

  params:add_control(self.param_prefix.."self.algo_param", "algo mod", controlspec.new(0.0, 1.00, "lin", 0.0001, 0))
  params:set_action(self.param_prefix.."self.algo_param", function(value) self.algo_param = value end)
end

-- export_packed_params
--
-- write patterns to paramset
--
function machine_grainloop:export_packed_params()
  -- do nothing
end

-- import_data
--
-- read packed data from paramset
--
function machine_grainloop:import_packed_params()
    -- do nothing
end

-- algo_process
--
-- process handler for algorithmic changes to playback
--
function machine_grainloop:algo_process(c)
  local update_screen = false

  -- SWITCHING ALGOS - exit the algo gracefully by resetting affected params
  if self.prev_algo ~= self.curr_algo then
    if self.prev_algo == 2 then
      params:set(self.param_prefix.."speed", self.prev_speed)
    elseif (self.prev_algo == 3) or (self.prev_algo == 4) or (self.prev_algo == 5) then
      engine.pos_loop(self.v, 0, 0, 0, 0) -- stop looping
    elseif (self.prev_algo == 6) or (self.prev_algo == 7) or (self.prev_algo == 8) then
      params:set(self.param_prefix.."play", "2") -- turn on voice again
    end
  end

  -- ALGO: FREE
  if self.curr_algo == 1 then
    -- do nothing
  elseif self.curr_algo == 2 then
    -- ALGO: FREEZE
    s = params:get(self.param_prefix.."speed")
    if s ~= 0 then
      self.prev_speed = s
      params:set(self.param_prefix.."speed", 0) -- stop playback and freeze
      update_screen = true
    end
  elseif self.curr_algo == 3 then
    -- ALGO: SUBLOOP FORWARD
    if (self.loop_start ~= 0) or (self.loop_end ~= 0) then
      engine.pos_loop(self.v, self.loop_start, self.loop_end, self.algo_param * 4, 1) -- 0 - 4hz
      update_screen = true
    end
  elseif self.curr_algo == 4 then
    -- ALGO: SUBLOOP BACK AND FORTH
    if (self.loop_start ~= 0) or (self.loop_end ~= 0) then
      engine.pos_loop(self.v, self.loop_start, self.loop_end, self.algo_param * 2, 2) -- 0 - 2hz
      update_screen = true
    end
  elseif self.curr_algo == 5 then
    -- ALGO: RANDOMIZED GLITCH SUBLOOPS
    if math.random() > (1 - (.2 * self.algo_param)) then
      self.loop_start = math.random()
      self.loop_end = math.fmod(self.loop_start + (math.random() * self.algo_param * 0.2), 1.0) -- increase size with higher values
      engine.pos_loop(self.v, self.loop_start, self.loop_end, util.linlin(0, 1, 0.01, util.linexp(0, 1, 2.0, 10, self.algo_param), math.random()), 1) -- increase hz w/ higher values
      update_screen = true
    end
  elseif self.curr_algo == 6 then
    -- ALGO: RANDOMIZED WAVES - FADE IN AND OUT DURING PLAYBACK
    self.curr_algo_clock = c
    if c >= self.next_algo_event then
      -- flip the voice state on/off
      local gate_state = params:get(self.param_prefix.."play")
      if gate_state == 2 then
        -- low tide
        params:set(self.param_prefix.."play", "1")
      else
        -- high tide
       params:set(self.param_prefix.."play", "2")
    end
      -- choose timing of next state flip, scaled by algo param, 60 to 1 seconds
      self.algo_tide_duration = math.floor((util.linlin(0, 1, 60, 1, self.algo_param) * self.algo_rate) * util.linlin(0, 1, .8, 1.2, math.random()))
      self.next_algo_event = c + self.algo_tide_duration
    end
    update_screen = true
  elseif self.curr_algo == 8 then
    params:set(self.param_prefix.."play", "1") -- turn off voice
    update_screen = true
  end


  -- keep track of which algo ran for next metro cycle
  self.prev_algo = self.curr_algo

  if self.machine_foreground == true and update_screen == true then redraw() end

end

return machine_grainloop
