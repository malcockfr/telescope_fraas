local has_telescope, telescope = pcall(require, 'telescope')

if not has_telescope then
  error('This plugins requires nvim-telescope/telescope.nvim')
end

local action_state = require("telescope.actions.state")
local actions      = require("telescope.actions")
local finders      = require("telescope.finders")
local pickers      = require("telescope.pickers")
local sorters      = require("telescope.sorters")
local previewers   = require('telescope.previewers')
local utils        = require("telescope.utils")
local job          = require("plenary.job")

local M = {
  opts = {
    io_account = nil,
    sa_account = nil,
    terminal_cmd = nil,
    staging_context = nil,
  }
}

local test_state = {
  Running = "🚀",
  Finished = "🏁",
  Failed = "❌",
  Terminating = "☠️",
  Provisioning = "🚧",
}

local function set_config_state(opt_name, value, default)
  M.opts[opt_name] = value == nil and default or value
end

-- Override utils.get_os_command_output() with added 30s timeout
local function get_os_command_output(cmd, cwd)
  if type(cmd) ~= "table" then
    utils.notify("get_os_command_output", {
      msg = "cmd has to be a table",
      level = "ERROR",
    })
    return {}
  end
  local command = table.remove(cmd, 1)
  local stderr = {}
  local stdout, ret = job:new({
    command = command,
    args = cmd,
    cwd = cwd,
    on_stderr = function(_, data)
      table.insert(stderr, data)
    end,
  }):sync(30000)
  return stdout, ret, stderr
end

local get_fraas_projects = function()
  local cwd = vim.fn.getcwd()
  local results = get_os_command_output({ "gcloud", "projects", "list" }, cwd)

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

local get_fraas_tests = function()
  local cwd = vim.fn.getcwd()
  local results, _, stderr = get_os_command_output({ "kubectl", "get", "testruns", "--context", M.opts.staging_context,
    "--output=jsonpath={range .items[*]}{.status.runId}{\",\"}{.status.state}{\",\"}{.spec.prBranchName}{\",\"}{.spec.createdBy}{\",\"}{.status.slackThreadTs}{\",\"}{.metadata.name}{\"\\n\"}" }
    , cwd)
  local entries = {}
  for _, testrun in ipairs(results) do
    local id, state, branch, createdBy, slackThread, name = string.match(testrun,
      "(%w+),(%w+),([%w%p%Z]*),([%w%s%p]+),([%s%p%Z]*),([%w%p]+)")
    if id ~= nil then
      table.insert(entries, { id, state, branch, createdBy, slackThread, name })
    end
  end
  return entries
end

local open_gcp_console = function(account, id)
  vim.api.nvim_command(string.format("OpenBrowser https://console.cloud.google.com/getting-started?authuser=%s&project=%s"
    , account, id))
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
        -- actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        vim.fn.system(string.format(M.opts.terminal_cmd, selection.name, selection.name))
      end)
      actions.open_io_gcp_console = function()
        -- actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        open_gcp_console(M.opts.io_account, selection.id)
      end
      actions.open_sa_gcp_console = function()
        -- actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        open_gcp_console(M.opts.sa_account, selection.id)
      end
      actions.open_stackdriver = function()
        -- actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        vim.api.nvim_command(string.format("OpenBrowser https://console.cloud.google.com/logs/query?authuser=%s&project=%s"
          , M.opts.io_account, selection.id))
      end

      map('n', 'b', actions.open_io_gcp_console)
      map('n', 'B', actions.open_sa_gcp_console)
      map('n', 'l', actions.open_stackdriver)

      return true
    end,
  }):find()
end

M.fraas_tests = function(opts)
  pickers.new(opts, {
    prompt_title = string.format("FRaaS E2E tests"),
    finder = finders.new_table {
      results = get_fraas_tests(),
      entry_maker = function(entry)
        return {
          value = entry[1],
          display = string.format("%s\t-\t%s\t-\t%s", test_state[entry[2]], entry[1], entry[4]),
          ordinal = entry[4],
          slackThread = entry[5],
          name = entry[6],
          id = entry[1],
          branch = entry[3],
          state = entry[2]
        }
      end
    },
    sorter = sorters.get_generic_fuzzy_sorter(),
    previewer = previewers.new_buffer_previewer {
      title = "Test run details",
      define_preview = function(self, entry, status)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
          string.format("Name:\t\t\t%s", entry.name),
          string.format("ID:\t\t\t\t%s", entry.id),
          string.format("Branch:\t\t%s", entry.branch),
          string.format("State:\t\t%s", entry.state),
        })
      end
    },
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        -- actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        vim.api.nvim_command(string.format("OpenBrowser https://forgerock.slack.com/archives/C010WEFEMRV/p%s"
          , selection.slackThread:gsub('%.', '')))
      end)
      actions.terminate_testrun = function()
        -- actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        vim.fn.system(string.format("kubectl --context %s delete testrun %s", M.staging_context, selection.name))
      end
      return true
    end,
  }):find()
end

-- set_config_state("terminal_cmd", nil, "gnome-terminal --tab --title %s -- /usr/local/bin/forge shell %s")
-- set_config_state("io_account", nil, "")
-- set_config_state("staging_context", nil, "gke_terraforged-66994cf9-acf8_us-west1_staging")
-- M.fraas_tests()

return telescope.register_extension {
  setup = function(ext_config)
    set_config_state("terminal_cmd", ext_config.terminal_cmd,
      "gnome-terminal --tab --title %s -- /usr/local/bin/forge shell %s")
    set_config_state("io_account", ext_config.io_account, "")
    set_config_state("sa_account", string.gsub(ext_config.io_account, "@", "-sa@"))
    set_config_state("staging_context", ext_config.staging_context, "gke_terraforged-66994cf9-acf8_us-west1_staging")
  end,
  exports = {
    fraas = M.fraas_projects,
    projects = M.fraas_projects,
    tests = M.fraas_tests,
  },
}
