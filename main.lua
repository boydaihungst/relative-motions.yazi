--- @since 25.2.7
--- NOTE: REMOVE :parent() :name() :is_hovered() :ext() after upgrade to v25.4.4
--- https://github.com/sxyazi/yazi/pull/2572

local PackageName = "relative-motions"
local M = {}
-- stylua: ignore
local MOTIONS_AND_OP_KEYS = {
	{ on = "0" }, { on = "1" }, { on = "2" }, { on = "3" }, { on = "4" },
	{ on = "5" }, { on = "6" }, { on = "7" }, { on = "8" }, { on = "9" },
	-- commands
	{ on = "d" }, { on = "v" }, { on = "y" }, { on = "x" },
	-- tab commands
	{ on = "t" }, { on = "L" }, { on = "H" }, { on = "w" },
	{ on = "W" }, { on = "<" }, { on = ">" }, { on = "~" },
	-- movement
	{ on = "g" }, { on = "j" }, { on = "k" }, { on = "<Down>" }, { on = "<Up>" }
}

-- stylua: ignore
local MOTION_KEYS = {
	{ on = "0" }, { on = "1" }, { on = "2" }, { on = "3" }, { on = "4" },
	{ on = "5" }, { on = "6" }, { on = "7" }, { on = "8" }, { on = "9" },
	-- movement
	{ on = "g" }, { on = "j" }, { on = "k" }
}

-- stylua: ignore
local DIRECTION_KEYS = {
	{ on = "j" }, { on = "k" }, { on = "<Down>" }, { on = "<Up>" },
	-- tab movement
	{ on = "t" }
}

-----------------------------------------------
----------------- R E N D E R -----------------
-----------------------------------------------

local function warn(s, ...)
	ya.notify { title = PackageName, content = string.format(s, ...), timeout = 3, level = "warn" }
end

local render_motion_setup = ya.sync(function(_)
	ya.render()

	Status.motion = function() return ui.Span("") end

	Status.children_redraw = function(self, side)
		local lines = {}
		if side == self.RIGHT then
			lines[1] = self:motion(self)
		end
		for _, c in ipairs(side == self.RIGHT and self._right or self._left) do
			lines[#lines + 1] = (type(c[1]) == "string" and self[c[1]] or c[1])(self)
		end
		return ui.Line(lines)
	end

	-- TODO: check why it doesn't work line this
	-- Status:children_add(Status.motion, 100, Status.RIGHT)
end)

local render_motion = ya.sync(function(_, motion_num, motion_cmd)
	ya.render()

	Status.motion = function(self)
		if not motion_num then
			return ui.Span("")
		end

		local style = self:style()

		local motion_span
		if not motion_cmd then
			motion_span = ui.Span(string.format(" %d ", motion_num)):style(style.main)
		else
			motion_span = ui.Span(string.format(" %d%s ", motion_num, motion_cmd)):style(style.main)
		end
		return ui.Line {
			ui.Span(
				(th or THEME).status.separator_open or ((th or THEME).status.sep_right and (th or THEME).status.sep_right.open)
			)
				:fg(style.main.bg),
			motion_span,
			ui.Span(
				(th or THEME).status.separator_close
					or ((th or THEME).status.sep_right and (th or THEME).status.sep_right.close)
			)
				:fg(style.main.bg)
				:bg(style.alt.bg),
			ui.Span(" "),
		}
	end
end)

---@enum render_mode
local RENDER_MODE = {
	SHOW_NUMBERS_ABSOLUTE = 0,
	SHOW_NUMBERS_RELATIVE = 1,
	SHOW_NUMBERS_RELATIVE_ABSOLUTE = 2,
}
--- Render line numbers based on RENDER_MODE
--- @param mode render_mode
--- @param styles {hovered: {fg: any, bg: any}, normal: {fg: any, bg: any}}
--- @param resizable_entity_children_ids table<number, number> input list of entity children which are resizable e.g: {4, 6} id=4 is filname and find highlight, id=6 is symlink. You have to override those `Entity:method` to be able to make this work
--- @return nil
local render_numbers = ya.sync(function(state, mode, styles, resizable_entity_children_ids)
	ya.render()

	local smart_truncate_entity_plugin_ok, smart_truncate_entity_plugin = pcall(require, "smart-truncate")
	Entity.number = function(_, index, file, hovered, last_index)
		local idx
		local offset = 1
		if mode == RENDER_MODE.SHOW_NUMBERS_RELATIVE then
			idx = math.abs(hovered - index)
			offset = idx >= 100 and 2 or offset
		elseif mode == RENDER_MODE.SHOW_NUMBERS_ABSOLUTE then
			idx = file.idx
			offset = string.len(last_index)
		else -- RENDER_MODE.SHOW_NUMBERS_RELATIVE_ABSOLUTE
			if hovered == index then
				idx = file.idx
			else
				idx = math.abs(hovered - index)
			end
			offset = string.len(last_index)
		end

		if hovered == index then
			return ui.Span(string.format("%" .. tostring(offset + 1) .. "d ", idx)):style(styles and styles.hovered or {})
		else
			return ui.Span(string.format("%" .. tostring(offset + 1) .. "d ", idx)):style(styles and styles.normal or {})
		end
	end

	Parent.redraw = function(parent_self)
		if not parent_self._folder then
			return {}
		end

		local entities = {}
		local parent_tab_window_w = parent_self._area.w
		for _, f in ipairs(parent_self._folder.window) do
			local entity = Entity:new(f)
			if resizable_entity_children_ids then
				if smart_truncate_entity_plugin_ok then
					smart_truncate_entity_plugin:smart_truncate_entity(entity, parent_tab_window_w)
				else
					if not state.warned_smart_truncate_missing then
						state.warned_smart_truncate_missing = true
						warn(
							"smart-truncate plugin is not installed, please install it to use smart truncate feature \nor set smart_truncate = false in setup function"
						)
						return
					end
				end
			end
			-- Fall back to default render behaviour
			if state.warned_smart_truncate_missing or not resizable_entity_children_ids then
				entities[#entities + 1] =
					entity:redraw():truncate { max = parent_self._area.w, ellipsis = entity:ellipsis(self._area.w) }
			else
				-- Using smart truncate
				entities[#entities + 1] = ui.Line({ entity:redraw() }):style(entity:style())
			end
		end

		return {
			ui.List(entities):area(parent_self._area),
		}
	end

	Current.redraw = function(current_self)
		local files = current_self._folder.window
		if #files == 0 then
			return current_self:empty()
		end

		local last_entity_index = #current_self._folder.files
		local hovered_index
		local current_tab_window_w = current_self._area.w
		for i, f in ipairs(files) do
			if type(f.is_hovered) == "function" and f:is_hovered() or f.is_hovered then
				hovered_index = i
				break
			end
		end

		local entities, linemodes = {}, {}
		for i, f in ipairs(files) do
			local line_number_component = ui.Line(Entity:number(i, f, hovered_index, last_entity_index))
			local entity = Entity:new(f)
			local linemode_rendered = Linemode:new(f):redraw()
			local linemode_char_length = linemode_rendered:align(ui.Text.RIGHT):width()
			-- smart truncate
			if resizable_entity_children_ids then
				if smart_truncate_entity_plugin_ok then
					smart_truncate_entity_plugin:smart_truncate_entity(
						entity,
						current_tab_window_w - line_number_component:width() - linemode_char_length
					)
				else
					if not state.warned_smart_truncate_missing then
						state.warned_smart_truncate_missing = true
						warn(
							"smart-truncate plugin is not installed, please install it to use smart truncate feature \nor set smart_truncate = false in setup function"
						)
						return
					end
				end
			end

			entities[#entities + 1] = ui.Line({ line_number_component, entity:redraw() }):style(entity:style())
			linemodes[#linemodes + 1] = linemode_rendered

			-- fallback to default render behaviour
			if state.warned_smart_truncate_missing or not resizable_entity_children_ids then
				local max = math.max(0, current_self._area.w - linemodes[#linemodes]:width())
				entities[#entities]:truncate { max = max, ellipsis = entity:ellipsis(max) }
			end
		end

		return {
			ui.List(entities):area(current_self._area),
			ui.Text(linemodes):area(current_self._area):align(ui.Text.RIGHT),
		}
	end
end)

local function render_clear() render_motion() end

-----------------------------------------------
--------- C O M M A N D   P A R S E R ---------
-----------------------------------------------

local get_keys = ya.sync(function(state) return state._only_motions and MOTION_KEYS or MOTIONS_AND_OP_KEYS end)

local function normal_direction(dir)
	if dir == "<Down>" then
		return "j"
	elseif dir == "<Up>" then
		return "k"
	end
	return dir
end

local function get_cmd(first_char, keys)
	local last_key
	local lines = first_char or ""

	while true do
		render_motion(tonumber(lines))
		local key = ya.which { cands = keys, silent = true }
		if not key then
			return nil, nil, nil
		end

		last_key = keys[key].on
		if not tonumber(last_key) then
			last_key = normal_direction(last_key)
			break
		end

		lines = lines .. last_key
	end

	render_motion(tonumber(lines), last_key)

	-- command direction
	local direction
	if last_key == "g" or last_key == "v" or last_key == "d" or last_key == "y" or last_key == "x" then
		DIRECTION_KEYS[#DIRECTION_KEYS + 1] = {
			on = last_key,
		}
		local direction_key = ya.which { cands = DIRECTION_KEYS, silent = true }
		if not direction_key then
			return nil, nil, nil
		end

		direction = DIRECTION_KEYS[direction_key].on
		direction = normal_direction(direction)
	end

	return tonumber(lines), last_key, direction
end

local function is_tab_command(command)
	local tab_commands = { "t", "L", "H", "w", "W", "<", ">", "~" }
	for _, cmd in ipairs(tab_commands) do
		if command == cmd then
			return true
		end
	end
	return false
end

local get_active_tab = ya.sync(function(_) return cx.tabs.idx end)

-----------------------------------------------
---------- E N T R Y   /   S E T U P ----------
-----------------------------------------------

function M:setup(args)
	local state = self
	if not args then
		return
	end

	-- initialize state variables
	state._only_motions = args["only_motions"] or false

	if args["show_motion"] then
		render_motion_setup()
	end

	local custom_line_numbers_styles = args["line_numbers_styles"] or {}
	-- Default are filename/highlight (4) and symlink (6)
	-- Default = true equal { 4, 6 }
	-- 4 and 6 ids is get from this Entity._children
	-- https://github.com/sxyazi/yazi/blob/main/yazi-plugin/preset/components/entity.lua
	---@type boolean
	local smart_truncate = args["smart_truncate"]
	local resizable_entity_children_ids = { 4, 6 }
	if not smart_truncate then
		resizable_entity_children_ids = nil
	end

	if args["show_numbers"] == "absolute" then
		render_numbers(RENDER_MODE.SHOW_NUMBERS_ABSOLUTE, custom_line_numbers_styles, resizable_entity_children_ids)
	elseif args["show_numbers"] == "relative" then
		render_numbers(RENDER_MODE.SHOW_NUMBERS_RELATIVE, custom_line_numbers_styles, resizable_entity_children_ids)
	elseif args["show_numbers"] == "relative_absolute" then
		render_numbers(
			RENDER_MODE.SHOW_NUMBERS_RELATIVE_ABSOLUTE,
			custom_line_numbers_styles,
			resizable_entity_children_ids
		)
	end
end

function M:entry(job)
	local initial_value

	-- this is checking if the argument is a valid number
	if job.args then
		initial_value = tostring(tonumber(job.args[1]))
		if initial_value == "nil" then
			return
		end
	end

	local lines, cmd, direction = get_cmd(initial_value, get_keys())
	if not lines or not cmd then
		-- command was cancelled
		render_clear()
		return
	end

	if cmd == "g" then
		if direction == "g" then
			ya.manager_emit("arrow", { "top" })
			ya.manager_emit("arrow", { lines - 1 })
			render_clear()
			return
		elseif direction == "j" then
			cmd = "j"
		elseif direction == "k" then
			cmd = "k"
		elseif direction == "t" then
			ya.manager_emit("tab_switch", { lines - 1 })
			render_clear()
			return
		else
			-- no valid direction
			render_clear()
			return
		end
	end

	if cmd == "j" then
		ya.manager_emit("arrow", { lines })
	elseif cmd == "k" then
		ya.manager_emit("arrow", { -lines })
	elseif is_tab_command(cmd) then
		if cmd == "t" then
			for _ = 1, lines do
				ya.manager_emit("tab_create", {})
			end
		elseif cmd == "H" then
			ya.manager_emit("tab_switch", { -lines, relative = true })
		elseif cmd == "L" then
			ya.manager_emit("tab_switch", { lines, relative = true })
		elseif cmd == "w" then
			ya.manager_emit("tab_close", { lines - 1 })
		elseif cmd == "W" then
			local curr_tab = get_active_tab()
			local del_tab = curr_tab + lines - 1
			for _ = curr_tab, del_tab do
				ya.manager_emit("tab_close", { curr_tab - 1 })
			end
			ya.manager_emit("tab_switch", { curr_tab - 1 })
		elseif cmd == "<" then
			ya.manager_emit("tab_swap", { -lines })
		elseif cmd == ">" then
			ya.manager_emit("tab_swap", { lines })
		elseif cmd == "~" then
			local jump = lines - get_active_tab()
			ya.manager_emit("tab_swap", { jump })
		end
	else
		ya.manager_emit("visual_mode", {})
		-- invert direction when user specifies it
		if direction == "k" then
			ya.manager_emit("arrow", { -lines })
		elseif direction == "j" then
			ya.manager_emit("arrow", { lines })
		else
			ya.manager_emit("arrow", { lines - 1 })
		end
		ya.manager_emit("escape", {})

		if cmd == "d" then
			ya.manager_emit("remove", {})
		elseif cmd == "y" then
			ya.manager_emit("yank", {})
		elseif cmd == "x" then
			ya.manager_emit("yank", { cut = true })
		end
	end

	render_clear()
end
return M
