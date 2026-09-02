--- @sync entry
-- smart-enter: <Enter> descends into a directory, opens anything else.
-- Mirrors yazi-rs/plugins:smart-enter, vendored here so kempt owns it.
-- NOTE: the `--- @sync` annotation must be the first line or yazi runs the
-- plugin async, where `cx` is nil.
return {
  entry = function()
    local h = cx.active.current.hovered
    ya.emit(h and h.cha.is_dir and "enter" or "open", { hovered = true })
  end,
}
