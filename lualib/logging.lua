local LOGGING_SIGNAL = {name="signal-L", type="virtual"}

local function make_gps_string(position, surface)
  if position and surface then
    return string.format("[gps=%s,%s,%s]", position.x, position.y, surface.name)
  else
    return "[lost location]"
  end
end

local function make_area_string(network)
    if not network then return "" end
    local W, H = get_area_signals(network)
    return " W=" .. W ..
           " H=" .. H
end

local function make_bp_name_string(bp)
    if not bp or not bp.valid or not bp.label then return "unnamed" end
    return bp.label
end

function deployer_logging(msg_type, network, vars)
  local log_settings = settings.global["recursive-blueprints-logging"].value
  if log_settings == "never" then
    return
  else
    local L = get_signal(network, LOGGING_SIGNAL)
    if (log_settings == "with 'L>0' signal" and L < 1)
       or (log_settings == "with 'L>=0' signal" and L < 0)
    then
      return
    end
  end
  
  local msg = ""
  local deployer_gps = make_gps_string(network.deployer.position, network.deployer.surface)

  --"point_deploy" "area_deploy" "self_deconstract" "destroy_book" "copy_book"
  if msg_type == "point_deploy" then
    local target_gps  = " " .. make_gps_string(vars.position, network.deployer.surface)
    if deployer_gps == target_gps then target_gps = "" end
    msg = "Deployer " .. deployer_gps ..
          " place bp: " .. make_bp_name_string(vars.bp) .. target_gps

  elseif msg_type == "area_deploy" then
    local target_gps  = " " .. make_gps_string(get_target_position(network), network.deployer.surface)
    if deployer_gps == target_gps then target_gps = "" end
    local sub_msg = ""
    if vars.sub_type == "deconstract" then
      sub_msg = " deconstracting area: "
    elseif vars.sub_type == "upgrade" then
      sub_msg = " upgrading area: "
    else
      sub_msg = " somefing: "
    end
    if not vars.apply then sub_msg = " cansel" .. sub_msg end
    msg = "Deployer " .. deployer_gps ..
          sub_msg .. make_bp_name_string(vars.bp) ..
          target_gps .. make_area_string(network)

  else
    msg = "Deployer " .. deployer_gps .. " sent an unknown message: " .. msg_type
  end

  if network.deployer.force and network.deployer.force.valid then
    network.deployer.force.print(msg)
  else
    game.print(msg)
  end
end
