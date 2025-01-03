---@toc workspace.nvim

---@divider
---@mod workspace.introduction Introduction
---@brief [[
--- workspace.nvim is a plugin that allows you to manage tmux session
--- for your projects and workspaces in a simple and efficient way.
---@brief ]]
local M = {}
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local sorters = require("telescope.sorters")
local actions = require("telescope.actions")
local action_set = require("telescope.actions.set")
local action_state = require("telescope.actions.state")
local tmux = require("workspace-manager.tmux")

local function validate_workspace(workspace)
	if not workspace.name or not workspace.path or not workspace.keymap then
		return false
	end
	return true
end

local function validate_options(options)
	if not options or not options.workspaces or #options.workspaces == 0 then
		return false
	end

	for _, workspace in ipairs(options.workspaces) do
		if not validate_workspace(workspace) then
			return false
		end
	end

	return true
end

local default_options = {
	workspaces = {
		--{ name = "Projects", path = "~/Projects", keymap = { "<leader>o" } },
	},
	tmux_session_name_generator = function(project_name, workspace_name)
		local session_name = string.upper(project_name)
		return session_name
	end,
}

local function open_workspace_popup(workspace, options)
	if not tmux.is_running() then
		vim.api.nvim_err_writeln("Tmux is not running or not in a tmux session")
		return
	end

	if not workspace.path or workspace.path == "" then
		vim.api.nvim_err_writeln("Invalid workspace path")
		return
	end

	local workspace_path = vim.fn.expand(workspace.path) -- Expand the ~ symbol
	local all_git_folders = vim.fn.globpath(workspace_path, "**/.git", 1, 1) -- Find all .git folders
	local git_projects = {}

	for _, git_path in ipairs(all_git_folders) do
		local parent_dir = vim.fn.fnamemodify(git_path, ":h") -- Parent directory of .git
		git_projects[parent_dir] = true -- Use table to remove duplicates
	end

	local unique_folders = vim.tbl_keys(git_projects) -- Convert to list
	local entries = {}

	if #unique_folders == 0 then
		table.insert(entries, {
			value = "noProjects",
			display = "No Git projects found",
			ordinal = "No Git projects found",
		})
	else
		table.insert(entries, {
			value = "newProject",
			display = "Create new project",
			ordinal = "Create new project",
		})
		for _, folder in ipairs(unique_folders) do
			table.insert(entries, {
				value = folder,
				display = folder:gsub(workspace_path .. "/", ""),
				ordinal = folder,
			})
		end
	end

	pickers
		.new({
			results_title = workspace.name,
			prompt_title = "Search in " .. workspace.name .. " workspace",
		}, {
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					return {
						value = entry.value,
						display = entry.display,
						ordinal = entry.ordinal,
					}
				end,
			}),
			sorter = sorters.get_fuzzy_file(),
			attach_mappings = function()
				action_set.select:replace(function(prompt_bufnr)
					local selection = action_state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)
					if selection.value == "noProjects" then
						vim.api.nvim_err_writeln("No Git projects to manage")
					elseif selection.value == "newProject" then
						-- Handle new project creation
					else
						tmux.manage_session(selection.value, workspace, options)
					end
				end)
				return true
			end,
		})
		:find()
end

---@divider
---@mod workspace.tmux_sessions Tmux Sessions Selector
---@brief [[
--- workspace.tmux_sessions allows to list and select tmux sessions
---@brief ]]
function M.tmux_sessions()
	if not tmux.is_running() then
		vim.api.nvim_err_writeln("Tmux is not running or not in a tmux session")
		return
	end

	local sessions = vim.fn.systemlist('tmux list-sessions -F "#{session_name}"')

	local entries = {}
	for _, session in ipairs(sessions) do
		table.insert(entries, {
			value = session,
			display = session,
			ordinal = session,
		})
	end

	pickers
		.new({
			results_title = "Tmux Sessions",
			prompt_title = "Select a Tmux session",
		}, {
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					return {
						value = entry.value,
						display = entry.display,
						ordinal = entry.ordinal,
					}
				end,
			}),
			sorter = sorters.get_fuzzy_file(),
			attach_mappings = function()
				action_set.select:replace(function(prompt_bufnr)
					local selection = action_state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)
					tmux.attach(selection.value)
				end)
				return true
			end,
		})
		:find()
end

---@mod workspace-manager.setup setup
---@param options table Setup options
--- * {workspaces} (table) List of workspaces
---  ```
---  {
---    { name = "Workspace1", path = "~/path/to/workspace1", keymap = { "<leader>w" } },
---    { name = "Workspace2", path = "~/path/to/workspace2", keymap = { "<leader>x" } },
---  }
---  ```
---  * `name` string: Name of the workspace
---  * `path` string: Path to the workspace
---  * `keymap` table: List of keybindings to open the workspace
---
--- * {tmux_session_name_generator} (function) Function that generates the tmux session name
---  ```lua
---  function(project_name, workspace_name)
---    local session_name = string.upper(project_name)
---    return session_name
---  end
---  ```
---  * `project_name` string: Name of the project
---  * `workspace_name` string: Name of the workspace
---
function M.setup(user_options)
	local options = vim.tbl_deep_extend("force", default_options, user_options or {})

	if not validate_options(options) then
		-- Display an error message and example options
		vim.api.nvim_err_writeln("Invalid setup options. Provide options like this:")
		vim.api.nvim_err_writeln([[{
      workspaces = {
        { name = "Workspace1", path = "~/path/to/workspace1", keymap = { "<leader>w" } },
        { name = "Workspace2", path = "~/path/to/workspace2", keymap = { "<leader>x" } },
      }
    }]])
		return
	end

	for _, workspace in ipairs(options.workspaces or {}) do
		vim.keymap.set("n", workspace.keymap[1], function()
			open_workspace_popup(workspace, options)
		end, { noremap = true, desc = workspace.keymap.desc or ("Open workspace " .. workspace.name) })
	end
end

return M
