local has_telescope, telescope = pcall(require, 'telescope')

if not has_telescope then
  error('This plugins requires nvim-telescope/telescope.nvim')
end

local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local utils = require("telescope.utils")
local sorters = require("telescope.sorters")

local M = {
  opts = {
    io_account = nil,
    terminal_cmd = nil,
  }
}

local function set_config_state(opt_name, value, default)
  M.opts[opt_name] = value == nil and default or value
end

local get_fraas_projects = function()
  local cwd = vim.fn.getcwd()
  local results = utils.get_os_command_output({ "gcloud", "projects", "list" }, cwd)

  local entries = {}
  for _, project in ipairs(results) do
    local id, name, number = string.match(project,
      "([%w%p]+)%s*([%w%p]+)%s*(%d+)")
    if id ~= "PROJECT_ID" then
      table.insert(entries, { project, id, name, number })
    end
  end
  return entries
end

M.fraas_projects = function(opts)
  pickers.new(opts, {
    prompt_title = string.format("FRaaS Projects"),
    finder = finders.new_table {
      results = get_fraas_projects(),
      entry_maker = function(entry)
        return {
          value = entry[3],
          display = entry[1],
          ordinal = entry[3],
          id = entry[2],
          name = entry[3],
          number = entry[4],
        }
      end
    },
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        vim.fn.system(string.format(M.opts.terminal_cmd, selection.name, selection.name))
      end)
      actions.open_gcp_console = function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        vim.api.nvim_command(string.format("OpenBrowser https://console.cloud.google.com/getting-started?authuser=%s&project=%s"
          , M.opts.io_account, selection.id))
      end
      actions.open_stackdriver = function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        vim.api.nvim_command(string.format("OpenBrowser https://console.cloud.google.com/logs/query?authuser=%s&project=%s"
          , M.opts.io_account, selection.id))
      end

      map('n', 'b', actions.open_gcp_console)
      map('n', 'l', actions.open_gcp_console)

      return true
    end,
  }):find()
end
-- set_config_state("terminal_cmd", nil, "gnome-terminal --tab --title %s -- /usr/local/bin/forge shell %s")
-- set_config_state("io_account", nil, "")
-- M.fraas_projects()

return telescope.register_extension {
  setup = function(ext_config)
    set_config_state("terminal_cmd", ext_config.terminal_cmd,
      "gnome-terminal --tab --title %s -- /usr/local/bin/forge shell %s")
    set_config_state("io_account", ext_config.io_account, "")
  end,
  exports = {
    fraas = M.fraas_projects,
    projects = M.fraas_projects,
  },
}
