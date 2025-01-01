local C_COMB_SECTIONS_WRITE_LIMIT = 20
-- Command signals
local COM_SIGNAL = {name="recursive-blueprints-deployer-command", type="virtual"}
local AREA_SIGNALS = {
  x = {name="signal-X", type="virtual"},
  y = {name="signal-Y", type="virtual"},
  w = {name="signal-W", type="virtual"},
  h = {name="signal-H", type="virtual"},
}
local FLAG_SIGNALS = {
  rotate =     {name="recursive-blueprints-deployer-rotate-bp",     type="virtual"},
  superforce = {name="recursive-blueprints-deployer-superforce",    type="virtual"},
  cancel =     {name="recursive-blueprints-deployer-cancel",        type="virtual"},
  invert =     {name="recursive-blueprints-deployer-invert-filter", type="virtual"},
  enviroment = {name="recursive-blueprints-deployer-enviroment",    type="virtual"},
  quality =    {name="recursive-blueprints-deployer-quality",       type="virtual"},
}
local BOOK_SIGNALS = {}
for i = 1, 6 do table.insert(BOOK_SIGNALS, {name="recursive-blueprints-book-layer"..i, type="virtual"}) end

---@class BAD_Chest
---@field entity LuaEntity
---@field id uint
---@field is_input_combined boolean
---@field input_main defines.wire_connector_id
---@field input_alt defines.wire_connector_id
---@field output_entity nil|LuaEntity
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
    if       com <  10 then  -- Item in inventory
      if     com == 1 then -- Use item
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
        if bp.is_blueprint then self:deploy_blueprint(bp)
        elseif bp.is_deconstruction_item then self:deconstruct_area(bp)
        elseif bp.is_upgrade_item then self:upgrade_area(bp)
        end
      end
    elseif   com <  30 then -- Deconstructions & Upgrades
      if     com == 10 then -- Simple deconstruction
        self:deconstruct_area(nil)
      elseif com == 11 then -- Filtred deconstruction
        self:signal_filtred_deconstruction()
      --end
    --elseif com < 30 then -- Upgrades
      elseif com == 20 then -- Simple upgrade
        local upg = storage.plans[2][1]
        upg.clear_upgrade_item()
        self:upgrade_area(upg)
      end
    elseif   com <  40 then  -- Remote c-comb
      local c_comb = self:find_c_comb()
      if not c_comb then return end
      local behavior = c_comb.get_control_behavior() ---@cast behavior LuaConstantCombinatorControlBehavior
      if     com == 30 then -- Read signals from c_comb
        self:read_from_c_comb(c_comb)
      elseif com == 31 then -- Write signals to c_comb
        self:write_to_c_comb(c_comb)
      elseif com == 32 then -- On/Off remote c_comb
        behavior.enabled = self:get_signal(FLAG_SIGNALS.invert) > 0
      elseif com == 33 then -- Clear remote c_comb
        RB_util.clear_constant_combinator(behavior)
      end
    elseif   com <  50 then -- I/O
      if     com == 40 then -- Clear output
        self:output_clear()
      elseif com == 41 then -- Reset I/O
        self:reset_IO()
      end
    elseif   com <  130 then -- BP managment
      if     com == 100 then -- Simple copy
        self:copy_blueprint(false)
      elseif com == 120 then -- Delete blueprint item
        local stack = self.entity.get_inventory(defines.inventory.chest)[1]
        if RB_util.is_BP(stack) then
          stack.clear()
          self:logging("destroy_book", nil)
        end
      end
    end
  end
end

function BAD_Chest:deploy_blueprint(bp)
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
  bp.build_blueprint{
    surface = e.surface,
    force = e.force,
    position = position,
    direction = direction,
    build_mode = build_mode,
    raise_built = true,
  }

  self:logging("point_deploy", {bp = bp, position = position, direction = direction} )
end

function BAD_Chest:deconstruct_area(bp)
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
        table.insert(tmp, {name = name})
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
  local out_e = self:output_get_or_create_entity()
  if not out_e then return end
  local section_i = self:get_signal(FLAG_SIGNALS.enviroment)
  if section_i < 1 then
    out_e.copy_settings(c_comb)
  else
    local distant_behavior = c_comb.get_control_behavior() ---@type LuaConstantCombinatorControlBehavior
    local s = RB_util.clear_constant_combinator(out_e.get_control_behavior())
    if distant_behavior.sections_count < section_i then return end
    local distant_s = distant_behavior.sections[section_i]
    if not distant_s.active and (self:get_signal(FLAG_SIGNALS.superforce) < 1) then return end
    s.filters  = distant_s.filters
    s.multiplier  = distant_s.multiplier
    s.group  = distant_s.group
  end
end

function BAD_Chest:write_to_c_comb(c_comb)
  if not self:separete_comm_inputs() then return end
  local section_i = self:get_signal(FLAG_SIGNALS.enviroment)
  if section_i > C_COMB_SECTIONS_WRITE_LIMIT then return end
  local behavior = c_comb.get_control_behavior() ---@type LuaConstantCombinatorControlBehavior
  if section_i < 1 then
    RB_util.clear_constant_combinator(behavior)
    section_i = 1
  end
  if behavior.sections_count < section_i then
    for _ = behavior.sections_count, section_i do behavior.add_section() end
    if behavior.sections_count < section_i then return end
  end
  local section = behavior.sections[section_i]
  local filter = {}
  ---@diagnostic disable-next-line: param-type-mismatch
  for _, signal in pairs(self.entity.get_signals(self.input_alt)) do
    table.insert(filter, signal.signal)
  end
  section.filters = filter
end

function BAD_Chest:get_signal(signal)
  if self.is_input_combined then
    return self.entity.get_signal(signal, defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)
  end
  return self.entity.get_signal(signal, self.input_main)
end

function BAD_Chest:separete_comm_inputs()
  if self.is_input_combined then
    local r = self.entity.get_signal(COM_SIGNAL, defines.wire_connector_id.circuit_red)
    local g = self.entity.get_signal(COM_SIGNAL, defines.wire_connector_id.circuit_green)
    if (r==0 or g==0) then
      self.is_input_combined = false
      if g==0 then
        self.input_main = defines.wire_connector_id.circuit_red
        self.input_alt  = defines.wire_connector_id.circuit_green
      else
        self.input_main = defines.wire_connector_id.circuit_green
        self.input_alt  = defines.wire_connector_id.circuit_red
      end
      return true
    end
    return false
  end
  return true
end

function BAD_Chest:get_target_position()
  -- Shift x,y coordinates
  local d_pos = self.entity.position
  local position = {
    x = d_pos.x + self:get_signal(AREA_SIGNALS.x),
    y = d_pos.y + self:get_signal(AREA_SIGNALS.y),
  }

  -- Check for building out of bounds (map limit 2^23 = 8'388'608)
  if position.x > 8000000
  or position.x < -8000000
  or position.y > 8000000
  or position.y < -8000000 then
    return
  end
  return position
end

function BAD_Chest:get_area()
  local X = self:get_signal(AREA_SIGNALS.x)
  local Y = self:get_signal(AREA_SIGNALS.y)
  local W = self:get_signal(AREA_SIGNALS.w)
  local H = self:get_signal(AREA_SIGNALS.h)

  if W < 1 then W = 1 end
  if H < 1 then H = 1 end

  if settings.global["recursive-blueprints-area"].value == "corner" then
    -- Convert from top left corner to center
    X = X + math.floor((W - 1) / 2)
    Y = Y + math.floor((H - 1) / 2)
  end

  -- Align to grid
  if W % 2 == 0 then X = X + 0.5 end
  if H % 2 == 0 then Y = Y + 0.5 end

  -- Subtract 1 pixel from the edges to avoid tile overlap
  -- 2 / 256 = 0.0078125
  W = W - 0.0078125
  H = H - 0.0078125

  local position = self.entity.position
  local area = {
    {position.x + X - W/2, position.y + Y - H/2},
    {position.x + X + W/2, position.y + Y + H/2}
  }
  RB_util.area_check_limits(area)
  return area
end

function BAD_Chest:reset_IO()
  self.is_input_combined = true
  local e = self.output_entity
  if e and e.valid then
    e.destroy()
    self.output_entity = nil
  end
end

function BAD_Chest:output_clear()
  local e = self.output_entity
  if e and e.valid then
    RB_util.clear_constant_combinator(e.get_control_behavior())
  end
end

function BAD_Chest:output_get_or_create_entity()
  local main_e = self.entity
  local b = self.output_entity
  if not b or not b.valid then
    b = main_e.surface.create_entity{
      name = "recursive-blueprints-hidden-io",
      position = main_e.position,
      force = main_e.force,
      create_build_effect_smoke = false,
    }
    if not b then return end
    self.output_entity = b
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
  local e = self.output_entity
  if e and e.valid then e.teleport(self.entity.position) end
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

local function make_area_string(deployer)
  if not deployer then return "" end
  return " W=" .. deployer:get_signal(AREA_SIGNALS.w) .. " H=" .. deployer:get_signal(AREA_SIGNALS.h)
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
    local target_gps = make_gps_string(self:get_target_position(), surface)
    if deployer_gps == target_gps then target_gps = "" end
    msg = {"recursive-blueprints-deployer-logging.deploy-bp", deployer_gps, get_bp_name(vars.bp), target_gps}

  elseif msg_type == "area_deploy" then
    local target_gps  = make_gps_string(self:get_target_position(), surface)
    if deployer_gps == target_gps then target_gps = "" end
    local sub_msg = vars.sub_type
    if not self:get_signal(FLAG_SIGNALS.cancel) > 0 then sub_msg = "cancel-" .. sub_msg end
    msg = {"recursive-blueprints-deployer-logging."..sub_msg, deployer_gps, get_bp_name(vars.bp), target_gps, make_area_string(self)}

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

local function empty_func(_,_,_) end
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

script.register_metatable("Deployer2", BAD_Chest)
return BAD_Chest
