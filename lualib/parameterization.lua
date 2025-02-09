local param_list = {}
for i = 1, 9 do param_list[i] = "parameter-"..i end
param_list[10] = "parameter-0"
local num_list = {}
for i = 1, 9 do num_list["signal-"..i] = i end
num_list["signal-"..0] = 10

local char_list1 = {}
for i, c in pairs({"A", "B", "C", "D", "E", "F", "G", "H", "I", "J"}) do
  char_list1["signal-"..c] = i
end
local char_list2 = {}
for i, c in pairs({"K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"}) do
  char_list2["signal-"..c] = i
end

---@param signals Signal[]
local function get_pattern_from_signals(signals)
  local param = {}
  local num_src = {}
  local num_dst = {}
  local num = {}
  for _, s in pairs(signals) do
    local n = s.signal.name
    ---@diagnostic disable: need-check-nil
    if char_list1[n] then num_src[char_list1[n]] = s.count end
    if char_list2[n] then num_dst[char_list2[n]] = s.count end
    if num_list[n] then
      param[n] = s.count
    else
      if num[s.count] then
        table.insert(num[s.count], s.signal)
      else
        num[s.count] = {s.signal}
      end
    end
    ---@diagnostic enable: need-check-nil
  end

  local pattern = {
    signals = {},
    numbers = {},
    sc = false,
    nc = false,
  }
  local check = false
  for name, c in pairs(param) do
    local i = num_list[name]
    if num_list[name] then
      if (c>0) and (c<11) then
        if c == 10 then c = 0 end
        pattern.signals[param_list[i]] = {type="virtual", name="signal-"..c}
      elseif num[c] then
        pattern.signals[param_list[i]] = num[c][1]
      end
      check = true
    end
  end
  pattern.sc = check
  check = false
  for i, s in pairs(num_src) do
    local d = num_dst[i]
    if d then
      pattern.numbers[s] = d
    else
      pattern.numbers[s] = 0
    end
    check = true
  end
  pattern.nc = check
  return pattern
end

local function replace_condition(c, p)
  if not c then return end
  local s = p.signals
  local sg = c.first_signal
  if sg and s[sg.name] then
    c.first_signal = s[sg.name]
  end
  sg = c.second_signal
  local n = p.numbers
  if sg and s[sg.name] then
    c.second_signal = s[sg.name]
  elseif not sg and c.constant and n[c.constant] then
    c.constant = n[c.constant]
  end
end

local function replace_signal(c, sp)
  if (type(c) == "table") and c.name and sp[c.name] then
    local new = sp[c.name]
    c.name = new.name
    c.type = new.type
    c.quality = new.quality or "normal"
    --c.comparator = new.comparator
  end
end

local function replace_constant(c, name, nc)
  if c[name] and nc[c[name]] then c[name] = nc[c[name]]end
end

local function replace_filter(f, sp)
  local p = sp[f.name]
  if p and (not p.type or p.type == "item") then
    f.name = p.name
    f.quality = p.quality or "normal"
  end
end

local function empty_func() end
local Controls = {}
setmetatable(Controls, {
  __index = function (_, k)
    if string.find(k, "_condition$") then
      return replace_condition
    elseif string.find(k, "_signal$") then
      return function(v, p) replace_signal(v, p.signals) end
    end
    return empty_func
  end
})

Controls.arithmetic_conditions = function(value, p)
  local s = p.signals
  local n = p.numbers
  if value.first_signal then
    replace_signal(value.first_signal, s)
  else
    replace_constant(value, "first_constant", n)
  end
  if value.second_signal then
    replace_signal(value.second_signal, s)
  else
    replace_constant(value, "second_constant", n)
  end
  replace_signal(value.output_signal, s)
end

Controls.decider_conditions = function(value, p)
  local s = p.signals
  for _, c in pairs(value.conditions) do
    replace_condition(c, p)
  end
  for _, o in pairs(value.outputs) do
    replace_signal(o.signal, s)
  end
end

--Constant combinator
Controls.sections = function(value, p)
  local s = p.signals
  local n = p.numbers
  for _, s1 in pairs(value) do
    for _, s2 in pairs(s1) do
      if not s2.group then
        for _, f in pairs(s2.filters) do
          replace_signal(f, s)
          if n[f.count] then --replace number
            f.count = n[f.count]
          end
        end
      end
    end
  end
end

--Display panel
Controls.parameters = function(value, p)
  local s = p.signals
  for _, i in pairs(value) do
    replace_condition(i.condition, p)
    replace_signal(i.icon, s)
  end
end

local function parametric(signals, bp)
  --if not bp or not bp.is_blueprint_setup() then return end
  local pattern = get_pattern_from_signals(signals)
  local s = pattern.signals
  --local n = pattern.numbers
  if pattern.sc or pattern.nc then
    local bp_entitys = bp.get_blueprint_entities()
    if bp_entitys then
      for _, g in pairs(bp_entitys) do
        if g.control_behavior then
          for key, value in pairs(g.control_behavior) do
            Controls[key](value, pattern)
          end
        end
        if g.recipe then
          local p = s[g.recipe]
          if p and prototypes.recipe[p.name] then
            if prototypes.entity[g.name].crafting_categories[prototypes.recipe[p.name].category] then
              g.recipe = p.name
              g.recipe_quality = p.quality or "normal"
            end
          end
        end
        if g.filter then
          replace_filter(g.filter, s)
        end
        if g.filters then
          for _, f in pairs(g.filters) do
            replace_filter(f, s)
          end
        end
        if g.request_filters then
          local rf = g.request_filters.sections
          if rf then
            for _, s1 in pairs(rf) do
              if not s1.group then
                for _, f in pairs(s1.filters) do
                  replace_filter(f, s)
                end
              end
            end
          end
        end
        if g.fluid_filter then
          local p = s[g.fluid_filter]
          if p and p.type == "fluid" then
            g.fluid_filter = p.name
          end
        end
        if g.alert_parameters then
          replace_signal(g.alert_parameters.icon_signal_id, s)
        end
        if g.icon then
          replace_signal(g.icon, s)
        end
        --[[
        if g["priority-list"] then
          for _, t in pairs(g["priority-list"]) do
            local p = s[t.name]
            if p and p.type == "entity" then
              t.name = p.name
            end
          end
        end
        ]]
      end
      bp.set_blueprint_entities(bp_entitys)
    end
  end
end

return parametric
