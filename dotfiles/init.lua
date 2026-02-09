local hyper = { "cmd", "alt", "ctrl", "shift" }

hs.hotkey.bind(hyper, "0", function()
  hs.reload()
end)

hs.notify.new({ title="Hammerspoon", informativeText="Config reloaded" }):send()

-- Window management Hyper + j/i/k/l
hs.window.animationDuration = 0

hs.hotkey.bind(hyper, "j", function()
  local win = hs.window.focusedWindow();
  if not win then return end
  win:moveToUnit(hs.layout.left50)
end)

hs.hotkey.bind(hyper, "i", function()
  local win = hs.window.focusedWindow();
  if not win then return end
  win:moveToUnit(hs.layout.maximized)
end)

hs.hotkey.bind(hyper, "k", function()
  local win = hs.window.focusedWindow();
  if not win then return end
  win:moveToUnit('[50,50,0,0]')
end)

hs.hotkey.bind(hyper, "l", function()
  local win = hs.window.focusedWindow();
  if not win then return end
  win:moveToUnit(hs.layout.right50)
end)

local applicationHotkeys = {
  e = 'Finder',
  f = 'Safari',
  t = 'Terminal',
  m = 'Mail',
  n = 'Notes',
  r = 'Reminders',
  o = 'Calendar',
  x = 'Xcode'
}

for key, app in pairs(applicationHotkeys) do
  hs.hotkey.bind(hyper, key, function()
    hs.application.launchOrFocus(app)
  end)
end

-- Mute mac on wake by default
function muteOnWake(eventType)
  if (eventType == hs.caffeinate.watcher.systemDidWake) then
    local output = hs.audiodevice.defaultOutputDevice()
    output:setMuted(true)
  end
end

hs.caffeinate.watcher.new(muteOnWake):start()

