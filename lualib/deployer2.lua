local Parametric = require"lualib.parameterization"

local C_COMB_SECTIONS_WRITE_LIMIT = 20
-- Command signals
local COMMANDS = {} --The list of commands is located at the end of this file.
local COM_SIGNAL   = RBP_defines.COM_SIGNAL
local AREA_SIGNALS = RBP_defines.AREA_SIGNALS
local FLAG_SIGNALS = RBP_defines.FLAG_SIGNALS
local BOOK_SIGNALS = RBP_defines.BOOK_SIGNALS
local UNION_SIGNALS_LIST = RBP_defines.UNION_SIGNALS_LIST
local OUTPUT_VALID_NAMES = {
  output_alt = true, -- hidden c-comb that emits output signals.
  output_compensate = true, -- hidden c-comb that emits -1 of item stored in BAD_Chest.
}

local function empty_func() end

---@class BAD_Chest
---@field entity LuaEntity
---@field id uint
---@field is_input_combined boolean
---@field input_main defines.wire_connector_id
---@field input_alt defines.wire_connector_id
---@field output_alt nil|LuaEntity
---@field output_compensate nil|LuaEntity
local BAD_Chest = {}
BAD_Chest.__index = BAD_Chest

function BAD_Chest.on_built(entity)
  local obj = {
    id = entity.unit_number,
    entity = entity,
    is_input_combined = true,
    input_main = defines.wire_connector_id.circuit_red,
    input_alt = defines.wire_connector_id.circuit_green,
  }
  script.register_on_object_destroyed(entity)
  setmetatable(obj, BAD_Chest)
  storage.deployers2[obj.id] = obj
  return obj
end

function BAD_Chest.on_destroy(id)
  local deployer = storage.deployers2[id]
  if deployer then deployer:destroy() end
end

function BAD_Chest.on_tick()
  for _, obj in pairs(storage.deployers2) do
    if obj.entity.valid then
      obj:tick()
    else
      obj:destroy()
    end
  end
end

function BAD_Chest:destroy()
  self:reset_IO()
  storage.deployers2[self.id] = nil
end


function BAD_Chest:tick()
  local com = self:get_signal(COM_SIGNAL)
  if com > 0 then
    COMMANDS[com](self, com)
  end
end

function BAD_Chest:use_item(com)
  local bp = self.entity.get_inventory(defines.inventory.chest)[1]
  if not bp.valid_for_read then return end
  -- Pick item from blueprint book
  if bp.is_blueprint_book then
    bp = self:pick_from_book(bp)
    if not bp.valid_for_read then return end -- Got an empty slot
    -- Pick active item from nested blueprint books if it is still a book.
    while bp.is_blueprint_book do
      if not bp.active_index then return end
      bp = bp.get_inventory(defines.inventory.item_main)[bp.active_index]
      if not bp.valid_for_read then return end
    end
  end
  if bp.is_blueprint then self:deploy_blueprint(bp, com)
  elseif bp.is_deconstruction_item then self:deconstruct_area(bp)
  elseif bp.is_upgrade_item then self:upgrade_area(bp)
  end
end

function BAD_Chest:simple_upgrade()
  local upg = storage.plans[2][1]
  upg.clear_upgrade_item()
  self:upgrade_area(upg)
end

function BAD_Chest:deploy_blueprint(bp, com)
  if not bp.is_blueprint_setup() then return end

  -- Rotate
  local rotation = self:get_signal(FLAG_SIGNALS.rotate)
  local direction = defines.direction.north
  if (rotation == 1) then ---@diagnostic disable: cast-local-type
    direction = defines.direction.east
  elseif (rotation == 2) then
    direction = defines.direction.south
  elseif (rotation == 3) then
    direction = defines.direction.west
  end ---@diagnostic enable: cast-local-type

  local position = self:get_target_position()
  if not position then return end
  local build_mode = defines.build_mode.forced
  if self:get_signal(FLAG_SIGNALS.superforce) > 0 then
    ---@diagnostic disable-next-line: cast-local-type
    build_mode = defines.build_mode.superforced
  end
  -- Build blueprint
  local e = self.entity
  if com == 2 then
    local new_bp = storage.plans[3][1]
    new_bp.set_stack(bp)
    local sate, result = pcall(Parametric, e.get_signals(self.input_main, self.input_alt), new_bp)
    if not sate then
      e.force.print(e.gps_tag .. " Blueprint parameterization error:\n" .. result)
    else
      bp = new_bp
    end
  end

  bp.build_blueprint{
    surface = e.surface,
      ---@diagnostic disable-next-line: assign-type-mismatch
    force = e.force,
    position = position,
    direction = direction,
    build_mode = build_mode,
    raise_built = true,
  }

  self:logging("point_deploy", {bp = bp, position = position, direction = direction} )
end

function BAD_Chest:deconstruct_area(bp)
  if type(bp) == "number" then bp = nil end
  local area = self:get_area()
  local surface = self.entity.surface
  local params = {
    area = area,
    force = self.entity.force,
    skip_fog_of_war = false,
    item = bp,
    super_forced = self:get_signal(FLAG_SIGNALS.superforce) > 0
  }
  if self:get_signal(FLAG_SIGNALS.cancel) > 0 then
    surface.cancel_deconstruct_area(params)
  else
    surface.deconstruct_area(params)
    --? Don't deconstruct myself in an area order?
  end
  self:logging("area_deploy", {sub_type = "deconstruct", bp = bp, area = area})
end

function BAD_Chest:upgrade_area(bp)
  local area = self:get_area()
  local surface = self.entity.surface
  local params = {
    area = area,
    force = self.entity.force,
    skip_fog_of_war = false,
    item = bp,
  }
  if self:get_signal(FLAG_SIGNALS.cancel) > 0 then
    surface.cancel_upgrade_area(params)
  else
    surface.upgrade_area(params)
  end
  self:logging("area_deploy", {sub_type = "upgrade", bp = bp, area = area} )
end

function BAD_Chest:signal_filtred_deconstruction()
  local list = {}
  local list_tiles = {}
  local w_list = storage.buildings_without_item_to_place
  -- Read filtred items from signals.
  ---@diagnostic disable-next-line: param-type-mismatch
  for _, signal in pairs(self.entity.get_signals(defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)) do
    if signal.count > 0 then
      local s_name = signal.signal.name
      if signal.signal.type == "item" or not signal.signal.type then
        local i_prototype = prototypes.item[s_name]
        if i_prototype then
          if i_prototype.place_result then
            ---@diagnostic disable-next-line: undefined-field
            table.insert(list, {name = i_prototype.place_result.name, quality = signal.signal.quality or "normal", comparator = "="})
          elseif i_prototype.place_as_tile_result then
            table.insert(list_tiles, i_prototype.place_as_tile_result.result.name)
          end
        end
      elseif signal.signal.type == "entity" and (w_list[s_name] or UNION_SIGNALS_LIST[s_name]) then
        table.insert(list, {type = "entity", name = s_name, quality = signal.signal.quality or "normal", comparator = "="})
      end
    end
  end

  --Set item filters to "any quality"
  if self:get_signal(FLAG_SIGNALS.quality) > 0 then
    local index = {}
    local tmp = {}
    for _, item in pairs(list) do
      local name = item.name
      if not index[name] then
        index[name] = true
        table.insert(tmp, {type = item.type, name = name})
      end
    end
    list = tmp
  end

  local dp = storage.plans[1][1]
  local filter_mode = "whitelist"
  local def_deconstruct = defines.deconstruction_item
  dp.clear_deconstruction_item()
  if self:get_signal(FLAG_SIGNALS.invert) > 0 then filter_mode = "blacklist" end
  dp.entity_filter_mode = def_deconstruct.entity_filter_mode[filter_mode]
  if self:get_signal(FLAG_SIGNALS.enviroment) > 0 then
    dp.trees_and_rocks_only = true
  else
    dp.entity_filters = list
    if #list_tiles > 0 then
      dp.tile_filters = list_tiles
      if #list == 0 then
        dp.tile_selection_mode = def_deconstruct.tile_selection_mode.only
      else
        dp.tile_selection_mode = def_deconstruct.tile_selection_mode.always
      end
      dp.tile_filter_mode = def_deconstruct.tile_filter_mode[filter_mode]
    end
  end
  self:deconstruct_area(dp)
end

function BAD_Chest:copy_blueprint(from_exact)
  local deployer = self.entity
  local inventory = deployer.get_inventory(defines.inventory.chest)
  if not inventory then return end
  local rewrite = (self:get_signal(FLAG_SIGNALS.superforce) > 0) and RB_util.is_BP(inventory[1])
  if (not rewrite and not inventory.is_empty()) then return end
  for _, signal in pairs(storage.blueprint_signals) do
    -- Check for a signal before doing an expensive search
    local r = deployer.get_signal(signal, defines.wire_connector_id.circuit_red) > 0
    local g = deployer.get_signal(signal, defines.wire_connector_id.circuit_green) > 0
    if r or g then
      -- Signal exists, now we have to search for the blueprint
      local stack = RB_util.find_stack_in_network(deployer, signal.name, r, g)
      if stack then
        if from_exact and stack.is_blueprint_book then
          stack = self:pick_from_book(stack)
          if not stack.valid_for_read then return end
        end
        ---@diagnostic disable-next-line: need-check-nil
        inventory[1].set_stack(stack)
        self:logging("copy_book", stack)
        return
      end
    end
  end
end

function BAD_Chest:simple_copy(com)
  self:copy_blueprint(false)
end

function BAD_Chest:delete_item(com)
  local stack = self.entity.get_inventory(defines.inventory.chest)[1]
  if RB_util.is_BP(stack) then
    stack.clear()
    self:logging("destroy_book", nil)
  end
end

function BAD_Chest:remote_c_comb(com)
  local c_comb = self:find_c_comb()
  if not c_comb then return end
  local behavior = c_comb.get_control_behavior() ---@cast behavior LuaConstantCombinatorControlBehavior
  if not behavior and not behavior.valid then return end
  if     com == 30 then -- Read signals from c_comb
    self:read_from_c_comb(behavior)
  elseif com == 31 then -- Write signals to c_comb
    self:write_to_c_comb(behavior)
  elseif com == 32 then -- On/Off remote c_comb
    behavior.enabled = self:get_signal(FLAG_SIGNALS.invert) < 1
  elseif com == 33 then -- Clear remote c_comb
    RB_util.clear_constant_combinator(behavior)
  end
end

function BAD_Chest:find_c_comb()
  local pos = self:get_target_position()
  if not pos then return end
  local surface = self.entity.surface
  local force = self.entity.force
  local s = surface.find_entities_filtered{position = pos, force = force, name = "constant-combinator"}
  if s and #s == 1 then return s[1] end
end

function BAD_Chest:read_from_c_comb(c_comb)
  if not self:separete_comm_inputs() then return end
  local out_e = self:output_get_or_create_entity("output_alt")
  if not out_e then return end
  local section_i = self:get_signal(FLAG_SIGNALS.enviroment)
  if section_i < 1 then
    local out_b = out_e.get_control_behavior() ---@cast out_b LuaConstantCombinatorControlBehavior
    RB_util.clear_constant_combinator(out_b)
    if not out_b or not out_b.valid then return end
    out_b.remove_section(1)
    for _, section in pairs(c_comb.sections) do
      if section.active then
        if section.group == "" then
          local s = out_b.add_section()
          s.filters = section.filters
          s.multiplier = section.multiplier
          s.active = true
        else
          out_b.add_section(section.group)
        end
      end
    end
  else
    local s = RB_util.clear_constant_combinator(out_e.get_control_behavior())
    if c_comb.sections_count < section_i then return end
    local distant_s = c_comb.sections[section_i]
    if not distant_s.active and (self:get_signal(FLAG_SIGNALS.superforce) < 1) then return end
    s.filters  = distant_s.filters
    s.multiplier  = distant_s.multiplier
    s.group  = distant_s.group
  end
end

function BAD_Chest:write_to_c_comb(behavior)
  if not self:separete_comm_inputs() then return end
  local section_i = self:get_signal(FLAG_SIGNALS.enviroment)
  if section_i > C_COMB_SECTIONS_WRITE_LIMIT then return end
  local is_exact_section = true
  if section_i < 1 then
    RB_util.clear_constant_combinator(behavior)
    section_i = 1
    is_exact_section = false
  end
  if behavior.sections_count < section_i then
    for _ = behavior.sections_count, section_i do behavior.add_section() end
    if behavior.sections_count < section_i then return end
  end
  local section = behavior.sections[section_i]
  local filter = {}
  ---@diagnostic disable-next-line: param-type-mismatch
  for _, signal in pairs(self.entity.get_signals(self.input_alt)) do
    local s = signal.signal
    table.insert(filter, {value={type=s.type, name=s.name, quality=s.quality or "normal", comparator="="}, min=signal.count})
  end
  section.filters = filter
  section.active = (not is_exact_section) or (self:get_signal(FLAG_SIGNALS.invert) < 1)
end

function BAD_Chest:get_signal(signal)
  if self.is_input_combined then
    return self.entity.get_signal(signal, defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)
  end
  return self.entity.get_signal(signal, self.input_main)
end

function BAD_Chest:separete_comm_inputs()
  local main_e = self.entity
  if self.is_input_combined then
    local wr, wg = defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green
    local r = main_e.get_signal(COM_SIGNAL, wr)
    local g = main_e.get_signal(COM_SIGNAL, wg)
    if (r==0 or g==0) then
      self.is_input_combined = false
      if g==0 then
        self.input_main = wr
        self.input_alt  = wg
      else
        self.input_main = wg
        self.input_alt  = wr
      end
    else
      return false
    end
  end
  --Read inventory and emit negative signal to compensate it in alt output wire.
  local c = self:output_get_or_create_entity("output_compensate")
  if c and c.valid then
    local section = RB_util.clear_constant_combinator(c.get_control_behavior())
    local inv = main_e.get_inventory(defines.inventory.chest)
    if inv and inv.valid and (not inv.is_empty()) and section and section.valid then
      local con = inv.get_contents()[1]
      ---@diagnostic disable-next-line: missing-fields
      section.set_slot(1, {value={name=con.name, quality=con.quality, comparator="="}, min=(-con.count)})
    end
  end
  return true
end

function BAD_Chest:get_target_position()
  local pos = { --point to the center of a tile.
    x = self:get_signal(AREA_SIGNALS.x) + 0.5,
    y = self:get_signal(AREA_SIGNALS.y) + 0.5,
  }
  -- Shift x,y coordinates
  if self:get_signal(FLAG_SIGNALS.absolute)<=0 then
    local d_pos = self.entity.position
    pos.x = pos.x + math.floor(d_pos.x)
    pos.y = pos.y + math.floor(d_pos.y)
  end

  -- Check for building out of bounds (map limit 2^23 = 8'388'608)
  if pos.x > 8000000
  or pos.x < -8000000
  or pos.y > 8000000
  or pos.y < -8000000 then
    return
  end
  self.last_target = {x = pos.x, y = pos.y}
  return pos
end

function BAD_Chest:get_area()
  local area = RB_util.area_get_from_offsets(
    self.entity.position,
    self:get_signal(AREA_SIGNALS.x),
    self:get_signal(AREA_SIGNALS.y),
    self:get_signal(AREA_SIGNALS.w),
    self:get_signal(AREA_SIGNALS.h),
    self:get_signal(FLAG_SIGNALS.center),
    self:get_signal(FLAG_SIGNALS.absolute)
  )
  if area[1][1] == area[2][1] then area[2][1] = area[2][1] + 1 end
  if area[1][2] == area[2][2] then area[2][2] = area[2][2] + 1 end
  self.last_area = {{area[1][1], area[1][2]}, {area[2][1], area[2][2]}}
  return RB_util.area_shrink_1_pixel(area)
end

function BAD_Chest:reset_IO()
  self.is_input_combined = true
  for name, _ in pairs(OUTPUT_VALID_NAMES) do
    local e = self[name]
    if e and e.valid then
      e.destroy()
      self[name] = nil
    end
  end
end

function BAD_Chest:output_clear()
  if not self:separete_comm_inputs() then return end
  local e = self.output_alt
  if e and e.valid then
    RB_util.clear_constant_combinator(e.get_control_behavior())
  end
end

---@param name string
---@return LuaEntity|nil
function BAD_Chest:output_get_or_create_entity(name)
  if not OUTPUT_VALID_NAMES[name] then return end
  local main_e = self.entity
  local b = self[name]
  if not b or not b.valid then
    b = main_e.surface.create_entity{
      name = "recursive-blueprints-hidden-io",
      position = main_e.position,
      force = main_e.force,
      create_build_effect_smoke = false,
    }
    if not b then return end
    self[name] = b
    local def = self.input_alt
    local hidden_con = b.get_wire_connector(def, true)
    hidden_con.connect_to(main_e.get_wire_connector(def, true))
  end
  return b
end

---@param bp LuaItemStack
---@return LuaItemStack
---@return table|nil
function BAD_Chest:pick_from_book(bp)
  local last
  if bp.is_blueprint_book then
    local inventory
    for i=1, 6 do
      index = self:get_signal(BOOK_SIGNALS[i])
      if index < 1 then break end -- invalid index
      inventory = bp.get_inventory(defines.inventory.item_main)
      last = {inventory, index}
      if (#inventory < 1) or (index > #inventory) then break end -- empty book or index out of bound
      ---@diagnostic disable-next-line: need-check-nil
      bp = inventory[index]
      if not bp.valid_for_read or not bp.is_blueprint_book then break end -- Got an empty slot or not a book
    end
  end
  return bp, last
end

function BAD_Chest:dolly_moved()
  for name, _ in pairs(OUTPUT_VALID_NAMES) do
    local e = self[name]
    if e and e.valid then e.teleport(self.entity.position) end
  end
end

local LOGGING_SIGNAL = {name="signal-L", type="virtual"}
local LOGGING_LEVEL = 0

local function make_gps_string(position, surface)
  if position and surface then
    return string.format("[gps=%s,%s,%s]", position.x, position.y, surface.name)
  else
    return "[lost location]"
  end
end

local function get_bp_name(bp)
  if not bp or not bp.valid or not bp.label then return "unnamed" end
  return bp.label
end

local function make_area_string(size)
  if not size then return "" end
  return " W=" .. size[1] .. " H=" .. size[2]
end

function BAD_Chest:main_logging(msg_type, vars)
  if self:get_signal(LOGGING_SIGNAL) < LOGGING_LEVEL then
    return
  end

  local msg = {""}
  local deployer_gps = self.entity.gps_tag
  local surface = self.entity.surface

  --"point_deploy" "area_deploy" "self_deconstruct" "destroy_book" "copy_book"
  if msg_type == "point_deploy" then
    local target_gps = make_gps_string(self.last_target, surface)
    if deployer_gps == target_gps then target_gps = "" end
    msg = {"recursive-blueprints-deployer-logging.deploy-bp", deployer_gps, get_bp_name(vars.bp), target_gps}

  elseif msg_type == "area_deploy" then
    local c, s = RB_util.area_find_center_and_size(self.last_area)
    local target_gps  = make_gps_string({x = c[1], y = c[2]}, surface)
    if deployer_gps == target_gps then target_gps = "" end
    local sub_msg = vars.sub_type
    if not (self:get_signal(FLAG_SIGNALS.cancel) > 0) then sub_msg = "cancel-" .. sub_msg end
    msg = {"recursive-blueprints-deployer-logging."..sub_msg, deployer_gps, get_bp_name(vars.bp), target_gps, make_area_string(s)}

  else
    msg = {"recursive-blueprints-deployer-logging.unknown", deployer_gps, msg_type}
  end

  local force = self.entity.force
  if force and force.valid then
    force.print(msg)
  else
    game.print(msg)
  end
end

BAD_Chest.logging = empty_func

function BAD_Chest.toggle_logging()
  local log_settings = settings.global["recursive-blueprints-logging"].value
  if log_settings == "never" then
    BAD_Chest.logging = empty_func
  else
    BAD_Chest.logging = BAD_Chest.main_logging
    if log_settings == "with_L_greater_or_equal_to_zero" then
      LOGGING_LEVEL = 0
    elseif log_settings == "with_L_greater_than_zero" then
      LOGGING_LEVEL = 1
    else
      LOGGING_LEVEL = -4000000000
    end
  end
end
BAD_Chest.toggle_logging()

COMMANDS[1]  = BAD_Chest.use_item
COMMANDS[2]  = BAD_Chest.use_item -- blueprint parameterization
COMMANDS[10] = BAD_Chest.deconstruct_area -- simple deconstruction
COMMANDS[11] = BAD_Chest.signal_filtred_deconstruction
COMMANDS[20] = BAD_Chest.simple_upgrade
COMMANDS[30] = BAD_Chest.remote_c_comb -- read
COMMANDS[31] = BAD_Chest.remote_c_comb -- write
COMMANDS[32] = BAD_Chest.remote_c_comb -- toggle on/off
COMMANDS[33] = BAD_Chest.remote_c_comb -- clear
COMMANDS[40] = BAD_Chest.output_clear
COMMANDS[41] = BAD_Chest.reset_IO
COMMANDS[100] = BAD_Chest.simple_copy -- copy blueprint/book
COMMANDS[120] = BAD_Chest.delete_item
setmetatable(COMMANDS, {__index = function() return empty_func end}) -- do nothing by default

script.register_metatable("Deployer2", BAD_Chest)
return BAD_Chest
