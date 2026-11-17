--[[
Name: SpreadJam timer
Author: Dale Blackwood
Use Case:
	-	Timer counts down footage recorded up to 24hr
	-	Runs on Windows, macOS and Linux
	-	Works with a GDI+ or FreeType 2 text source named "SpreadJam"
Research:
	- 	Adaptive CountDown by Tormy Van Cool
	- 	OBS Stats on Stream by GreenComfyTea
]]
obs             = obslua
APP_NAME        = "SpreadJam"
APP_VERSION     = "1.2.0"
SOURCE_NAME     = "SpreadJam"
MANAGED_KEY     = "spreadjam_managed"
TEXT_PREFIX     = "SJ%d  "
VID_EXTS        = {"mp4", "mpg", "mkv", "m4v", "mov", "flv", "ts"}
-- newest first; the first one OBS knows about is used when creating the source
TEXT_SOURCE_IDS = {"text_gdiplus_v3", "text_gdiplus_v2", "text_gdiplus", "text_ft2_source_v2", "text_ft2_source"}
ALIGN_CENTER    = 0
ALIGN_LEFT      = 1
ALIGN_RIGHT     = 2
ALIGN_TOP       = 4
ALIGN_BOTTOM    = 8
SIZE_SMALL      = 75
SIZE_MEDIUM     = 100
SIZE_LARGE      = 150
SIZE_HUGE       = 200
FREE_JAM        = 99
PROBE_INTERVAL  = 50   -- ms between duration probe attempts
PROBE_ATTEMPTS  = 40   -- give up on a file after PROBE_INTERVAL * PROBE_ATTEMPTS ms

-- settings
local duration_hours = 24
local seconds_total  = 24 * 60 * 60
local count_down     = false
local align_h        = ALIGN_LEFT
local align_v        = ALIGN_BOTTOM
local size           = SIZE_MEDIUM
local enabled        = true
local auto_add       = true

-- state
local seconds_count   = 0
local is_recording    = false
local recording_path  = nil   -- normalised path of the file being recorded
local recording_raw_path = nil -- same file, as OBS reported it
local durations       = {}    -- normalised path -> seconds
local calculating     = {}    -- normalised path -> { path, attempts, source }
local is_calculating  = false
local output_path     = nil
local dim_width       = 1920
local dim_height      = 1080
local last_enabled    = true
local has_exited      = false
local last_error      = nil

-- forward declarations (script_* hooks below call these)
local update_display, calculate_recorded, calculate_recorded_update, load_config

local description = [[
<center>
	<h2>]] .. APP_NAME .. [[ ]] .. APP_VERSION .. [[</h2>
	<h4>By Dale Blackwood</h4>
<p>Counts video footage for a gamejam until the limit is reached.</p>
<p><a href='https://github.com/daleblackwood/spreadjam/blob/main/README.md'>Information</a></p>
<p><a href='https://github.com/daleblackwood/spreadjam/blob/main/SpreadJam.md'>SpreadJam Rules</a></p>
</center>
]]

local function log(msg)
	print("SJ: " .. msg)
end

local function normalise_path(path)
	if path == nil then
		return nil
	end
	path = path:gsub("\\", "/"):gsub("/+", "/")
	return string.lower(path)
end

local function is_file_video(filename)
	local ext = obs.os_get_path_extension(filename)
	if ext == nil then
		return false
	end
	ext = string.lower(ext)
	for i = 1, #VID_EXTS do
		if ext == "." .. VID_EXTS[i] then
			return true
		end
	end
	return false
end

local function sum_durations()
	local total = 0
	for _, d in pairs(durations) do
		total = total + d
	end
	return total
end

------------------------------------------------------------------------------
-- config
------------------------------------------------------------------------------

load_config = function()
	-- borrowed pointer, do not release
	local cfg = obs.obs_frontend_get_profile_config()
	if cfg == nil then
		return
	end
	local path
	if obs.config_get_string(cfg, "Output", "Mode") == "Advanced" then
		if obs.config_get_string(cfg, "AdvOut", "RecType") == "FFmpeg" then
			path = obs.config_get_string(cfg, "AdvOut", "FFFilePath")
		else
			path = obs.config_get_string(cfg, "AdvOut", "RecFilePath")
		end
	else
		path = obs.config_get_string(cfg, "SimpleOutput", "FilePath")
	end
	if path == "" then
		path = nil
	end
	local changed = path ~= output_path
	output_path = path

	local cx = obs.config_get_uint(cfg, "Video", "BaseCX")
	local cy = obs.config_get_uint(cfg, "Video", "BaseCY")
	if cx ~= nil and cy ~= nil and cx > 0 and cy > 0 then
		dim_width, dim_height = cx, cy
	else
		dim_width, dim_height = 1920, 1080
	end

	if changed then
		log("recording path is " .. tostring(output_path))
		durations = {}
	end
	return changed
end

local function get_recording_path()
	local output = obs.obs_frontend_get_recording_output()
	if output == nil then
		return nil
	end
	local settings = obs.obs_output_get_settings(output)
	local path = obs.obs_data_get_string(settings, "path")
	if path == nil or path == "" then
		path = obs.obs_data_get_string(settings, "url")
	end
	obs.obs_data_release(settings)
	obs.obs_output_release(output)
	if path == nil or path == "" then
		return nil
	end
	return path
end

------------------------------------------------------------------------------
-- duration probing
------------------------------------------------------------------------------

local function release_probe(info)
	if info ~= nil and info.source ~= nil then
		obs.obs_source_release(info.source)
		info.source = nil
	end
end

local function release_all_probes()
	obs.timer_remove(calculate_recorded_update)
	for key, info in pairs(calculating) do
		release_probe(info)
		calculating[key] = nil
	end
	is_calculating = false
end

local function queue_probe(key, filepath)
	if calculating[key] == nil then
		calculating[key] = { path = filepath, attempts = 0 }
	end
end

calculate_recorded = function()
	load_config()
	if output_path == nil then
		return
	end
	local dir = obs.os_opendir(output_path)
	if dir == nil then
		log("can't open recording path " .. output_path)
		return
	end
	local files = {}
	local entry
	repeat
		entry = obs.os_readdir(dir)
		if entry and not entry.directory then
			local filename = entry.d_name
			if is_file_video(filename) then
				local filepath = output_path .. "/" .. filename
				local key = normalise_path(filepath)
				files[key] = true
				-- skip the file being written; seconds_count covers it
				if key ~= recording_path then
					local known = durations[key]
					if known == nil or known <= 0 then
						queue_probe(key, filepath)
					end
				end
			end
		end
	until not entry
	obs.os_closedir(dir)

	-- forget files that are gone
	for key, info in pairs(calculating) do
		if files[key] == nil then
			release_probe(info)
			calculating[key] = nil
		end
	end
	for key, _ in pairs(durations) do
		if files[key] == nil then
			durations[key] = nil
		end
	end

	if next(calculating) ~= nil and not is_calculating then
		is_calculating = true
		obs.timer_add(calculate_recorded_update, PROBE_INTERVAL)
	end
end

-- processes one file per tick until the queue is empty
calculate_recorded_update = function()
	local key, info = next(calculating)
	if key == nil then
		obs.timer_remove(calculate_recorded_update)
		is_calculating = false
		log("total duration is " .. sum_durations() .. "s")
		return
	end

	if info.source == nil then
		local s = obs.obs_data_create()
		obs.obs_data_set_bool(s, "is_local_file", true)
		obs.obs_data_set_string(s, "local_file", info.path)
		obs.obs_data_set_bool(s, "looping", false)
		info.source = obs.obs_source_create_private("ffmpeg_source", "SpreadJam Probe", s)
		obs.obs_data_release(s)
		if info.source == nil then
			log("couldn't create probe for " .. info.path)
			calculating[key] = nil
		end
		return
	end

	local duration = obs.obs_source_media_get_duration(info.source)
	if duration > 0 then
		durations[key] = duration / 1000
		log("duration for " .. info.path .. " is " .. durations[key] .. "s")
	elseif info.attempts >= PROBE_ATTEMPTS then
		log("duration failed for " .. info.path)
		-- keep any provisional value from a finished recording
		if durations[key] == nil then
			durations[key] = 0
		end
	else
		info.attempts = info.attempts + 1
		return
	end
	release_probe(info)
	calculating[key] = nil
end

------------------------------------------------------------------------------
-- display
------------------------------------------------------------------------------

local function is_managed(source)
	local settings = obs.obs_source_get_settings(source)
	local managed = obs.obs_data_get_bool(settings, MANAGED_KEY)
	obs.obs_data_release(settings)
	return managed
end

local function pick_text_source_id()
	for i = 1, #TEXT_SOURCE_IDS do
		if obs.obs_source_get_display_name(TEXT_SOURCE_IDS[i]) ~= nil then
			return TEXT_SOURCE_IDS[i]
		end
	end
	return nil
end

-- removes script-created items and hides user-created ones in every scene
local function remove_from_scenes()
	local scenes = obs.obs_frontend_get_scenes()
	if scenes == nil then
		return
	end
	for _, scene_source in pairs(scenes) do
		local scene = obs.obs_scene_from_source(scene_source)
		if scene ~= nil then
			local items = obs.obs_scene_enum_items(scene)
			if items ~= nil then
				for _, item in pairs(items) do
					local item_source = obs.obs_sceneitem_get_source(item)
					if item_source ~= nil and obs.obs_source_get_name(item_source) == SOURCE_NAME then
						if is_managed(item_source) then
							obs.obs_sceneitem_remove(item)
						else
							obs.obs_sceneitem_set_visible(item, false)
						end
					end
				end
				obs.sceneitem_list_release(items)
			end
		end
	end
	obs.source_list_release(scenes)
end

local function build_text()
	local is_freejam = duration_hours == FREE_JAM
	local should_count_down = count_down and not is_freejam

	local seconds_recorded = sum_durations()
	local timer_seconds = seconds_count + seconds_recorded
	local times_up = false
	if should_count_down then
		timer_seconds = seconds_total - timer_seconds
		if timer_seconds < 0 then
			times_up = true
			timer_seconds = -timer_seconds
		end
	end

	local t_seconds     = math.floor(timer_seconds % 60)
	local total_minutes = math.floor(timer_seconds / 60)
	local t_minutes     = math.floor(total_minutes % 60)
	local t_hours       = math.floor(total_minutes / 60)
	local t_prefix      = string.format(TEXT_PREFIX, duration_hours)
	if is_freejam then
		t_prefix = ""
	end

	if output_path == nil then
		return t_prefix .. "Error: Please set recording output path."
	elseif seconds_count == 0 and seconds_recorded == 0 then
		local hour_str = "0"
		if should_count_down then
			hour_str = tostring(duration_hours)
		end
		return t_prefix .. hour_str .. ":00:00"
	elseif not should_count_down and not is_freejam and timer_seconds >= seconds_total then
		return t_prefix .. "■   TIME!"
	end

	local t_sign = times_up and "-" or ""
	local text = t_prefix .. string.format("%s%02d:%02d:%02d", t_sign, t_hours, t_minutes, t_seconds)
	if not is_recording then
		text = text .. "  II"
	elseif is_calculating then
		text = text .. "  ○"
	elseif t_seconds % 2 == 0 then
		text = text .. (times_up and "  ■" or "  ●")
	end
	return text
end

local function apply_style(source, text_data)
	local dim_min = math.min(dim_height, dim_width)
	local font_data = obs.obs_data_create()
	obs.obs_data_set_string(font_data, "face", "Arial")
	obs.obs_data_set_string(font_data, "style", "Regular")
	obs.obs_data_set_int(font_data, "size", math.ceil(dim_min * 0.04 * size * 0.01))
	obs.obs_data_set_obj(text_data, "font", font_data)
	obs.obs_data_release(font_data)

	local id = obs.obs_source_get_unversioned_id(source) or ""
	if id == "text_ft2_source" then
		obs.obs_data_set_int(text_data, "color1", 0xFFFFFFFF)
		obs.obs_data_set_int(text_data, "color2", 0xFFFFFFFF)
	else
		obs.obs_data_set_int(text_data, "color", 0xFFFFFF)
		obs.obs_data_set_int(text_data, "opacity", 100)
	end
end

local function position_item(scene_item)
	local dim_min = math.min(dim_height, dim_width)
	obs.obs_sceneitem_set_order(scene_item, obs.OBS_ORDER_MOVE_TOP)
	obs.obs_sceneitem_set_locked(scene_item, true)
	obs.obs_sceneitem_set_alignment(scene_item, bit.bor(align_h, align_v))
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
	local pos = obs.vec2()
	obs.vec2_set(pos, posx, posy)
	obs.obs_sceneitem_set_pos(scene_item, pos)
end

local function do_update_display()
	if has_exited then
		return
	end
	local was_last_enabled = last_enabled
	last_enabled = enabled
	if not enabled then
		if was_last_enabled then
			remove_from_scenes()
		end
		return
	end

	if load_config() then
		calculate_recorded()
	end

	local text_data = obs.obs_data_create()
	obs.obs_data_set_string(text_data, "text", build_text())

	-- get, or create, the text source
	local source = obs.obs_get_source_by_name(SOURCE_NAME)
	local managed = false
	if source == nil then
		if auto_add then
			local id = pick_text_source_id()
			if id ~= nil then
				obs.obs_data_set_bool(text_data, MANAGED_KEY, true)
				source = obs.obs_source_create(id, SOURCE_NAME, text_data, nil)
				managed = true
			else
				log("no text source type available")
			end
		end
	else
		managed = is_managed(source)
	end

	if source ~= nil then
		if managed then
			apply_style(source, text_data)
		end
		obs.obs_source_update(source, text_data)

		local scene_source = obs.obs_frontend_get_current_scene()
		if scene_source ~= nil then
			local scene = obs.obs_scene_from_source(scene_source)
			if scene ~= nil then
				-- borrowed reference, do not release
				local scene_item = obs.obs_scene_find_source(scene, SOURCE_NAME)
				if scene_item == nil and auto_add then
					scene_item = obs.obs_scene_add(scene, source)
				end
				if scene_item ~= nil then
					if not was_last_enabled then
						obs.obs_sceneitem_set_visible(scene_item, true)
					end
					if managed then
						position_item(scene_item)
					end
				end
			end
			obs.obs_source_release(scene_source)
		end
		obs.obs_source_release(source)
	end
	obs.obs_data_release(text_data)
end

-- log each distinct error once instead of every tick
update_display = function()
	local ok, err = pcall(do_update_display)
	if not ok then
		if err ~= last_error then
			log("error: " .. tostring(err))
		end
		last_error = err
	else
		last_error = nil
	end
end

local function timer_callback()
	if is_recording then
		seconds_count = seconds_count + 1
	end
	update_display()
end

------------------------------------------------------------------------------
-- recording
------------------------------------------------------------------------------

local function activate_recording(on)
	obs.timer_remove(timer_callback)
	if on then
		is_recording = true
		seconds_count = 0
		recording_raw_path = get_recording_path()
		recording_path = normalise_path(recording_raw_path)
		if recording_path ~= nil then
			-- in case an earlier probe already caught it
			release_probe(calculating[recording_path])
			calculating[recording_path] = nil
			durations[recording_path] = nil
		end
		calculate_recorded()
		obs.timer_add(timer_callback, 1000)
	else
		is_recording = false
		-- count the finished file provisionally, then measure it properly
		if recording_path ~= nil then
			if seconds_count > 0 then
				durations[recording_path] = seconds_count
				seconds_count = 0
			end
			queue_probe(recording_path, recording_raw_path)
		end
		recording_path = nil
		recording_raw_path = nil
		calculate_recorded()
	end
	update_display()
end

local function on_event(e)
	if has_exited then
		return
	end
	if e == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then
		activate_recording(true)
	elseif e == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED then
		activate_recording(false)
	elseif e == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED
		or e == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING
		or e == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED then
		update_display()
	elseif e == obs.OBS_FRONTEND_EVENT_PROFILE_CHANGED then
		calculate_recorded()
		update_display()
	elseif e == obs.OBS_FRONTEND_EVENT_EXIT then
		has_exited = true
		obs.timer_remove(timer_callback)
		release_all_probes()
	end
end

------------------------------------------------------------------------------
-- OBS script hooks
------------------------------------------------------------------------------

function script_description()
	return description
end

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

function script_defaults(settings)
	obs.obs_data_set_default_int(settings, "hours", 24)
	obs.obs_data_set_default_int(settings, "align_h", ALIGN_LEFT)
	obs.obs_data_set_default_int(settings, "align_v", ALIGN_BOTTOM)
	obs.obs_data_set_default_int(settings, "size", SIZE_MEDIUM)
	obs.obs_data_set_default_bool(settings, "count_down", false)
	obs.obs_data_set_default_bool(settings, "enabled", true)
	obs.obs_data_set_default_bool(settings, "auto_add", true)
end

function script_update(settings)
	duration_hours = obs.obs_data_get_int(settings, "hours")
	seconds_total = duration_hours * 60 * 60
	align_h = obs.obs_data_get_int(settings, "align_h")
	align_v = obs.obs_data_get_int(settings, "align_v")
	size = obs.obs_data_get_int(settings, "size")
	count_down = obs.obs_data_get_bool(settings, "count_down")
	enabled = obs.obs_data_get_bool(settings, "enabled")
	auto_add = obs.obs_data_get_bool(settings, "auto_add")
	calculate_recorded()
	update_display()
end

function script_load(settings)
	obs.obs_frontend_add_event_callback(on_event)
	-- the script may be loaded while a recording is already running
	if obs.obs_frontend_recording_active() then
		activate_recording(true)
	else
		calculate_recorded()
		update_display()
	end
end

function script_unload()
	obs.timer_remove(timer_callback)
	release_all_probes()
end
