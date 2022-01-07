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
APP_NAME        = "SpreadJam"
APP_VERSION     = "1.0.0"
SOURCE_NAME 	= "SpreadJam"
TEXT_PREFIX		= "SJ%d  "
VID_EXTS		= {"mp4", "mpg", "mkv", "m4v", "mov"}
ALIGN_CENTER 	= 0
ALIGN_LEFT		= 1
ALIGN_RIGHT		= 2
ALIGN_TOP		= 4
ALIGN_BOTTOM	= 8
SIZE_SMALL		= 75
SIZE_MEDIUM		= 100
SIZE_LARGE		= 150
SIZE_HUGE		= 200
FREE_JAM		= 99

duration_hours  = 24;
seconds_count = 0
seconds_total   = 0
count_down		= false
is_recording	= false
align_h			= ALIGN_LEFT
align_v			= ALIGN_BOTTOM
size			= SIZE_MEDIUM
enabled			= true
auto_add		= true

durations		= {}
calculating		= {}
is_calculating  = false
config			= {}
output_path		= nil
dim_width		= 0
dim_height		= 0
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
        text = t_prefix .. "■   TIME!"	
	else
		text = t_prefix .. string.format("%02d:%02d:%02d", t_hours, t_minutes, t_seconds)
		if is_recording == false then
			text = text .. "  II"
		elseif is_calculating then
			text = text .. "  ○"
		elseif math.floor(t_seconds / 2) == t_seconds / 2 then
			text = text .. "  ●"
		end
	end

	-- set data
	local text_data = obs.obs_data_create()
	obs.obs_data_set_string(text_data, "text", text)

	local dim_min = math.min(dim_height, dim_width)

	-- update font		
	local font_data = obs.obs_data_create()
	local font_size = math.ceil(dim_min * 0.04 * size * 0.01)
	obs.obs_data_set_string(font_data, "face", "Arial")
	obs.obs_data_set_int(font_data, "size", font_size)
	obs.obs_data_set_obj(text_data, "font", font_data)
	obs.obs_data_set_int(text_data, "color", 0xFFFFFFFF)

	-- get or update source
	local source = obs.obs_get_source_by_name(SOURCE_NAME)
	if source == nil then
		source = obs.obs_source_create("text_gdiplus", SOURCE_NAME, text_data, nil)
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

	if scene_item ~= nil then
		-- position
		obs.obs_sceneitem_set_order(scene_item, obs.OBS_ORDER_MOVE_TOP)
		obs.obs_sceneitem_set_locked(scene_item, true)
		obs.obs_sceneitem_set_alignment(scene_item, bit.bor(align_h, align_v))
		local pos = obs.vec2()
		local pad = math.ceil(dim_min * 0.03)
		local posx = pad
		if align_h == ALIGN_CENTER then
			posx = dim_width * 0.5
		elseif align_h == ALIGN_RIGHT then
			posx = dim_width - pad
		end
		local posy = pad
		if align_v == ALIGN_CENTER then
			posy = dim_height * 0.5
		elseif align_v == ALIGN_BOTTOM then
			posy = dim_height - pad
		end
		obs.vec2_set(pos, posx, posy)
		obs.obs_sceneitem_set_pos(scene_item, pos)
	end

	-- release
	if source ~= nil then
		obs.obs_source_release(source)
	end
	obs.obs_data_release(text_data)
	obs.obs_data_release(font_data)
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

	local o_align_h = obs.obs_properties_add_list(props, "align_h", "Position Horizontal", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	obs.obs_property_list_add_int(o_align_h, "Left", ALIGN_LEFT)
    obs.obs_property_list_add_int(o_align_h, "Center", ALIGN_CENTER)
    obs.obs_property_list_add_int(o_align_h, "Right", ALIGN_RIGHT)

	local o_align_v = obs.obs_properties_add_list(props, "align_v", "Position Vertical", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
	obs.obs_property_list_add_int(o_align_v, "Top", ALIGN_TOP)
    obs.obs_property_list_add_int(o_align_v, "Middle", ALIGN_CENTER)
    obs.obs_property_list_add_int(o_align_v, "Bottom", ALIGN_BOTTOM)

	local o_size = obs.obs_properties_add_list(props, "size", "Display Size", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_INT)
    obs.obs_property_list_add_int(o_size, "Medium", SIZE_MEDIUM)
	obs.obs_property_list_add_int(o_size, "Small", SIZE_SMALL)
	obs.obs_property_list_add_int(o_size, "Large", SIZE_LARGE)
	obs.obs_property_list_add_int(o_size, "Huge", SIZE_HUGE)

	obs.obs_properties_add_bool(props, "count_down", "Count Down")
	obs.obs_properties_add_bool(props, "auto_add", "Automatically Add")
	obs.obs_properties_add_bool(props, "enabled", "Enabled")

	return props
end

-- A function named script_update will be called when settings are changed
function script_update(settings)
    duration_hours = obs.obs_data_get_int(settings, "hours")
	seconds_total = duration_hours * 60 * 60
	align_h = obs.obs_data_get_int(settings, "align_h")
	align_v = obs.obs_data_get_int(settings, "align_v")
	size = obs.obs_data_get_int(settings, "size")
	count_down = obs.obs_data_get_bool(settings, "count_down")
	enabled = obs.obs_data_get_bool(settings, "enabled")
	auto_add = obs.obs_data_get_bool(settings, "auto_add")
	update_display()
end

-- A function named script_defaults will be called to set the default settings
function script_defaults(settings)
	obs.obs_data_set_default_int(settings, "hours", 24)
	obs.obs_data_set_default_int(settings, "align_h", ALIGN_LEFT)
	obs.obs_data_set_default_int(settings, "align_v", ALIGN_BOTTOM)
	obs.obs_data_set_default_int(settings, "size", SIZE_MEDIUM)
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
end

function on_exit()
	is_recording = false
	enabled = false
	has_exited = true
	obs.timer_remove(timer_callback)
	obs.timer_remove(calculate_recorded_update)
	obs.obs_frontend_remove_event_callback(on_event)
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
	local res = config["FFRescaleRes"] or config["RescaleRes"]
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