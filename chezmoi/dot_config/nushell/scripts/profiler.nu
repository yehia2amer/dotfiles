# Nushell Profiling Toolkit
#
# Commands for measuring startup time, profiling config hotspots,
# toggling live REPL timing, and reviewing timing history.
#
# Usage:
#   profile-startup                    # compare interactive vs minimal startup
#   profile-config --top 10            # top 10 config.nu hotspots
#   profile-repl on                    # enable live per-command timing
#   profile-repl off                   # disable live per-command timing
#   profile-log                        # show REPL timing history
#   profile-log clear                  # reset REPL timing history
#   debug profile --duration-values --lines { source ./file.nu } | top-hotspots --top 5

# Profile config.nu internals — runs in a subprocess to avoid circular import
# (since config.nu `use`s this module). Sources env.nu first for a realistic env.
export def profile-config [
    --top (-n): int = 30   # number of hotspots to return
] {
    let env_path = $nu.env-path
    let config_path = $nu.config-path
    (^nu --no-config-file -c $"
        source '($env_path)'
        debug profile --duration-values --lines --expand-source { source '($config_path)' }
        | sort-by duration | reverse | first ($top) | to nuon
    " | from nuon)
}

# Compare interactive startup time vs bare-minimum baseline.
export def profile-startup [] {
    let config_path = $nu.config-path
    let env_path = $nu.env-path

    print "Measuring full startup (loads env + config)..."
    let full = (^nu --config $config_path --env-config $env_path -c '$nu.startup-time' | str trim)

    print "Measuring minimal startup (no config, no std-lib)..."
    let minimal = (^nu --no-std-lib -n -c '$nu.startup-time' | str trim)

    print ""
    print $"Full \(config) : ($full)"
    print $"Minimal       : ($minimal)"
    print $"Config cost   ≈ full − minimal"
    print ""
    print "Drill into config cost with:  profile-config --top 20"
}

# Pipe filter — sort any `debug profile` table by duration and take top N.
#
# Example:
#   debug profile --duration-values --lines { source ./myscript.nu } | top-hotspots --top 10
export def top-hotspots [
    --top (-n): int = 20   # number of rows to return
] {
    sort-by duration | reverse | first $top
}

# Show REPL timing history collected while `profile-repl on` is active.
export def "profile-log" [
    --top (-n): int = 20   # number of entries to show (by duration desc)
] {
    if ($env.__nu_profile_log? | default [] | is-empty) {
        print "No REPL timing entries yet. Run `profile-repl on` then execute some commands."
        return
    }
    $env.__nu_profile_log | sort-by duration | reverse | first $top
}

# Clear REPL timing history.
export def "profile-log clear" [] {
    $env.__nu_profile_log = []
    print "REPL timing log cleared."
}

# Toggle live per-command timing in the REPL.
#
#   profile-repl on    — start printing [duration] after every command
#   profile-repl off   — stop printing
#   profile-repl       — show current state
export def --env "profile-repl" [
    action?: string   # "on" or "off" (omit to show current state)
] {
    match $action {
        "on" => {
            $env.__nu_profile_enabled = true
            print "REPL profiling ON — timing will appear after each command."
        }
        "off" => {
            $env.__nu_profile_enabled = false
            print "REPL profiling OFF."
        }
        null => {
            let state = if ($env.__nu_profile_enabled? | default false) { "ON" } else { "OFF" }
            print $"REPL profiling is ($state)."
        }
        _ => {
            print "Usage: profile-repl [on|off]"
        }
    }
}
