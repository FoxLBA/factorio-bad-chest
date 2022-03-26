data:extend{
  {
    type = "string-setting",
    name = "recursive-blueprints-area",
    setting_type = "runtime-global",
    default_value = "center",
    allowed_values = {"center", "corner"},
  },
  {
    type = "string-setting",
    name = "recursive-blueprints-logging",
    setting_type = "runtime-global",
    default_value = "never",
    allowed_values = {"never", "with 'L>0' signal", "with 'L>=0' signal", "always"},
  }
}
