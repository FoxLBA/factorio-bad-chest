local defs = {}

defs.circuit_red = defines.wire_connector_id.circuit_red
defs.circuit_green = defines.wire_connector_id.circuit_green

defs.AREA_SIGNALS = {
  x = {name="signal-X", type="virtual"},
  y = {name="signal-Y", type="virtual"},
  w = {name="signal-W", type="virtual"},
  h = {name="signal-H", type="virtual"},
}

defs.COM_SIGNAL = {name="rbp-command", type="virtual"}

defs.FLAG_SIGNALS = {
  rotate =     {name="rbp-rotate-bp",     type="virtual"},
  superforce = {name="rbp-superforce",    type="virtual"},
  cancel =     {name="rbp-cancel",        type="virtual"},
  invert =     {name="rbp-invert-filter", type="virtual"},
  enviroment = {name="rbp-enviroment",    type="virtual"},
  quality =    {name="rbp-quality",       type="virtual"},
  center =     {name="rbp-center",        type="virtual"},
  absolute =   {name="rbp-absolute",      type="virtual"},
}

defs.BOOK_SIGNALS = {}
for i = 1, 6 do table.insert(defs.BOOK_SIGNALS, {name="rbp-book-layer"..i, type="virtual"}) end

return defs
