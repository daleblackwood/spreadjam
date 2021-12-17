--[[
Name: SpreadJam timer
Author: Dale Williams
Based upon Adaptive CountDown by Tormy Van Cool
Use Case:
	-	Timer counts down footage recorded up to 24hr
]]
obs             = obslua
APP_NAME        = "SpeadJam"
APP_VERSION     = "1.0.0"

source_name     = ""
duration_hours  = 24;
text_prefix     = ""

seconds_count = 0
seconds_total   = 0
last_text       = ""
activated       = false
count_down		= true
is_recording	= false

hotkey_id       = obs.OBS_INVALID_HOTKEY_ID

VID_EXTS		= {"mp4", "mpg", "mkv", "m4v", "mov"}

durations		= {}
calculating		= {}

-- Function to set the time text
function set_time_text()
	local seconds_recorded = 0
	for k, duration in pairs(durations) do
		seconds_recorded = seconds_recorded + duration
	end

	count = seconds_count + seconds_recorded
	if count_down then
		count = seconds_total - count
	end

	local text = ''
	local seconds       = math.floor(count % 60)
	local total_minutes = math.floor(count / 60)
	local minutes       = math.floor(total_minutes % 60)
	local hours         = math.floor(total_minutes / 60)

	text = string.format(text_prefix, duration_hours) .. 
        string.format("%02d:%02d:%02d", hours, minutes, seconds)

	if count >= seconds_total then
        text = "Time's up!"	
	end

	if text ~= last_text then
		local source = obs.obs_get_source_by_name(source_name)
		if source ~= nil then
			local settings = obs.obs_data_create()
			obs.obs_data_set_string(settings, "text", text)
			obs.obs_source_update(source, settings)
			obs.obs_data_release(settings)
			obs.obs_source_release(source)
		end
	end
	last_text = text
end

function calculate_seconds_recorded()
	local dirpath = "C:/Users/dalew/Videos/Captures"
	local dir = obs.os_opendir(dirpath)
	local entry
	repeat
		entry = obs.os_readdir(dir)
		if entry then
			local filename = entry.d_name
			local filepath = dirpath .. "/" .. filename
			if is_file_video(filename) then
				calculating[filepath] = { attempts = 0 }
			end
		end
	until not entry
	obs.os_closedir(dir)
	calculate_seconds_recorded_update()
end

function calculate_seconds_recorded_update()
	obs.timer_remove(calculate_seconds_recorded_update)
	for filepath, info in pairs(calculating) do
		local pending = false
		if info then
			if info.source then
				-- try to read the duration
				duration = obs.obs_source_media_get_duration(info.source)
				if duration > 0 or info.attempts > 4 then
					print("calculated " .. duration .. " for " .. filepath)
					obs.obs_source_release(info.source)
					durations[filepath] = duration
					calculating[filepath] = nil
				else
					info.attempts = info.attempts + 1
					pending = true
				end
			else
				-- create a source
				print("calculating " .. filepath .. "...")
				info.source = obs.obs_source_create_private("ffmpeg_source", "Global Media Source", nil)
				info.data = obs.obs_data_create()
				obs.obs_data_set_string(s, "local_file", filepath)
				obs.obs_source_update(info.source, info.data)
				pending = true
			end
		end
		if pending then
			-- if we processed one, let it through
			obs.timer_add(calculate_seconds_recorded_update, 500)
			return
		end
	end
end

-- function calculate_video_duration(filepath)
-- 	if durations[filepath] then
-- 		return durations[filepath]
-- 	end
-- 	local duration = 0;
-- 	print("calculate " .. filepath)
-- 	local source = obs.obs_source_create_private("ffmpeg_source", "Global Media Source", nil)
--   	local s = obs.obs_data_create()
--   	obs.obs_data_set_string(s, "local_file", filepath)
--   	obs.obs_source_update(source, s)
-- 	obs.obs_source_update_properties(source)
-- 	duration = obs.obs_source_media_get_duration(source)
-- 	print("calculated " .. filepath .. " is " .. duration)
-- 	durations[filepath] = duration
-- 	return duration
-- end

function is_file_video(filename)
	local ext = obs.os_get_path_extension(filename)
	if ext == nil then
		return false
	end
	ext = string.lower(ext)
	for i = 1, #VID_EXTS do
		local matchkey = "." .. VID_EXTS[i]
		if matchkey == ext then
			return true
		end
	end
	return false
end

function timer_callback()
	if is_recording then
		seconds_count = seconds_count + 1
	end

	if activated then
		set_time_text()
	end
end

function activate(activating)
	if activated == activating then
		return
	end

	activated = activating

	if activating then
		set_time_text()
	end
end

-- Called when a source is activated/deactivated
function activate_signal(cd, activating)
	local source = obs.calldata_source(cd, "source")
	if source ~= nil then
		local name = obs.obs_source_get_name(source)
		if (name == source_name) then
			activate(activating)
		end
	end
end

function source_activated(cd)
	activate_signal(cd, true)
end

function source_deactivated(cd)
	activate_signal(cd, false)
end

function reset(pressed)
	if not pressed then
		return
	end

	activate(false)
	local source = obs.obs_get_source_by_name(source_name)
	if source ~= nil then
		local active = obs.obs_source_active(source)
		obs.obs_source_release(source)
		activate(active)
	end
end

----------------------------------------------------------

-- A function named script_properties defines the properties that the user
-- can change for the entire script module itself
function script_properties()
	local props = obs.obs_properties_create()
	local p = obs.obs_properties_add_list(props, "source", "Timer Source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
	local sources = obs.obs_enum_sources()
	if sources ~= nil then
		for _, source in ipairs(sources) do
			source_id = obs.obs_source_get_unversioned_id(source)
			if source_id == "text_gdiplus" or source_id == "text_ft2_source" then
				local name = obs.obs_source_get_name(source)
				obs.obs_property_list_add_string(p, name, name)
			end
		end
	end
	obs.source_list_release(sources)

    local f = obs.obs_properties_add_list(props, "hours", "Hours", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	obs.obs_property_list_add_int(f, "Full 24h", 24)
    obs.obs_property_list_add_int(f, "Mini 12h", 12)

	obs.obs_properties_add_text(props, "text_prefix", "Prefix", obs.OBS_TEXT_DEFAULT)

	obs.obs_properties_add_bool(props, "count_down", "Count Down")

	return props
end

-- A function named script_description returns the description shown to
-- the user
function script_description()
	return APP_NAME .. " " .. APP_VERSION .. "\n\n" ..
        "Counts video footage for a gamejam until the limit is reached."
end

-- A function named script_update will be called when settings are changed
function script_update(settings)
	activate(false)

    duration_hours = obs.obs_data_get_int(settings, "hours")
	seconds_total = (duration_hours*60*60) + (obs.obs_data_get_int(settings, "minutes")*60) + obs.obs_data_get_int(settings, "seconds")
	source_name = obs.obs_data_get_string(settings, "source")
    text_prefix = obs.obs_data_get_string(settings, "text_prefix")
	count_down = obs.obs_data_get_bool(settings, "count_down")

	reset(true)
end

-- A function named script_defaults will be called to set the default settings
function script_defaults(settings)
	obs.obs_data_set_default_int(settings, "hours", 24)
	obs.obs_data_set_default_int(settings, "minutes", 0)
	obs.obs_data_set_default_int(settings, "seconds", 0)
    obs.obs_data_set_default_string(settings, "text_prefix", "SJ%dh ║ ")
    obs.obs_data_set_default_bool(settings, "count_down", true)
end

-- A function named script_save will be called when the script is saved
--
-- NOTE: This function is usually used for saving extra data (such as in this
-- case, a hotkey's save data).  Settings set via the properties are saved
-- automatically.
function script_save(settings)
	local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
	obs.obs_data_array_release(hotkey_save_array)
end

function activate_recording(on)
	is_recording = on
	obs.timer_remove(timer_callback)
	if is_recording then
		seconds_count = 0
		calculate_seconds_recorded()
		obs.timer_add(timer_callback, 1000)
	end
end

-- a function named script_load will be called on startup
function script_load(settings)
	-- Connect hotkey and activation/deactivation signal callbacks
	--
	-- NOTE: These particular script callbacks do not necessarily have to
	-- be disconnected, as callbacks will automatically destroy themselves
	-- if the script is unloaded.  So there's no real need to manually
	-- disconnect callbacks that are intended to last until the script is
	-- unloaded.
	local sh = obs.obs_get_signal_handler()
	obs.signal_handler_connect(sh, "source_activate", source_activated)
	obs.signal_handler_connect(sh, "source_deactivate", source_deactivated)
	obs.obs_frontend_add_event_callback(on_event)

	local hotkey_save_array = obs.obs_data_get_array(settings, "reset_hotkey")
	obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
	obs.obs_data_array_release(hotkey_save_array)
end

function on_event(event)
	if event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then
		activate_recording(true)
	elseif event == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED then
		activate_recording(false)
	end
end