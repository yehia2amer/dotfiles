local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ============================================================
-- Font Configuration (Ghostty defaults: JetBrains Mono, 13pt)
-- ============================================================
config.font = wezterm.font('JetBrains Mono', { weight = 'Medium' })
config.font_size = 13.0
config.line_height = 1.0
config.freetype_load_flags = 'NO_HINTING'

-- ============================================================
-- Color Scheme (Ghostty One Dark defaults)
-- ============================================================
config.colors = {
  foreground = '#ABB2BF',
  background = '#282C34',
  cursor_bg = '#528BFF',
  cursor_fg = '#282C34',
  cursor_border = '#528BFF',
  selection_fg = '#ABB2BF',
  selection_bg = '#3E4451',
  scrollbar_thumb = '#4B5263',

  ansi = {
    '#282C34', -- black
    '#E06C75', -- red
    '#98C379', -- green
    '#E5C07B', -- yellow
    '#61AFEF', -- blue
    '#C678DD', -- magenta
    '#56B6C2', -- cyan
    '#ABB2BF', -- white
  },
  brights = {
    '#5C6370', -- bright black
    '#E06C75', -- bright red
    '#98C379', -- bright green
    '#E5C07B', -- bright yellow
    '#61AFEF', -- bright blue
    '#C678DD', -- bright magenta
    '#56B6C2', -- bright cyan
    '#FFFFFF', -- bright white
  },

  -- Tab bar colors (styled to blend with One Dark theme)
  tab_bar = {
    background = '#21252B',
    active_tab = {
      bg_color = '#282C34',
      fg_color = '#ABB2BF',
      intensity = 'Bold',
      underline = 'None',
      italic = false,
      strikethrough = false,
    },
    inactive_tab = {
      bg_color = '#21252B',
      fg_color = '#5C6370',
    },
    inactive_tab_hover = {
      bg_color = '#2C313A',
      fg_color = '#ABB2BF',
      italic = false,
    },
    new_tab = {
      bg_color = '#21252B',
      fg_color = '#5C6370',
    },
    new_tab_hover = {
      bg_color = '#2C313A',
      fg_color = '#ABB2BF',
      italic = false,
    },
  },
}

-- ============================================================
-- Window Appearance (minimal chrome, Ghostty-like)
-- ============================================================
config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE'
config.window_background_opacity = 1.0
config.macos_window_background_blur = 0
config.window_padding = {
  left = 2,
  right = 18,
  top = 2,
  bottom = 2,
}

-- ============================================================
-- Tab Bar (hidden for single tab, retro style at bottom)
-- ============================================================
-- WezTerm does not support vertical tab bars natively.
-- Using retro tab bar at bottom, hidden when only one tab.
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.tab_max_width = 25
config.window_frame = {
  font = wezterm.font('JetBrains Mono', { weight = 'Medium' }),
  font_size = 15.0,
  active_titlebar_bg = '#21252B',
  inactive_titlebar_bg = '#21252B',
}

-- ============================================================
-- Scrollbar
-- ============================================================
config.enable_scroll_bar = true
config.scrollback_lines = 10000

-- ============================================================
-- Cursor (Ghostty defaults: block, blinking)
-- ============================================================
config.default_cursor_style = 'BlinkingBlock'
config.cursor_blink_rate = 500
config.cursor_blink_ease_in = 'Constant'
config.cursor_blink_ease_out = 'Constant'

-- ============================================================
-- Shell Launcher (Windows Terminal-style dropdown)
-- ============================================================
-- Default shell: zsh
config.default_prog = { '/bin/zsh', '-l' }

-- Launch menu entries (right-click "+" tab button or use keybinding)
config.launch_menu = {
  {
    label = '🐚 Zsh (default)',
    args = { '/bin/zsh', '-l' },
  },
  {
    label = '🐚 Bash',
    args = { '/bin/bash', '-l' },
  },
  {
    label = '🐟 Fish',
    args = { '/Users/yamer003/.nix-profile/bin/fish', '-l' },
  },
  {
    label = '🚀 Nushell',
    args = { '/Users/yamer003/.nix-profile/bin/nu', '-l' },
  },
}

-- ============================================================
-- Dynamic SSH Hosts (parsed from ~/.ssh/config + manual entries)
-- ============================================================

-- Manual quick-access SSH hosts (add entries here for hosts NOT in ssh_config)
-- Format: { label = 'display name', host = 'user@hostname', port = 22 }
local manual_ssh_hosts = {
  -- { label = 'Dev Server', host = 'deploy@dev.example.com' },
  -- { label = 'Production', host = 'admin@prod.example.com', port = 2222 },
}

-- Parse ~/.ssh/config for Host entries (skips wildcards and coder-vscode proxies)
local function parse_ssh_config()
  local hosts = {}
  local home = os.getenv('HOME') or '/Users/yamer003'
  local f = io.open(home .. '/.ssh/config', 'r')
  if not f then return hosts end

  local current_host = nil
  local current_user = nil
  local current_hostname = nil
  local current_port = nil

  local function flush()
    if current_host and not current_host:match('[*?]') and not current_host:match('^coder%-') then
      table.insert(hosts, {
        label = current_host,
        hostname = current_hostname or current_host,
        user = current_user,
        port = current_port,
      })
    end
    current_host = nil
    current_user = nil
    current_hostname = nil
    current_port = nil
  end

  for line in f:lines() do
    local host_match = line:match('^%s*Host%s+(.+)$')
    if host_match then
      flush()
      current_host = host_match:match('^(%S+)')
    else
      local key, value = line:match('^%s+(%w+)%s+(.+)$')
      if key and current_host then
        key = key:lower()
        if key == 'hostname' then current_hostname = value
        elseif key == 'user' then current_user = value
        elseif key == 'port' then current_port = tonumber(value)
        end
      end
    end
  end
  flush()
  f:close()
  return hosts
end

-- Add parsed SSH hosts to launch menu
local ssh_hosts = parse_ssh_config()
for _, host in ipairs(ssh_hosts) do
  local ssh_args = { 'ssh' }
  if host.port and host.port ~= 22 then
    table.insert(ssh_args, '-p')
    table.insert(ssh_args, tostring(host.port))
  end
  local target = host.hostname or host.label
  if host.user then
    target = host.user .. '@' .. target
  end
  table.insert(ssh_args, target)

  table.insert(config.launch_menu, {
    label = '🔗 SSH: ' .. host.label .. ' (' .. target .. ')',
    args = ssh_args,
  })
end

-- Add manual SSH hosts to launch menu
for _, host in ipairs(manual_ssh_hosts) do
  local ssh_args = { 'ssh' }
  if host.port and host.port ~= 22 then
    table.insert(ssh_args, '-p')
    table.insert(ssh_args, tostring(host.port))
  end
  table.insert(ssh_args, host.host)

  table.insert(config.launch_menu, {
    label = '🔗 SSH: ' .. host.label,
    args = ssh_args,
  })
end

-- ============================================================
-- Keybindings
-- ============================================================
config.keys = {
  -- CTRL+SHIFT+L opens the launcher menu (shells + SSH hosts)
  {
    key = 'l',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.ShowLauncherArgs {
      flags = 'FUZZY|LAUNCH_MENU_ITEMS',
    },
  },
  -- CTRL+SHIFT+S opens an input box to SSH to any host on-the-fly
  {
    key = 's',
    mods = 'CTRL|SHIFT',
    action = wezterm.action.PromptInputLine {
      description = 'SSH to host (e.g. user@host or host -p 2222):',
      action = wezterm.action_callback(function(window, pane, line)
        if line and line ~= '' then
          -- Split input into args (supports: user@host, host -p 2222, etc.)
          local args = { 'ssh' }
          for token in line:gmatch('%S+') do
            table.insert(args, token)
          end
          window:perform_action(
            wezterm.action.SpawnCommandInNewTab {
              args = args,
            },
            pane
          )
        end
      end),
    },
  },
}

-- ============================================================
-- Misc
-- ============================================================
config.audible_bell = 'Disabled'
config.check_for_updates = false
config.automatically_reload_config = true

return config
