local EXT_SECTION = "SE_RUNNER_SCRIPT_SYSTEM"
local EXT_KEY = "SE_MESSAGE_QUEUE"
local id_index = 8

local current = reaper.GetExtState(EXT_SECTION, EXT_KEY)
local new_msg = current .. tostring(id_index) .. ";"
reaper.SetExtState(EXT_SECTION, EXT_KEY, new_msg, false)
