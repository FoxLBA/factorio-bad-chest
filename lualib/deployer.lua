local Deployer = {}

-- Command signals
local DEPLOY_SIGNAL = {name="construction-robot", type="item"}
local DECONSTRUCT_SIGNAL = {name="deconstruction-planner", type="item"}
local COPY_SIGNAL = {name="signal-C", type="virtual"}
local X_SIGNAL = {name="signal-X", type="virtual"}
local Y_SIGNAL = {name="signal-Y", type="virtual"}
local WIDTH_SIGNAL = {name="signal-W", type="virtual"}
local HEIGHT_SIGNAL = {name="signal-H", type="virtual"}
local ROTATE_SIGNAL = {name="signal-R", type="virtual"}
local NESTED_DEPLOY_SIGNALS = {DEPLOY_SIGNAL}
for i = 1, 5 do
    table.insert(
        NESTED_DEPLOY_SIGNALS,
        {name="signal-"..i, type="virtual"}
    )
end

local function read_1_deploy_signal(get_signal)
  return get_signal(DEPLOY_SIGNAL)
end
local ALT_DEPLOY_SIGNAL = {name="construction-robot", type="item"}
local function read_2_deploy_signals(get_signal)
  local value = get_signal(DEPLOY_SIGNAL)
  if value == 0 then value = get_signal(ALT_DEPLOY_SIGNAL) end
  return value
end
local read_deploy_signal = read_1_deploy_signal

function Deployer.toggle_deploy_signal_setting()
  local value = settings.global["recursive-blueprints-deployer-deploy-signal"].value
  if value == "construction_robot" then
    DEPLOY_SIGNAL.name = "construction-robot"
    DEPLOY_SIGNAL.type = "item"
  else
    DEPLOY_SIGNAL.name = "signal-0"
    DEPLOY_SIGNAL.type = "virtual"
  end
  if value == "both" then
    read_deploy_signal = read_2_deploy_signals
  else
    read_deploy_signal = read_1_deploy_signal
  end
end

function Deployer.deploy_blueprint(bp, deployer)
  if not bp.is_blueprint_setup() then return end

  -- Rotate
  local rotation = deployer.get_merged_signal(ROTATE_SIGNAL)
  local direction = defines.direction.north
  if (rotation == 1) then
    direction = defines.direction.east
  elseif (rotation == 2) then
    direction = defines.direction.south
  elseif (rotation == 3) then
    direction = defines.direction.west
  end

  local position = Deployer.get_target_position(deployer)
  if not position then return end

  -- Build blueprint
  local result = bp.build_blueprint{
    surface = deployer.surface,
    force = deployer.force,
    position = position,
    direction = direction,
    force_build = true,
  }

  -- Raise event for ghosts created
  for _, ghost in pairs(result) do
    script.raise_event(defines.events.script_raised_built, {
      entity = ghost,
      stack = bp,
    })
  end
  Deployer.deployer_logging("point_deploy", deployer,
                    {bp = bp, position = position, direction = direction}
                  )
end

function Deployer.deconstruct_area(bp, deployer, deconstruct)
  local area = Deployer.get_area(deployer)
  local force = deployer.force
  if not deconstruct then
    -- Cancel area
    deployer.surface.cancel_deconstruct_area{
      area = area,
      force = force,
      skip_fog_of_war = false,
      item = bp,
    }
  else
    -- Deconstruct area
    local deconstruct_self = deployer.to_be_deconstructed(force)
    deployer.surface.deconstruct_area{
      area = area,
      force = force,
      skip_fog_of_war = false,
      item = bp,
    }
    if not deconstruct_self then
      -- Don't deconstruct myself in an area order
      deployer.cancel_deconstruction(force)
    end
  end
  Deployer.deployer_logging("area_deploy", deployer,
                    {sub_type = "deconstruct", bp = bp,
                    area = area, apply = deconstruct}
                  )
end

function Deployer.upgrade_area(bp, deployer, upgrade)
  local area = Deployer.get_area(deployer)
  if not upgrade then
    -- Cancel area
    deployer.surface.cancel_upgrade_area{
      area = area,
      force = deployer.force,
      skip_fog_of_war = false,
      item = bp,
    }
  else
    -- Upgrade area
    deployer.surface.upgrade_area{
      area = area,
      force = deployer.force,
      skip_fog_of_war = false,
      item = bp,
    }
  end
  Deployer.deployer_logging("area_deploy", deployer,
                    {sub_type = "upgrade", bp = bp,
                    area = area, apply = upgrade}
                  )
end

function Deployer.signal_filtred_deconstruction(deployer, deconstruct, whitelist)
  local force = deployer.force
  local surface = deployer.surface
  local d_area = Deployer.get_area(deployer)
  local areas = RB_util.find_charted_areas(force, surface, d_area)
  local deconstruct_self = deployer.to_be_deconstructed(force)
  local func_name = "order_deconstruction"
  if not deconstruct then func_name = "cancel_deconstruction" end
  local list = {}
  local signal_t = false
  local signal_r = false
  local signal_c = false
  -- Read whitelist/blacklist from signals.
  for _, signal in pairs(deployer.get_merged_signals()) do
    if signal.count > 0 then
      local s_name = signal.signal.name
      if signal.signal.type == "item" then
        local i_prototype = game.item_prototypes[s_name]
        if i_prototype.place_result then
          table.insert(list, i_prototype.place_result.name)
          if i_prototype.curved_rail then
            table.insert(list, i_prototype.curved_rail.name)
          end
        end
      elseif s_name == "signal-T" then signal_t = true
      elseif s_name == "signal-R" then signal_r = true
      elseif s_name == "signal-C" then signal_c = true
      end
    end
  end
  -- Apply a blacklist/whitelist.
  local list_empty = not (#list>0 or signal_t or signal_r or signal_c)
  if whitelist then
    if list_empty then return end
    for _, area in pairs(areas) do
      if #list>0 then
        for _, entity in pairs(surface.find_entities_filtered{name = list, force = force, area = area})do
          entity[func_name](force) --order or cancel deconstruction
        end
      end
      local types = {}
      if signal_t then table.insert(types, "tree") end
      if signal_c then table.insert(types, "cliff") end
      if #types>0 then
        for _, entity in pairs(surface.find_entities_filtered{type = types, area = area})do
          entity[func_name](force)
        end
      end
      if signal_r and #global.rocks_names2>0 then
        for _, entity in pairs(surface.find_entities_filtered{name = global.rocks_names2, area = area})do
          entity[func_name](force)
        end
      end
    end
  else
    if list_empty then
      Deployer.deconstruct_area(nil, deployer, deconstruct)
      return
    end
    local blacklist = {}
    for _, name in pairs(list) do blacklist[name] = true end
    for _, area in pairs(areas) do
      if #list == 0 then
        for _, entity in pairs(surface.find_entities_filtered{force = force, area = area})do
          entity[func_name](force)
        end
      else
        for _, entity in pairs(surface.find_entities_filtered{force = force, area = area})do
          if not blacklist[entity.name] then entity[func_name](force) end
        end
      end
      local types = {}
      if not signal_t then table.insert(types, "tree") end
      if not signal_c then table.insert(types, "cliff") end
      if #types>0 then
        for _, entity in pairs(surface.find_entities_filtered{type = types, area = area})do
          entity[func_name](force)
        end
      end
      if not signal_r and #global.rocks_names2>0 then
        for _, entity in pairs(surface.find_entities_filtered{name = global.rocks_names2, area = area})do
          entity[func_name](force)
        end
      end
    end
  end
  if not deconstruct_self then
    -- Don't deconstruct myself in an area order
    deployer.cancel_deconstruction(force)
  end
  Deployer.deployer_logging("area_deploy", deployer, {sub_type = "deconstruct", area = d_area, apply = deconstruct})
end

function Deployer.on_tick_deployer(deployer)
  if not deployer.valid then return end
  -- Read deploy signal
  local get_signal = deployer.get_merged_signal
  local deploy = read_deploy_signal(get_signal)
  if deploy ~= 0 then
    local command_direction = deploy > 0
    if not command_direction then deploy = -deploy end
    local bp = deployer.get_inventory(defines.inventory.chest)[1]
    if not bp.valid_for_read then return end
    -- Pick item from blueprint book
    if bp.is_blueprint_book then
      local inventory = nil
      for i=1, 6 do
        inventory = bp.get_inventory(defines.inventory.item_main)
        if #inventory < 1 then return end -- Got an empty book, nothing to do
        if i ~= 1 then deploy = get_signal(NESTED_DEPLOY_SIGNALS[i]) end
        if (deploy < 1) or (deploy > #inventory) then break end -- Navigation is no longer applicable
        bp = inventory[deploy]
        if not bp.valid_for_read then return end -- Got an empty slot
        if not bp.is_blueprint_book then break end
      end
      -- Pick active item from nested blueprint books if it is still a book.
      while bp.is_blueprint_book do
        if not bp.active_index then return end
        bp = bp.get_inventory(defines.inventory.item_main)[bp.active_index]
        if not bp.valid_for_read then return end
      end
    end
    if bp.is_blueprint then Deployer.deploy_blueprint(bp, deployer)
    elseif bp.is_deconstruction_item then Deployer.deconstruct_area(bp, deployer, command_direction)
    elseif bp.is_upgrade_item then Deployer.upgrade_area(bp, deployer, command_direction)
    end
    return
  end

  -- Read deconstruct signal
  local deconstruct = get_signal(DECONSTRUCT_SIGNAL)
  if deconstruct < 0 then
    if deconstruct == -1 then
      -- Deconstruct area
      Deployer.deconstruct_area(nil, deployer, true)
    elseif deconstruct == -2 then
      -- Deconstruct self
      deployer.order_deconstruction(deployer.force)
      Deployer.deployer_logging("self_deconstruct", deployer, nil)
    elseif deconstruct == -3 then
      -- Cancel deconstruction in area
      Deployer.deconstruct_area(nil, deployer, false)
    elseif deconstruct >= -7 then
      --[[
        -4 = Deconstruct area with provided item signals as whitelist
        -5 = Deconstruct area with provided item signals as blacklist
        -6 = Cancel area deconstruct with provided item signals as whitelist
        -7 = Cancel area deconstruct with provided item signals as blacklist
      ]]
      local whitelist = (deconstruct == -4) or (deconstruct == -6)
      local decon = (deconstruct == -4) or (deconstruct == -5)
      Deployer.signal_filtred_deconstruction(deployer, decon, whitelist)
    end
    return
  end

  -- Read copy signal
  local copy = get_signal(COPY_SIGNAL)
  if copy ~= 0 then
    if copy == 1 then
      -- Copy blueprint
      Deployer.copy_blueprint(deployer)
    elseif copy == -1 then
      -- Delete blueprint
      local stack = deployer.get_inventory(defines.inventory.chest)[1]
      if not stack.valid_for_read then return end
      if stack.is_blueprint
      or stack.is_blueprint_book
      or stack.is_upgrade_item
      or stack.is_deconstruction_item then
        stack.clear()
        Deployer.deployer_logging("destroy_book", deployer, nil)
      end
    end
    return
  end
end

function Deployer.get_area(deployer)
  local get_signal = deployer.get_merged_signal
  local X = get_signal(X_SIGNAL)
  local Y = get_signal(Y_SIGNAL)
  local W = get_signal(WIDTH_SIGNAL)
  local H = get_signal(HEIGHT_SIGNAL)

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

  local position = deployer.position
  return {
    {position.x + X - W/2, position.y + Y - H/2},
    {position.x + X + W/2, position.y + Y + H/2}
  }
end

function Deployer.get_area_signals(deployer)
  local get_signal = deployer.get_merged_signal
  return get_signal(WIDTH_SIGNAL), get_signal(HEIGHT_SIGNAL)
end

function Deployer.get_target_position(deployer)
  -- Shift x,y coordinates
  local d_pos = deployer.position
  local get_signal = deployer.get_merged_signal
  local position = {
    x = d_pos.x + get_signal(X_SIGNAL),
    y = d_pos.y + get_signal(Y_SIGNAL),
  }

  -- Check for building out of bounds
  if position.x > 1000000
  or position.x < -1000000
  or position.y > 1000000
  or position.y < -1000000 then
    return
  end
  return position
end

function Deployer.copy_blueprint(deployer)
  local inventory = deployer.get_inventory(defines.inventory.chest)
  if not inventory.is_empty() then return end
  for _, signal in pairs(global.blueprint_signals) do
    -- Check for a signal before doing an expensive search
    if deployer.get_merged_signal(signal) >= 1 then
      -- Signal exists, now we have to search for the blueprint
      local stack = Deployer.find_stack_in_network(deployer, signal.name)
      if stack then
        inventory[1].set_stack(stack)
        Deployer.deployer_logging("copy_book", deployer, stack)
        return
      end
    end
  end
end

-- Create a unique key for a circuit connector
local function con_hash(entity, connector, wire)
  return entity.unit_number .. "-" .. connector .. "-" .. wire
end

-- Breadth-first search for an item in the circuit network
-- If there are multiple items, returns the closest one (least wire hops)
function Deployer.find_stack_in_network(deployer, item_name)
  local present = {
    [con_hash(deployer, defines.circuit_connector_id.container, defines.wire_type.red)] =
    {
      entity = deployer,
      connector = defines.circuit_connector_id.container,
      wire = defines.wire_type.red,
    },
    [con_hash(deployer, defines.circuit_connector_id.container, defines.wire_type.green)] =
    {
      entity = deployer,
      connector = defines.circuit_connector_id.container,
      wire = defines.wire_type.green,
    }
  }
  local past = {}
  local future = {}
  while next(present) do
    for key, con in pairs(present) do
      -- Search connecting wires
      for _, def in pairs(con.entity.circuit_connection_definitions) do
        -- Wire color and connection points must match
        if def.target_entity.unit_number
        and def.wire == con.wire
        and def.source_circuit_id == con.connector then
          local hash = con_hash(def.target_entity, def.target_circuit_id, def.wire)
          if not past[hash] and not present[hash] and not future[hash] then
            -- Search inside the entity
            local stack = Deployer.find_stack_in_container(def.target_entity, item_name)
            if stack then return stack end

            -- Add entity connections to future searches
            future[hash] = {
              entity = def.target_entity,
              connector = def.target_circuit_id,
              wire = def.wire
            }
          end
        end
      end
      past[key] = true
    end
    present = future
    future = {}
  end
end

function Deployer.find_stack_in_container(entity, item_name)
  local e_type = entity.type
  if e_type == "container" or e_type == "logistic-container" then
    local inventory = entity.get_inventory(defines.inventory.chest)
    for i = 1, #inventory do
      if inventory[i].valid_for_read and inventory[i].name == item_name then
        return inventory[i]
      end
    end
  elseif e_type == "inserter" then
    local behavior = entity.get_control_behavior()
    e_held_stack = entity.held_stack
    if behavior
    and behavior.circuit_read_hand_contents
    and e_held_stack.valid_for_read
    and e_held_stack.name == item_name then
      return e_held_stack
    end
  end
end

function Deployer.get_nested_blueprint(bp)
  if not bp then return end
  if not bp.valid_for_read then return end
  while bp.is_blueprint_book do
    if not bp.active_index then return end
    bp = bp.get_inventory(defines.inventory.item_main)[bp.active_index]
    if not bp.valid_for_read then return end
  end
  return bp
end

-- Collect all modded blueprint signals in one table
function Deployer.cache_blueprint_signals()
  local blueprint_signals = {}
  local filter ={
    {filter = "type", type="blueprint"},
    {filter = "type", type="blueprint-book"},
    {filter = "type", type="upgrade-item"},
    {filter = "type", type="deconstruction-item"}
  }
  for _, item in pairs(game.get_filtered_item_prototypes(filter)) do
    table.insert(blueprint_signals, {name=item.name, type="item"})
  end
  global.blueprint_signals = blueprint_signals
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

local function make_area_string(deployer)
    if not deployer then return "" end
    local W, H = Deployer.get_area_signals(deployer)
    return " W=" .. W .. " H=" .. H
end

local function make_bp_name_string(bp)
    if not bp or not bp.valid or not bp.label then return "unnamed" end
    return bp.label
end

local function deployer_logging_func(msg_type, deployer, vars)
  if deployer.get_merged_signal(LOGGING_SIGNAL) < LOGGING_LEVEL then
    return
  end

  local msg = ""
  local deployer_gps = make_gps_string(deployer.position, deployer.surface)

  --"point_deploy" "area_deploy" "self_deconstruct" "destroy_book" "copy_book"
  if msg_type == "point_deploy" then
    local target_gps  = make_gps_string(vars.position, deployer.surface)
    if deployer_gps == target_gps then target_gps = "" end
    msg = {"recursive-blueprints-deployer-logging.deploy-bp", deployer_gps, make_bp_name_string(vars.bp), target_gps}

  elseif msg_type == "area_deploy" then
    local target_gps  = make_gps_string(Deployer.get_target_position(deployer), deployer.surface)
    if deployer_gps == target_gps then target_gps = "" end
    local sub_msg = vars.sub_type
    if not vars.apply then sub_msg = "cancel-" .. sub_msg end
    msg = {"recursive-blueprints-deployer-logging."..sub_msg, deployer_gps, make_bp_name_string(vars.bp), target_gps, make_area_string(deployer)}

  else
    msg = {"recursive-blueprints-deployer-logging.unknown", deployer_gps, msg_type}
  end

  if deployer.force and deployer.force.valid then
    deployer.force.print(msg)
  else
    game.print(msg)
  end
end

local function empty_func() end

Deployer.deployer_logging = empty_func

function Deployer.toggle_logging()
  local log_settings = settings.global["recursive-blueprints-logging"].value
  if log_settings == "never" then
    Deployer.deployer_logging = empty_func
  else
    Deployer.deployer_logging = deployer_logging_func
    if log_settings == "with_L_greater_or_equal_to_zero" then
      LOGGING_LEVEL = 0
    elseif log_settings == "with_L_greater_than_zero" then
      LOGGING_LEVEL = 1
    else
      LOGGING_LEVEL = -4000000000
    end
  end
end

return Deployer
