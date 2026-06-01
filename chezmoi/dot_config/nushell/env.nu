# Nushell Environment Config File
#
# version = "0.105.0"

def create_left_prompt [] {
    let dir = match (do --ignore-errors { $env.PWD | path relative-to $nu.home-dir }) {
        null => $env.PWD
        '' => '~'
        $relative_pwd => ([~ $relative_pwd] | path join)
    }

    let path_color = (if (is-admin) { ansi red_bold } else { ansi green_bold })
    let separator_color = (if (is-admin) { ansi light_red_bold } else { ansi light_green_bold })
    let path_segment = $"($path_color)($dir)"

    $path_segment | str replace --all (char path_sep) $"($separator_color)(char path_sep)($path_color)"
}

def create_right_prompt [] {
    # create a right prompt in magenta with green separators and am/pm underlined
    let time_segment = ([
        (ansi reset)
        (ansi magenta)
        (date now | format date '%x %X') # try to respect user's locale
    ] | str join | str replace --regex --all "([/:])" $"(ansi green)${1}(ansi magenta)" |
        str replace --regex --all "([AP]M)" $"(ansi magenta_underline)${1}")

    let last_exit_code = if ($env.LAST_EXIT_CODE != 0) {([
        (ansi rb)
        ($env.LAST_EXIT_CODE)
    ] | str join)
    } else { "" }

    ([$last_exit_code, (char space), $time_segment] | str join)
}

# Use nushell functions to define your right and left prompt
$env.PROMPT_COMMAND = {|| create_left_prompt }
# FIXME: This default is not implemented in rust code as of 2023-09-08.
$env.PROMPT_COMMAND_RIGHT = {|| create_right_prompt }

# The prompt indicators are environmental variables that represent
# the state of the prompt
$env.PROMPT_INDICATOR = {|| "> " }
$env.PROMPT_INDICATOR_VI_INSERT = {|| ": " }
$env.PROMPT_INDICATOR_VI_NORMAL = {|| "> " }
$env.PROMPT_MULTILINE_INDICATOR = {|| "::: " }

# If you want previously entered commands to have a different prompt from the usual one,
# you can uncomment one or more of the following lines.
# This can be useful if you have a 2-line prompt and it's taking up a lot of space
# because every command entered takes up 2 lines instead of 1. You can then uncomment
# the line below so that previously entered commands show with a single `🚀`.
# $env.TRANSIENT_PROMPT_COMMAND = {|| "🚀 " }
# $env.TRANSIENT_PROMPT_INDICATOR = {|| "" }
# $env.TRANSIENT_PROMPT_INDICATOR_VI_INSERT = {|| "" }
# $env.TRANSIENT_PROMPT_INDICATOR_VI_NORMAL = {|| "" }
# $env.TRANSIENT_PROMPT_MULTILINE_INDICATOR = {|| "" }
# $env.TRANSIENT_PROMPT_COMMAND_RIGHT = {|| "" }

# Specifies how environment variables are:
# - converted from a string to a value on Nushell startup (from_string)
# - converted from a value back to a string when running external commands (to_string)
# Note: The conversions happen *after* config.nu is loaded
$env.ENV_CONVERSIONS = {
    "PATH": {
        from_string: { |s| $s | split row (char esep) | path expand --no-symlink }
        to_string: { |v| $v | path expand --no-symlink | str join (char esep) }
    }
    "Path": {
        from_string: { |s| $s | split row (char esep) | path expand --no-symlink }
        to_string: { |v| $v | path expand --no-symlink | str join (char esep) }
    }
}

# Directories to search for scripts when calling source or use
# The default for this is $nu.default-config-dir/scripts
$env.NU_LIB_DIRS = [
    ($nu.default-config-dir | path join 'scripts') # add <nushell-config-dir>/scripts
    ($nu.data-dir | path join 'completions') # default home for nushell completions
]

# Directories to search for plugin binaries when calling register
# The default for this is $nu.default-config-dir/plugins
$env.NU_PLUGIN_DIRS = [
    ($nu.default-config-dir | path join 'plugins') # add <nushell-config-dir>/plugins
]

# To add entries to PATH (on Windows you might use Path), you can use the following pattern:
# $env.PATH = ($env.PATH | split row (char esep) | prepend '/some/path')
# An alternate way to add entries to $env.PATH is to use the custom command `path add`
# which is built into the nushell stdlib:
use std/util "path add"
# $env.PATH = ($env.PATH | split row (char esep))
# path add /some/path
# path add ($env.CARGO_HOME | path join "bin")
# path add ($env.HOME | path join ".local" "bin")
# $env.PATH = ($env.PATH | uniq)
# path add /opt/homebrew/bin  # brew2nix: nix-profile is now in PATH instead
path add /etc/profiles/per-user/yamer003/bin  # nix-darwin HM packages land here, not .nix-profile/bin
path add /Users/yamer003/.nix-profile/bin
path add /Users/yamer003/.bun/bin
path add /usr/bin
path add /run/current-system/sw/bin
path add /Users/yamer003/.atuin/bin
path add '/Applications/Visual Studio Code.app/Contents/Resources/app/bin'
path add '/Applications/Utilities/google-cloud-sdk/bin'
path add '/Users/yamer003/.local/bin'
# path add '/usr/local/bin'  # brew2nix: covered by nix-profile
# path add '/opt/homebrew/opt/libpq/bin'  # brew2nix: postgresql now via nix (psql in nix-profile/bin)
path add '/Users/yamer003/.krew/bin'
path add '/Library/Frameworks/Python.framework/Versions/3.11/bin'
path add '/Users/yamer003/.cargo/bin/dx'
path add '/usr/local/share/dotnet'
path add '/Users/yamer003/Documents/portable_apps'
path add '/Applications/Postgres.app/Contents/Versions/latest/bin'

# fnm (Fast Node Manager) initialization
if (which fnm | is-not-empty) {
    let fnm_env = (^fnm env --json | from json)
    $env.FNM_MULTISHELL_PATH = $fnm_env.FNM_MULTISHELL_PATH
    $env.FNM_DIR = $fnm_env.FNM_DIR
    $env.FNM_LOGLEVEL = $fnm_env.FNM_LOGLEVEL
    $env.FNM_NODE_DIST_MIRROR = $fnm_env.FNM_NODE_DIST_MIRROR
    $env.FNM_RESOLVE_ENGINES = $fnm_env.FNM_RESOLVE_ENGINES
    $env.FNM_VERSION_FILE_STRATEGY = $fnm_env.FNM_VERSION_FILE_STRATEGY
    $env.FNM_COREPACK_ENABLED = $fnm_env.FNM_COREPACK_ENABLED
    $env.FNM_ARCH = $fnm_env.FNM_ARCH
    path add ($fnm_env.FNM_MULTISHELL_PATH | path join "bin")
}

# To load from a custom file you can use:
# source ($nu.default-config-dir | path join 'custom.nu')

mkdir ~/.cache/starship
# Regenerate starship init only when binary changes
let starship_cache = ($"($nu.home-dir)/.cache/starship/init.nu")
if (which starship | is-not-empty) {
  let starship_bin = (which starship | get 0.path)
  if not ($starship_cache | path exists) or (ls $starship_bin | get 0.modified) > (ls $starship_cache | get 0.modified) {
    starship init nu | save -f $starship_cache
  }
}

# Regenerate zoxide init only when binary changes
let zoxide_cache = ($"($nu.home-dir)/.zoxide.nu")
if (which zoxide | is-not-empty) {
  let zoxide_bin = (which zoxide | get 0.path)
  if not ($zoxide_cache | path exists) or (ls $zoxide_bin | get 0.modified) > (ls $zoxide_cache | get 0.modified) {
    zoxide init nushell | save -f $zoxide_cache
  }
}

$env.STARSHIP_CONFIG = '/Users/yamer003/.config/starship/starship.toml'
# $env.NIX_CONF_DIR = /Users/yamer003/.config/nix
$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
mkdir ~/.cache/carapace
# Regenerate carapace init only when binary changes (compat patch removed — fixed in v1.4+)
let carapace_cache = ($"($nu.home-dir)/.cache/carapace/init.nu")
if (which carapace | is-not-empty) {
  let carapace_bin = (which carapace | get 0.path)
  if not ($carapace_cache | path exists) or (ls $carapace_bin | get 0.modified) > (ls $carapace_cache | get 0.modified) {
    carapace _carapace nushell | save --force $carapace_cache
  }
}

$env.GITHUB_TOKEN = (security find-generic-password -a "yamer003" -s "github-token-nushell" -w | str trim)
$env.VAULT_AGENT_ADDR = (security find-generic-password -a "yamer003" -s "work-vault-url" -w | str trim)
$env.VAULT_ADDR = (security find-generic-password -a "yamer003" -s "work-vault-url" -w | str trim)
$env.VAULT_NAMESPACE = (security find-generic-password -a "yamer003" -s "work-vault-namespace" -w | str trim)
# $env.REQUESTS_CA_BUNDLE = (security find-generic-password -a "yamer003" -s "work-ca-root-cert-path" -w | str trim)
# $env.GSETTINGS_SCHEMA_DIR = '/opt/homebrew/share/glib-2.0/schemas/'  # brew2nix: gsettings now via nix
# $env.VAULT_AGENT_ADDR = 'https://localhost:8200'
# $env.VAULT_ADDR = 'https://localhost:8200'
# $env.VAULT_SKIP_VERIFY = true

$env.GOOGLE_GENAI_USE_VERTEXAI = 'true'
$env.GOOGLE_CLOUD_PROJECT = 'pg-ae-n-app-237049'
$env.GOOGLE_CLOUD_LOCATION = 'global'

$env.VERACODE_API_KEY_ID = (security find-generic-password -a "yamer003" -s "veracode-api-key-id" -w | str trim)
$env.VERACODE_API_KEY_SECRET = (security find-generic-password -a "yamer003" -s "veracode-api-key-secret" -w | str trim)

$env.CLAUDE_CODE_OAUTH_TOKEN = (security find-generic-password -a "yamer003" -s "claude-code-oauth-token" -w | str trim)

$env.CLOUDFLARE_ACCOUNT_ID = (security find-generic-password -a "yamer003" -s "cloudflare-account-id" -w | str trim)
$env.CLOUDFLARE_GATEWAY_ID = 'opencode'
$env.CLOUDFLARE_API_TOKEN = (security find-generic-password -a "yamer003" -s "cloudflare-api-token" -w | str trim)
$env.OPENCODE_SERVER_PASSWORD = (security find-generic-password -a "yamer003" -s "opencode-server-password" -w | str trim)

$env.OPENAI_API_KEY = (security find-generic-password -a "yamer003" -s "litellm-api-key" -w | str trim)


# Set the certificate path dynamically — cache DNS result for 5 min to avoid 60ms nslookup on every launch
let corp_cache = "/tmp/.nu_corp_network_cache"
let corp_dns = (security find-generic-password -a "yamer003" -s "work-dns-check-domain" -w | str trim)
let on_corp = if ($corp_cache | path exists) and ((date now) - (ls $corp_cache | get 0.modified) < 5min) {
  (open $corp_cache) == "on"
} else {
  let result = not ((^nslookup $corp_dns | complete).stdout | str contains "No answer")
  (if $result { "on" } else { "off" }) | save -f $corp_cache
  $result
}
if $on_corp {
  $env.REQUESTS_CA_BUNDLE = (security find-generic-password -a "yamer003" -s "work-ca-root-cert-path" -w | str trim)
}
