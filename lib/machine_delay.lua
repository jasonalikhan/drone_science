-- delay machine
-- @classmod machine_delay

local machine_delay = {}

--- constructor
function machine_delay:new()
  local o = {}
  self.__index = self
  setmetatable(o, self)

  -- user interface stuff
  o.machine_foreground = false -- true if machine is in foreground (in view)
  o.k1_shift = false -- for secondary functions

  o.fx_params = {"fx_delay_time", "fx_delay_damp", "fx_delay_size", "fx_delay_diff", "fx_delay_fdbk", "fx_delay_mod_depth", "fx_delay_mod_freq", "fx_delay_volume"}
  o.fx_labels = {"time", "damp", "size", "diff", "fdbk", "mod depth", "mod_freq", "fx volume"}

  o.curr_fx_param = 1

  return o
end

-- init
--
-- main script init
--

function machine_delay:init()
  -- nothing
end

-- cleanup
--
-- main script cleanup
--
function machine_delay:cleanup()
end

-- foreground
--
-- call when machine is in foregound
-- visible on screen and taking encoder input
--
function machine_delay:foreground()
  self.machine_foreground = true
end

-- background
--
-- call when machine if offscreen
--
function machine_delay:background()
  self.machine_foreground = false
end

-- key
--
-- process norns keys
--

function machine_delay:key(n, z)

  -- process k1 as a shift key for arc encoder input
  if n == 1 then
    if z == 1 then
      self.k1_shift = true
    elseif z == 0 then
      self.k1_shift = false
    end
  end

  if self.machine_foreground == true then redraw() end
end

-- midi_message_handler
--
-- process midi messages
--
function machine_delay:midi_message_handler(msg)
  -- do nothing
end

-- enc
--
-- process norns encoders
--

function machine_delay:enc(n, d)
  -- nothing to do yet

  if n == 2 then
    self.curr_fx_param = util.clamp(self.curr_fx_param + d, 1, #self.fx_params)
  end

  if n == 3 then
    params:delta(self.fx_params[self.curr_fx_param], d / 10)
  end

  if self.machine_foreground == true then redraw() end
end

-- redraw
--
-- handle norns screen updates
--

function machine_delay:redraw()
  local offs
  local display
  local val

  screen.level(15)
  screen.move(1,10)
  screen.font_size(8)
  screen.text("delay effect")

  screen.move(0, 40)
  screen.text(self.fx_labels[self.curr_fx_param])
  screen.move(128,40)
  val = string.format("%.3f",params:get(self.fx_params[self.curr_fx_param]))
  screen.text_right(val)
end


-- a.delta
--
--- process arc encoder inputs
--

function machine_delay:arc_delta(n, d)

end

-- arc_redraw_handler
--
-- refresh arc leds, driven by fast metro
--

function machine_delay:arc_redraw(a)

end

-- add_params
--
-- add this machine's params to paramset
--
function machine_delay:add_params()
  params:add_group("DELAY SETTINGS", 8)

  params:add_control("fx_delay_time", "delay time", controlspec.new(0.0, 60.0, "lin", 0.01, 2.00, ""))
  params:set_action("fx_delay_time", function(value) engine.delay_time(value) end)
  -- delay size
  params:add_control("fx_delay_size", "delay size", controlspec.new(0.5, 10.0, "lin", 0.01, 2.00, ""))
  params:set_action("fx_delay_size", function(value) engine.delay_size(value) end)
  -- dampening
  params:add_control("fx_delay_damp", "delay damp", controlspec.new(0.0, 1.0, "lin", 0.01, 0.10, ""))
  params:set_action("fx_delay_damp", function(value) engine.delay_damp(value) end)
  -- diffusion
  params:add_control("fx_delay_diff", "delay diff", controlspec.new(0.0, 1.0, "lin", 0.01, 0.707, ""))
  params:set_action("fx_delay_diff", function(value) engine.delay_diff(value) end)
  -- feedback
  params:add_control("fx_delay_fdbk", "delay fdbk", controlspec.new(0.00, 1.0, "lin", 0.01, 0.20, ""))
  params:set_action("fx_delay_fdbk", function(value) engine.delay_fdbk(value) end)
  -- mod depth
  params:add_control("fx_delay_mod_depth", "delay mod depth", controlspec.new(0.0, 1.0, "lin", 0.01, 0.00, ""))
  params:set_action("fx_delay_mod_depth", function(value) engine.delay_mod_depth(value) end)
  -- mod rate
  params:add_control("fx_delay_mod_freq", "delay mod freq", controlspec.new(0.0, 10.0, "lin", 0.01, 0.10, "hz"))
  params:set_action("fx_delay_mod_freq", function(value) engine.delay_mod_freq(value) end)
  -- delay output volume
  params:add_control("fx_delay_volume", "delay output volume", controlspec.new(0.0, 1.0, "lin", 0, 1.0, ""))
  params:set_action("fx_delay_volume", function(value) engine.delay_volume(value) end)
end

-- export_data_to_params
--
-- write stuff to paramset
--
function machine_delay:export_packed_params()
  -- do nothing
end

-- import_data
--
-- read packed data from paramset
--
function machine_delay:import_packed_params()
    -- to do
end

return machine_delay
