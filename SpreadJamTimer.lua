--[[
Name: SpreadJam timer
Author: Dale Williams
Use Case:
	-	Timer counts down footage recorded up to 24hr
Reasearch:
	- 	Adaptive CountDown by Tormy Van Cool
	- 	OBS Stats on Stream by GreenComfyTea
]]
obs             = obslua
APP_NAME        = "SpeadJam"
APP_VERSION     = "1.0.0"
SOURCE_NAME 	= "SpreadJam"
VID_EXTS		= {"mp4", "mpg", "mkv", "m4v", "mov"}

duration_hours  = 24;
text_prefix     = ""

seconds_count = 0
seconds_total   = 0
last_text       = ""
activated       = false
count_down		= true
is_recording	= false

durations		= {}
calculating		= {}
is_calculating  = false
config			= {}
output_path		= nil
dim_width		= 0
dim_height		= 0

ALIGN_CENTER 	= 0
ALIGN_LEFT		= 1
ALIGN_RIGHT		= 2
ALIGN_TOP		= 4
ALIGN_BOTTOM	= 8

-- Function to set the time text
function update_display()
	-- calculate display seconds
	local seconds_recorded = 0
	for k, duration in pairs(durations) do
		seconds_recorded = seconds_recorded + duration
	end
	timer_seconds = seconds_count + seconds_recorded
	if count_down then
		timer_seconds = seconds_total - timer_seconds
	end

	-- determine text to display
	local text = ''
	local t_seconds     = math.floor(timer_seconds % 60)
	local total_minutes = math.floor(timer_seconds / 60)
	local t_minutes     = math.floor(total_minutes % 60)
	local t_hours       = math.floor(total_minutes / 60)
	local t_prefix 	    = string.format(text_prefix, duration_hours)
	if output_path == nil then
		text = t_prefix .. "Error: Please set recording output path."
	elseif seconds_count == 0 and seconds_recorded == 0 then
		text = t_prefix .. duration_hours .. ":00:00 [ready]"	
	elseif timer_seconds >= seconds_total then
        text = t_prefix .. "Time up!"	
	else
		text = t_prefix .. string.format("%02d:%02d:%02d", t_hours, t_minutes, t_seconds)
		if is_recording == false then
			text = text .. " [paused]"
		elseif is_calculating then
			text = text .. " [...]"
		end
	end

	if text ~= last_text then
		-- set data
		local s = obs.obs_data_create()
		obs.obs_data_set_string(s, "text", text)

		local dim_min = math.min(dim_height, dim_width)

		-- update font		
		local font = obs.obs_data_create()
		local font_size = math.ceil(dim_min * 0.04)
		obs.obs_data_set_string(font, "face", "Arial")
		obs.obs_data_set_int(font, "size", font_size)
		obs.obs_data_set_obj(s, "font", font)
		obs.obs_data_set_int(s, "color", 0xFFFFFFFF)

		-- get or update source
		local source = obs.obs_get_source_by_name(SOURCE_NAME)
		if source == nil then
			source = obs.obs_source_create("text_gdiplus", SOURCE_NAME, s, nil)
		else
			obs.obs_source_update(source, s)
		end

		-- confirm or add to scene
		local scene_source = obs.obs_frontend_get_current_scene()
		local scene = obs.obs_scene_from_source(scene_source)
		local scene_item = obs.obs_scene_sceneitem_from_source(scene, source)
		if scene_item == nil then
			scene_item = obs.obs_scene_add(scene, source)
		end

		-- position
		obs.obs_sceneitem_set_order(scene_item, obs.OBS_ORDER_MOVE_TOP)
		obs.obs_sceneitem_set_locked(scene_item, true)
		obs.obs_sceneitem_set_alignment(scene_item, bit.bor(ALIGN_LEFT, ALIGN_BOTTOM))
		local pos = obs.vec2()
		local pad = math.ceil(dim_min * 0.05)
		obs.vec2_set(pos, pad, dim_height - pad)
		obs.obs_sceneitem_set_pos(scene_item, pos)

		-- release
		obs.obs_source_release(source)
		obs.obs_data_release(s)
		obs.obs_data_release(font)
	end
	last_text = text
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
    duration_hours = obs.obs_data_get_int(settings, "hours")
	seconds_total = duration_hours * 60 * 60
    text_prefix = obs.obs_data_get_string(settings, "text_prefix")
	count_down = obs.obs_data_get_bool(settings, "count_down")
end

-- A function named script_defaults will be called to set the default settings
function script_defaults(settings)
	obs.obs_data_set_default_int(settings, "hours", 24)
    obs.obs_data_set_default_string(settings, "text_prefix", "SJ%dh ║ ")
    obs.obs_data_set_default_bool(settings, "count_down", true)
end

-- A function named script_save will be called when the script is saved
function script_save(settings)
	return
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

function on_event(event)
	if event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then
		activate_recording(true)
	elseif event == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED then
		activate_recording(false)
	end
end

function calculate_recorded()
	is_calculating = true
	local dir = obs.os_opendir(output_path)
	local entry
	repeat
		entry = obs.os_readdir(dir)
		if entry then
			local filename = entry.d_name
			local filepath = output_path .. "/" .. filename
			if is_file_video(filename) then
				calculating[filepath] = { attempts = 0 }
			end
		end
	until not entry
	obs.os_closedir(dir)
	calculate_recorded_update()
end

function calculate_recorded_update()
	is_calculating = false
	obs.timer_remove(calculate_recorded_update)
	for filepath, info in pairs(calculating) do
		local pending = false
		if info then
			if info.source then
				-- try to read the duration
				duration = obs.obs_source_media_get_duration(info.source)
				if duration > 0 or info.attempts > 4 then
					--print("calculated " .. duration .. " for " .. filepath)
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
				--print("calculating " .. filepath .. "...")
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

function load_config()
	config = {}
	local profile = obs.obs_frontend_get_current_profile():gsub("[^%w_ ]", ""):gsub("%s", "_");
	local profile_relative_path = "obs-studio\\basic\\profiles\\" .. profile .. "\\basic.ini";
	-- char dst[512];
	local profile_path = "                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ";
	obs.os_get_abs_path("..\\..\\config\\" .. profile_relative_path, profile_path, #profile_path);
	if not obs.os_file_exists(profile_path) then	
		obs.os_get_config_path(profile_path, #profile_path, profile_relative_path);
		if not obs.os_file_exists(profile_path) then	
			print("Config file not found.");
			return;
		end
	end
	local config_text = obs.os_quick_read_utf8_file(profile_path);
	if config_text == nil then 
		print("Couldn't read config file.");
		return;
	end
	local section;
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
	local res = config["RecRescaleRes"]
	if res ~= nil then
		local xi = string.find(res, 'x')
		if xi > 0 then
			dim_width = tonumber(string.sub(0, xi))
			dim_height = tonumber(string.sub(xi + 1))
		else
			res = nil
		end
	end
	if res == nil then
		dim_width = 1920
		dim_height = 1080
	end
end