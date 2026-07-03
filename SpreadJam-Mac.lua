--[[
Name: SpreadJam timer
Author: Dale Blackwood
Use Case:
	-	Timer counts down footage recorded up to 24hr
Portions adapted from:
	- 	Adaptive CountDown by Tormy Van Cool
	- 	OBS Stats on Stream by GreenComfyTea
]]
obs             = obslua
APP_NAME        = "SpreadJam"
APP_VERSION     = "1.1.0"
SOURCE_NAME 	= "SpreadJam"
TEXT_PREFIX		= "SJAM%d "
VID_EXTS		= {"mp4", "mpg", "mkv", "m4v", "mov"}
FREE_JAM		= 99

duration_hours  = 24;
seconds_count = 0
seconds_total   = 0
count_down		= false
is_recording	= false
enabled			= true
auto_add		= true

durations		= {}
calculating		= {}
is_calculating  = false
config			= {}
output_path		= nil
last_enabled 	= false
has_exited		= false

local description = [[
<center>
	<h2>]] .. APP_NAME .. [[ ]] .. APP_VERSION .. [[</h2>
	<h4>By Dale Blackwood</h4>
<p>Counts video footage for a gamejam until the limit is reached.</p>
<p><a href='https://github.com/daleblackwood/spreadjam/blob/main/README.md'>Information</a></p>
<p><a href='https://github.com/daleblackwood/spreadjam/blob/main/SpreadJam.md'>SpreadJam Rules</a></p>
</center>
]]

function script_description()
	return description
end

-- Function to set the time text
function update_display()
	if has_exited then
		return
	end
	local was_last_enabled = last_enabled
	last_enabled = enabled
	if enabled == false then
		if was_last_enabled then
			remove_all()
		end
		return
	end

	local is_freejam = duration_hours == FREE_JAM
	local should_count_down = count_down and not is_freejam

	-- calculate display seconds
	local seconds_recorded = 0
	for k, duration in pairs(durations) do
		seconds_recorded = seconds_recorded + duration
	end
	timer_seconds = seconds_count + seconds_recorded
	if should_count_down then
		timer_seconds = seconds_total - timer_seconds
	end

	-- determine text to display
	local text = ''
	local t_seconds     = math.floor(timer_seconds % 60)
	local total_minutes = math.floor(timer_seconds / 60)
	local t_minutes     = math.floor(total_minutes % 60)
	local t_hours       = math.floor(total_minutes / 60)
	local t_prefix 	    = string.format(TEXT_PREFIX, duration_hours)
	if is_freejam then
		t_prefix = ""
	end

	if output_path == nil then
		text = t_prefix .. "Error: Please set recording output path."
	elseif seconds_count == 0 and seconds_recorded == 0 then
		local hour_str = "0"
		if should_count_down then
			hour_str = duration_hours
		end
		text = t_prefix .. hour_str .. ":00:00"	
	elseif timer_seconds >= seconds_total and not is_freejam then
        text = t_prefix .. "■  TIME!"	
	else
		text = t_prefix .. string.format("%d:%02d:%02d", t_hours, t_minutes, t_seconds)
		if is_recording == false then
			text = text .. " ||"
		elseif is_calculating then
			text = text .. " ○"
		elseif math.floor(t_seconds / 2) == t_seconds / 2 then
			text = text .. " ●"
		end
	end

	-- set data
	local text_data = obs.obs_data_create()
	obs.obs_data_set_string(text_data, "text", text)

	-- get or update source
	local source = obs.obs_get_source_by_name(SOURCE_NAME)
	if source == nil then
		print("create a text field named " .. SOURCE_NAME)
	else
		obs.obs_source_update(source, text_data)
	end

	-- confirm or add to scene
	local scene_source = obs.obs_frontend_get_current_scene()
	local scene = obs.obs_scene_from_source(scene_source)
	local scene_item = obs.obs_scene_sceneitem_from_source(scene, source)
	if scene_item == nil and auto_add then
		scene_item = obs.obs_scene_add(scene, source)
	end

	-- release
	if source ~= nil then
		obs.obs_source_release(source)
	end
	obs.obs_data_release(text_data)
end

function timer_callback()
	if is_recording then
		seconds_count = seconds_count + 1
	end
	update_display()
end

-- A function named script_properties defines the properties that the user
-- can change for the entire script module itself
function script_properties()
	local props = obs.obs_properties_create()

    local o_hours = obs.obs_properties_add_list(props, "hours", "Jam Hours", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	obs.obs_property_list_add_int(o_hours, "24 Hour Spreadjam", 24)
    obs.obs_property_list_add_int(o_hours, "12 Hour HalfJam", 12)
    obs.obs_property_list_add_int(o_hours, "8 Hour Proto", 8)
    obs.obs_property_list_add_int(o_hours, "6 Hour Proto", 6)
    obs.obs_property_list_add_int(o_hours, "FreeJam", FREE_JAM)

	obs.obs_properties_add_bool(props, "count_down", "Count Down")
	obs.obs_properties_add_bool(props, "auto_add", "Automatically Add")
	obs.obs_properties_add_bool(props, "enabled", "Enabled")

	return props
end

-- A function named script_update will be called when settings are changed
function script_update(settings)
    duration_hours = obs.obs_data_get_int(settings, "hours")
	seconds_total = duration_hours * 60 * 60
	count_down = obs.obs_data_get_bool(settings, "count_down")
	enabled = obs.obs_data_get_bool(settings, "enabled")
	auto_add = obs.obs_data_get_bool(settings, "auto_add")
	calculate_recorded()
	update_display()
end

-- A function named script_defaults will be called to set the default settings
function script_defaults(settings)
	obs.obs_data_set_default_int(settings, "hours", 24)
    obs.obs_data_set_default_bool(settings, "count_down", false)
    obs.obs_data_set_default_bool(settings, "enabled", true)
    obs.obs_data_set_default_bool(settings, "auto_add", true)
end

-- A function named script_save will be called when the script is saved
function script_save(settings)
	return settings
end

function activate_recording(on)
	is_recording = on
	obs.timer_remove(timer_callback)
	if is_recording then
		seconds_count = 0
		load_config()
		if output_path then
			calculate_recorded()
			obs.timer_add(timer_callback, 1000)
		end
	end
	update_display()
end

-- a function named script_load will be called on startup
function script_load(settings)
	obs.obs_frontend_add_event_callback(on_event)
	load_config()
	update_display()
end

function on_event(e)
	if e == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then
		activate_recording(true)
	elseif e == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED then
		activate_recording(false)
	elseif e == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
		update_display()
	elseif e == obs.OBS_FRONTEND_EVENT_PROFILE_CHANGED then
		load_config()
		update_display()
	elseif e == obs.OBS_FRONTEND_EVENT_EXIT then
		on_exit()
	end
end

function calculate_recorded()
	if is_calculating then
		return
	end
	is_calculating = true	
	load_config()
	local dir = obs.os_opendir(output_path)
	print("calculating recorded footage for " .. output_path)
	local files = {}
	local entry
	repeat
		entry = obs.os_readdir(dir)
		if entry then
			local filename = entry.d_name
			local filepath = output_path .. "/" .. filename
			if is_file_video(filename) then
				calculating[filepath] = { attempts = 0 }
				files[filepath] = true
			end
		end
	until not entry
	obs.os_closedir(dir)
	for k,v in pairs(calculating) do
		if files[k] == nil then
			calculating[k] = nil
		end
	end
	for k,v in pairs(durations) do
		if files[k] == nil then
			durations[k] = nil
		end
	end
	calculate_recorded_update()
end

function calculate_recorded_update()
	if enabled == false then
		return
	end
	is_calculating = false
	obs.timer_remove(calculate_recorded_update)
	for filepath, info in pairs(calculating) do
		local pending = false
		if info then
			if info.source ~= nil then
				-- try to read the duration
				duration = obs.obs_source_media_get_duration(info.source)
				if duration > 0 or info.attempts > 4 then
					obs.obs_source_release(info.source)
					info.source = nil
					durations[filepath] = duration / 1000
					calculating[filepath] = nil
				else
					info.attempts = info.attempts + 1
					pending = true
				end
			else
				-- create a source
				info.source = obs.obs_source_create_private("ffmpeg_source", "Global Media Source", nil)
				local s = obs.obs_data_create()
				obs.obs_data_set_string(s, "local_file", filepath)
				obs.obs_source_update(info.source, s)
				obs.obs_source_set_monitoring_type(info.source, obs.OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT)
  				obs.obs_data_release(s)
				pending = true
			end
		end
		if pending then
			-- if we processed one, let it through
			is_calculating = true
			obs.timer_add(calculate_recorded_update, 10)
			return
		end
	end
end

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

function remove_all()
	local scenes = obs.obs_frontend_get_scenes()
	for k, scene_source in pairs(scenes) do
		local scene = obs.obs_scene_from_source(scene_source)
		if scene ~= nil then
			local scene_items = obs.obs_scene_enum_items(scene)
			for j, scene_item in pairs(scene_items) do
				local item_source = obs.obs_sceneitem_get_source(scene_item)
				if item_source ~= nil then
					local item_name = obs.obs_source_get_name(item_source)
					if item_name == SOURCE_NAME then
						obs.obs_sceneitem_remove(scene_item)
					end
				end
			end
		end
	end
	obs.source_list_release(scenes)
	calculating = nil
end

function on_exit()
	is_recording = false
	enabled = false
	has_exited = true
	obs.timer_remove(timer_callback)
	obs.timer_remove(calculate_recorded_update)
	obs.obs_frontend_remove_event_callback(on_event)
end

local ffi = require("ffi")

function load_config()
    config = {}
    local profile = obs.obs_frontend_get_current_profile():gsub("[^%w_ ]", ""):gsub("%s", "_")
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    local sep = package.config:sub(1, 1)
    
    -- Construct path based on OS standard locations
    local base_path = ""
    if package.config:sub(1, 1) == "/" then
        -- macOS / Linux
        base_path = home .. "/Library/Application Support/obs-studio"
        if not obs.os_file_exists(base_path) then
            base_path = home .. "/.config/obs-studio"
        end
    else
        -- Windows
        base_path = os.getenv("APPDATA") .. "\\obs-studio"
    end
    
    local profile_path = base_path .. sep .. "basic" .. sep .. "profiles" .. sep .. profile .. sep .. "basic.ini"

    if not obs.os_file_exists(profile_path) then
        print("Config file not found at: " .. profile_path)
        return
    end

    local config_text = obs.os_quick_read_utf8_file(profile_path)
    if config_text == nil then
        print("Couldn't read config file.")
        return
    end

    local section
    for line in config_text:gmatch("[^\r\n]+") do
        local section_match = line:match('^%[([^%[%]]+)%]$')
        if section_match then
            section = section_match
        else
            local key, value = line:match('^([%w|_]+)%s-=%s-(.+)$')
            if key and value ~= nil then
                local config_key = section .. "." .. key
                config[config_key] = value
            end
        end
    end
    output_path = config["SimpleOutput.FilePath"]
end