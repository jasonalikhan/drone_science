--- event_pattern
-- @classmod event_pattern

local event_pattern = {}

--- constructor
function event_pattern:new()
  local i = {}
  setmetatable(i, self)
  self.__index = self

  i.rec = 0
  i.play = 0
  i.overdub = 0
  i.prev_time = 0
  i.event = {}
  i.time = {}
  i.count = 0
  i.step = 0
  i.time_factor = 1
  i.rec_start_time = 0
  i.rec_end_time = 0
  i.play_start_time = 0
  i.duration = 0
  i.pos = 0

  -- pattern metro
  i.metro = metro.init(function() i:next_event() end,1,1)

  -- 30hz position metro - smooth interpolation of position for display
  i.pos_metro = metro.init(function() if i.play == 1 then i.pos = ((util.time() - i.play_start_time) % (i.duration * i.time_factor)) / (i.duration * i.time_factor) end end, 0.01)
  i.pos_metro:start()

  i.process = function(_) print("event") end

  return i
end

--- clear this pattern
function event_pattern:clear()
  self.metro:stop()
  self.rec = 0
  self.play = 0
  self.overdub = 0
  self.prev_time = 0
  self.event = {}
  self.time = {}
  self.count = 0
  self.step = 0
  self.time_factor = 1
  self.start_time = 0
  self.end_time = 0
  self.duration = 0
  self.pos = 0
end


--- adjust the time factor of this pattern.
-- @tparam number f time factor
function event_pattern:set_time_factor(f)
  self.time_factor = f or 1
end

--- start recording
function event_pattern:rec_start()
  print("pattern rec start")
  self.rec = 1
end

--- stop recording
function event_pattern:rec_stop()
  if self.rec == 1 then
    self.rec = 0
    if self.count ~= 0 then
      --print("count "..self.count)
      local t = self.prev_time
      self.prev_time = util.time()
      self.time[self.count] = self.prev_time - t
      self.end_time = self.prev_time
      self.duration = self.end_time - self.start_time
    else
      print("pattern_time: no events recorded")
    end
  else print("pattern_time: not recording")
  end
end

--- watch
function event_pattern:watch(e)
  if self.rec == 1 then
    self:rec_event(e)
  elseif self.overdub == 1 then
    self:overdub_event(e)
  end
end

--- record event
function event_pattern:rec_event(e)
  local c = self.count + 1
  if c == 1 then
    self.prev_time = util.time()
    self.start_time = self.prev_time
  else
    local t = self.prev_time
    self.prev_time = util.time()
    self.time[c-1] = self.prev_time - t
  end
  self.count = c
  self.event[c] = e
end

--- add overdub event
function event_pattern:overdub_event(e)
  local c = self.step + 1
  local t = self.prev_time
  self.prev_time = util.time()
  local a = self.time[c-1]
  self.time[c-1] = self.prev_time - t
  table.insert(self.time, c, (a - self.time[c-1]))
  table.insert(self.event, c, e)
  self.step = self.step + 1
  self.count = self.count + 1
end

--- start this pattern
function event_pattern:start()
  if self.count > 0 then
    self.prev_time = util.time()
    self.process(self.event[1])
    self.play = 1
    self.step = 1
    self.metro.time = self.time[1] * self.time_factor
    self.metro:start()

    -- used to calculate position in sequence
    self.play_start_time = self.prev_time
  end
end

--- process next event
function event_pattern:next_event()
  self.prev_time = util.time()
  if self.step == self.count then -- loop back after sync
    self.step = 1
  else
    self.step = self.step + 1
  end

  -- process next event
  self.process(self.event[self.step])
  self.metro.time = self.time[self.step] * self.time_factor

  self.metro:start()
end

--- stop this pattern
function event_pattern:stop()
  if self.play == 1 then
    self.play = 0
    self.overdub = 0
    self.metro:stop()
  else print("pattern_time: not playing") end
end

--- set overdub
function event_pattern:set_overdub(s)
  if s==1 and self.play == 1 and self.rec == 0 then
    self.overdub = 1
  else
    self.overdub = 0
  end
end

return event_pattern
