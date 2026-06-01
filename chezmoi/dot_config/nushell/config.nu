# Nushell Config File
#
# version = "0.105.0"

source $"($nu.home-dir)/.cargo/env.nu"

# For more information on defining custom themes, see
# https://www.nushell.sh/book/coloring_and_theming.html
# And here is the theme collection
# https://github.com/nushell/nu_scripts/tree/main/themes
let dark_theme = {
    # color for nushell primitives
    separator: white
    leading_trailing_space_bg: { attr: n } # no fg, no bg, attr none effectively turns this off
    header: green_bold
    empty: blue
    # Closures can be used to choose colors for specific values.
    # The value (in this case, a bool) is piped into the closure.
    # eg) {|| if $in { 'light_cyan' } else { 'light_gray' } }
    bool: light_cyan
    int: white
    filesize: cyan
    duration: white
    date: purple
    range: white
    float: white
    string: white
    nothing: white
    binary: white
    cell-path: white
    row_index: green_bold
    record: white
    list: white
    block: white
    hints: dark_gray
    search_result: { bg: red fg: white }
    shape_and: purple_bold
    shape_binary: purple_bold
    shape_block: blue_bold
    shape_bool: light_cyan
    shape_closure: green_bold
    shape_custom: green
    shape_datetime: cyan_bold
    shape_directory: cyan
    shape_external: cyan
    shape_externalarg: green_bold
    shape_external_resolved: light_yellow_bold
    shape_filepath: cyan
    shape_flag: blue_bold
    shape_float: purple_bold
    # shapes are used to change the cli syntax highlighting
    shape_garbage: { fg: white bg: red attr: b}
    shape_glob_interpolation: cyan_bold
    shape_globpattern: cyan_bold
    shape_int: purple_bold
    shape_internalcall: cyan_bold
    shape_keyword: cyan_bold
    shape_list: cyan_bold
    shape_literal: blue
    shape_match_pattern: green
    shape_matching_brackets: { attr: u }
    shape_nothing: light_cyan
    shape_operator: yellow
    shape_or: purple_bold
    shape_pipe: purple_bold
    shape_range: yellow_bold
    shape_record: cyan_bold
    shape_redirection: purple_bold
    shape_signature: green_bold
    shape_string: green
    shape_string_interpolation: cyan_bold
    shape_table: blue_bold
    shape_variable: purple
    shape_vardecl: purple
    shape_raw_string: light_purple
}

let light_theme = {
    # color for nushell primitives
    separator: dark_gray
    leading_trailing_space_bg: { attr: n } # no fg, no bg, attr none effectively turns this off
    header: green_bold
    empty: blue
    # Closures can be used to choose colors for specific values.
    # The value (in this case, a bool) is piped into the closure.
    # eg) {|| if $in { 'dark_cyan' } else { 'dark_gray' } }
    bool: dark_cyan
    int: dark_gray
    filesize: cyan_bold
    duration: dark_gray
    date: purple
    range: dark_gray
    float: dark_gray
    string: dark_gray
    nothing: dark_gray
    binary: dark_gray
    cell-path: dark_gray
    row_index: green_bold
    record: dark_gray
    list: dark_gray
    block: dark_gray
    hints: dark_gray
    search_result: { fg: white bg: red }
    shape_and: purple_bold
    shape_binary: purple_bold
    shape_block: blue_bold
    shape_bool: light_cyan
    shape_closure: green_bold
    shape_custom: green
    shape_datetime: cyan_bold
    shape_directory: cyan
    shape_external: cyan
    shape_externalarg: green_bold
    shape_external_resolved: light_purple_bold
    shape_filepath: cyan
    shape_flag: blue_bold
    shape_float: purple_bold
    # shapes are used to change the cli syntax highlighting
    shape_garbage: { fg: white bg: red attr: b}
    shape_globpattern: cyan_bold
    shape_int: purple_bold
    shape_internalcall: cyan_bold
    shape_keyword: cyan_bold
    shape_list: cyan_bold
    shape_literal: blue
    shape_match_pattern: green
    shape_matching_brackets: { attr: u }
    shape_nothing: light_cyan
    shape_operator: yellow
    shape_or: purple_bold
    shape_pipe: purple_bold
    shape_range: yellow_bold
    shape_record: cyan_bold
    shape_redirection: purple_bold
    shape_signature: green_bold
    shape_string: green
    shape_string_interpolation: cyan_bold
    shape_table: blue_bold
    shape_variable: purple
    shape_vardecl: purple
    shape_raw_string: light_purple
}

# If Atuin is available, minimize Nushell's built-in history (Atuin handles it).
# Otherwise, fall back to SQLite history with full features.
let history_config = if (which atuin | is-not-empty) {
    {
        max_size: 1              # Minimal — Atuin is the source of truth
        sync_on_enter: false     # No need to write on every Enter
        file_format: "plaintext" # Lightweight; barely used
        isolation: false
    }
} else {
    {
        max_size: 100_000
        sync_on_enter: true
        file_format: "sqlite"
        isolation: true
    }
}

# ── Profiling state (used by REPL timing hooks at the bottom of this file) ──
$env.__nu_profile_log = []
$env.__nu_profile_start = null
$env.__nu_profile_cmd = null
$env.__nu_profile_enabled = false

$env.config = {
    show_banner: false

    ls: {
        use_ls_colors: true # use the LS_COLORS environment variable to colorize output
        clickable_links: true # enable or disable clickable links. Your terminal has to support links.
    }

    rm: {
        always_trash: false # always act as if -t was given. Can be overridden with -p
    }

    table: {
        mode: rounded # basic, compact, compact_double, light, thin, with_love, rounded, reinforced, heavy, none, other
        index_mode: always # "always" show indexes, "never" show indexes, "auto" = show indexes when a table has "index" column
        show_empty: true # show 'empty list' and 'empty record' placeholders for command output
        padding: { left: 1, right: 1 } # a left right padding of each column in a table
        trim: {
            methodology: wrapping # wrapping or truncating
            wrapping_try_keep_words: true # A strategy used by the 'wrapping' methodology
            truncating_suffix: "..." # A suffix used by the 'truncating' methodology
        }
        header_on_separator: false # show header text on separator/border line
        # abbreviated_row_count: 10 # limit data rows from top and bottom after reaching a set point
    }

    error_style: "fancy" # "fancy" or "plain" for screen reader-friendly error messages

    # datetime_format determines what a datetime rendered in the shell would look like.
    # Behavior without this configuration point will be to "humanize" the datetime display,
    # showing something like "a day ago."
    datetime_format: {
        # normal: '%a, %d %b %Y %H:%M:%S %z'    # shows up in displays of variables or other datetime's outside of tables
        # table: '%m/%d/%y %I:%M:%S%p'          # generally shows up in tabular outputs such as ls. commenting this out will change it to the default human readable datetime format
    }

    explore: {
        status_bar_background: { fg: "#1D1F21", bg: "#C4C9C6" },
        command_bar_text: { fg: "#C4C9C6" },
        highlight: { fg: "black", bg: "yellow" },
        status: {
            error: { fg: "white", bg: "red" },
            warn: {}
            info: {}
        },
        selected_cell: { bg: light_blue },
    }

    history: $history_config

    completions: {
        case_sensitive: false # set to true to enable case-sensitive completions
        quick: true    # set this to false to prevent auto-selecting completions when only one remains
        partial: true    # set this to false to prevent partial filling of the prompt
        algorithm: "fuzzy"    # prefix or fuzzy
        external: {
            enable: true # set to false to prevent nushell looking into $env.PATH to find more suggestions, `false` recommended for WSL users as this look up may be very slow
            max_results: 100 # setting it lower can improve completion performance at the cost of omitting some options
            completer: null # check 'carapace_completer' above as an example
        }
        use_ls_colors: true # set this to true to enable file/path/directory completions using LS_COLORS
    }

    filesize: {
        # metric: false # true => KB, MB, GB (ISO standard), false => KiB, MiB, GiB (Windows standard)
        unit: "metric" # metric (KB, MB, GB), binary (KiB, MiB, GiB), or specific: B, kB, MB, GB, TB, PB, EB, KiB, MiB, GiB, TiB, PiB, EiB
    }

    cursor_shape: {
        emacs: block # block, underscore, line, blink_block, blink_underscore, blink_line, inherit to skip setting cursor shape (line is the default)
        vi_insert: block # block, underscore, line, blink_block, blink_underscore, blink_line, inherit to skip setting cursor shape (block is the default)
        vi_normal: underscore # block, underscore, line, blink_block, blink_underscore, blink_line, inherit to skip setting cursor shape (underscore is the default)
    }

    color_config: $dark_theme # if you want a more interesting theme, you can replace the empty record with `$dark_theme`, `$light_theme` or another custom record
    # use_grid_icons: true
    # footer_mode: "25" # always, never, number_of_rows, auto
    float_precision: 2 # the precision for displaying floats in tables
    buffer_editor: "" # command that will be used to edit the current line buffer with ctrl+o, if unset fallback to $env.EDITOR and $env.VISUAL
    use_ansi_coloring: true
    bracketed_paste: true # enable bracketed paste, currently useless on windows
    edit_mode: vi # emacs, vi
    shell_integration: {
        # osc2 abbreviates the path if in the home_dir, sets the tab/window title, shows the running command in the tab/window title
        osc2: true
        # osc7 is a way to communicate the path to the terminal, this is helpful for spawning new tabs in the same directory
        osc7: true
        # osc8 is also implemented as the deprecated setting ls.show_clickable_links, it shows clickable links in ls output if your terminal supports it. show_clickable_links is deprecated in favor of osc8
        osc8: true
        # osc9_9 is from ConEmu and is starting to get wider support. It's similar to osc7 in that it communicates the path to the terminal
        osc9_9: false
        # osc133 is several escapes invented by Final Term which include the supported ones below.
        # 133;A - Mark prompt start
        # 133;B - Mark prompt end
        # 133;C - Mark pre-execution
        # 133;D;exit - Mark execution finished with exit code
        # This is used to enable terminals to know where the prompt is, the command is, where the command finishes, and where the output of the command is
        osc133: true
        # osc633 is closely related to osc133 but only exists in visual studio code (vscode) and supports their shell integration features
        # 633;A - Mark prompt start
        # 633;B - Mark prompt end
        # 633;C - Mark pre-execution
        # 633;D;exit - Mark execution finished with exit code
        # 633;E - NOT IMPLEMENTED - Explicitly set the command line with an optional nonce
        # 633;P;Cwd=<path> - Mark the current working directory and communicate it to the terminal
        # and also helps with the run recent menu in vscode
        osc633: true
        # reset_application_mode is escape \x1b[?1l and was added to help ssh work better
        reset_application_mode: true
    }
    render_right_prompt_on_last_line: false # true or false to enable or disable right prompt to be rendered on last line of the prompt.
    use_kitty_protocol: false # enables keyboard enhancement protocol implemented by kitty console, only if your terminal support this.
    highlight_resolved_externals: false # true enables highlighting of external commands in the repl resolved by which.
    recursion_limit: 50 # the maximum number of times nushell allows recursion before stopping it

    plugins: {} # Per-plugin configuration. See https://www.nushell.sh/contributor-book/plugins.html#configuration.

    plugin_gc: {
        # Configuration for plugin garbage collection
        default: {
            enabled: true # true to enable stopping of inactive plugins
            stop_after: 10sec # how long to wait after a plugin is inactive to stop it
        }
        plugins: {
            # alternate configuration for specific plugins, by name, for example:
            #
            # gstat: {
            #     enabled: false
            # }
        }
    }

    hooks: {
        pre_prompt: [{ null }] # run before the prompt is shown
        pre_execution: [{ null }] # run before the repl input is run
        env_change: {
            PWD: [{|before, after|
                # fnm: auto-switch node version on cd
                if ([.node-version .nvmrc] | any {|f| ($after | path join $f) | path exists }) {
                    let new_env = (^fnm env --json | from json)
                    $env.FNM_MULTISHELL_PATH = $new_env.FNM_MULTISHELL_PATH
                    $env.PATH = ($env.PATH | prepend ($new_env.FNM_MULTISHELL_PATH | path join "bin"))
                }
            }]
        }
        display_output: "if (term size).columns >= 100 { table -e } else { table }" # run to display the output of a pipeline
        command_not_found: { null } # return an error message when a command is not found
    }

    menus: [
        # Configuration for default nushell menus
        # Note the lack of source parameter
        {
            name: completion_menu
            only_buffer_difference: false
            marker: "| "
            type: {
                layout: columnar
                columns: 4
                col_width: 20     # Optional value. If missing all the screen width is used to calculate column width
                col_padding: 2
            }
            style: {
                text: green
                selected_text: { attr: r }
                description_text: yellow
                match_text: { attr: u }
                selected_match_text: { attr: ur }
            }
        }
        {
            name: ide_completion_menu
            only_buffer_difference: false
            marker: "| "
            type: {
                layout: ide
                min_completion_width: 0,
                max_completion_width: 50,
                max_completion_height: 10, # will be limited by the available lines in the terminal
                padding: 0,
                border: true,
                cursor_offset: 0,
                description_mode: "prefer_right"
                min_description_width: 0
                max_description_width: 50
                max_description_height: 10
                description_offset: 1
                # If true, the cursor pos will be corrected, so the suggestions match up with the typed text
                #
                # C:\> str
                #      str join
                #      str trim
                #      str split
                correct_cursor_pos: false
            }
            style: {
                text: green
                selected_text: { attr: r }
                description_text: yellow
                match_text: { attr: u }
                selected_match_text: { attr: ur }
            }
        }
        {
            name: history_menu
            only_buffer_difference: true
            marker: "? "
            type: {
                layout: list
                page_size: 10
            }
            style: {
                text: green
                selected_text: green_reverse
                description_text: yellow
            }
        }
        {
            name: help_menu
            only_buffer_difference: true
            marker: "? "
            type: {
                layout: description
                columns: 4
                col_width: 20     # Optional value. If missing all the screen width is used to calculate column width
                col_padding: 2
                selection_rows: 4
                description_rows: 10
            }
            style: {
                text: green
                selected_text: green_reverse
                description_text: yellow
            }
        }
    ]

    keybindings: [
        {
            name: delete_one_word_backward
            modifier: alt
            keycode: backspace
            mode: [emacs, vi_normal, vi_insert]
            event: {edit: backspaceword}
        }
        {
            name: completion_menu
            modifier: none
            keycode: tab
            mode: [emacs vi_normal vi_insert]
            event: {
                until: [
                    { send: menu name: completion_menu }
                    { send: menunext }
                    { edit: complete }
                ]
            }
        }
        {
            name: ide_completion_menu
            modifier: control
            keycode: char_n
            mode: [emacs vi_normal vi_insert]
            event: {
                until: [
                    { send: menu name: ide_completion_menu }
                    { send: menunext }
                    { edit: complete }
                ]
            }
        }
        {
            name: history_menu
            modifier: control
            keycode: char_r
            mode: [emacs, vi_insert, vi_normal]
            event: { send: menu name: history_menu }
        }
        {
            name: help_menu
            modifier: none
            keycode: f1
            mode: [emacs, vi_insert, vi_normal]
            event: { send: menu name: help_menu }
        }
        {
            name: completion_previous_menu
            modifier: shift
            keycode: backtab
            mode: [emacs, vi_normal, vi_insert]
            event: { send: menuprevious }
        }
        {
            name: next_page_menu
            modifier: control
            keycode: char_x
            mode: emacs
            event: { send: menupagenext }
        }
        {
            name: undo_or_previous_page_menu
            modifier: control
            keycode: char_z
            mode: emacs
            event: {
                until: [
                    { send: menupageprevious }
                    { edit: undo }
                ]
            }
        }
        {
            name: escape
            modifier: none
            keycode: escape
            mode: [emacs, vi_normal, vi_insert]
            event: { send: esc }    # NOTE: does not appear to work
        }
        {
            name: cancel_command
            modifier: control
            keycode: char_c
            mode: [emacs, vi_normal, vi_insert]
            event: { send: ctrlc }
        }
        {
            name: quit_shell
            modifier: control
            keycode: char_d
            mode: [emacs, vi_normal, vi_insert]
            event: { send: ctrld }
        }
        {
            name: clear_screen
            modifier: control
            keycode: char_l
            mode: [emacs, vi_normal, vi_insert]
            event: { send: clearscreen }
        }
        {
            name: search_history
            modifier: control
            keycode: char_q
            mode: [emacs, vi_normal, vi_insert]
            event: { send: searchhistory }
        }
        {
            name: open_command_editor
            modifier: control
            keycode: char_o
            mode: [emacs, vi_normal, vi_insert]
            event: { send: openeditor }
        }
        {
            name: move_up
            modifier: none
            keycode: up
            mode: [emacs, vi_normal, vi_insert]
            event: {
                until: [
                    { send: menuup }
                    { send: up }
                ]
            }
        }
        {
            name: move_down
            modifier: none
            keycode: down
            mode: [emacs, vi_normal, vi_insert]
            event: {
                until: [
                    { send: menudown }
                    { send: down }
                ]
            }
        }
        {
            name: move_left
            modifier: none
            keycode: left
            mode: [emacs, vi_normal, vi_insert]
            event: {
                until: [
                    { send: menuleft }
                    { send: left }
                ]
            }
        }
        {
            name: move_right_or_take_history_hint
            modifier: none
            keycode: right
            mode: [emacs, vi_normal, vi_insert]
            event: {
                until: [
                    { send: historyhintcomplete }
                    { send: menuright }
                    { send: right }
                ]
            }
        }
        {
            name: move_one_word_left
            modifier: control
            keycode: left
            mode: [emacs, vi_normal, vi_insert]
            event: { edit: movewordleft }
        }
        {
            name: move_one_word_right_or_take_history_hint
            modifier: control
            keycode: right
            mode: [emacs, vi_normal, vi_insert]
            event: {
                until: [
                    { send: historyhintwordcomplete }
                    { edit: movewordright }
                ]
            }
        }
        {
            name: move_to_line_start
            modifier: none
            keycode: home
            mode: [emacs, vi_normal, vi_insert]
            event: { edit: movetolinestart }
        }
        {
            name: move_to_line_start
            modifier: control
            keycode: char_a
            mode: [emacs, vi_normal, vi_insert]
            event: { edit: movetolinestart }
        }
        {
            name: move_to_line_end_or_take_history_hint
            modifier: none
            keycode: end
            mode: [emacs, vi_normal, vi_insert]
            event: {
                until: [
                    { send: historyhintcomplete }
                    { edit: movetolineend }
                ]
            }
        }
        {
            name: move_to_line_end_or_take_history_hint
            modifier: control
            keycode: char_e
            mode: [emacs, vi_normal, vi_insert]
            event: {
                until: [
                    { send: historyhintcomplete }
                    { edit: movetolineend }
                ]
            }
        }
        {
            name: move_to_line_start
            modifier: control
            keycode: home
            mode: [emacs, vi_normal, vi_insert]
            event: { edit: movetolinestart }
        }
        {
            name: move_to_line_end
            modifier: control
            keycode: end
            mode: [emacs, vi_normal, vi_insert]
            event: { edit: movetolineend }
        }
        {
            name: move_up
            modifier: control
            keycode: char_p
            mode: [emacs, vi_normal, vi_insert]
            event: {
                until: [
                    { send: menuup }
                    { send: up }
                ]
            }
        }
        {
            name: move_down
            modifier: control
            keycode: char_t
            mode: [emacs, vi_normal, vi_insert]
            event: {
                until: [
                    { send: menudown }
                    { send: down }
                ]
            }
        }
        {
            name: delete_one_character_backward
            modifier: none
            keycode: backspace
            mode: [emacs, vi_insert]
            event: { edit: backspace }
        }
        {
            name: delete_one_word_backward
            modifier: control
            keycode: backspace
            mode: [emacs, vi_insert]
            event: { edit: backspaceword }
        }
        {
            name: delete_one_character_forward
            modifier: none
            keycode: delete
            mode: [emacs, vi_insert]
            event: { edit: delete }
        }
        {
            name: delete_one_character_forward
            modifier: control
            keycode: delete
            mode: [emacs, vi_insert]
            event: { edit: delete }
        }
        {
            name: delete_one_character_backward
            modifier: control
            keycode: char_h
            mode: [emacs, vi_insert]
            event: { edit: backspace }
        }
        {
            name: delete_one_word_backward
            modifier: control
            keycode: char_w
            mode: [emacs, vi_insert]
            event: { edit: backspaceword }
        }
        {
            name: move_left
            modifier: none
            keycode: backspace
            mode: vi_normal
            event: { edit: moveleft }
        }
        {
            name: newline_or_run_command
            modifier: none
            keycode: enter
            mode: emacs
            event: { send: enter }
        }
        {
            name: move_left
            modifier: control
            keycode: char_b
            mode: emacs
            event: {
                until: [
                    { send: menuleft }
                    { send: left }
                ]
            }
        }
        {
            name: move_right_or_take_history_hint
            modifier: control
            keycode: char_f
            mode: emacs
            event: {
                until: [
                    { send: historyhintcomplete }
                    { send: menuright }
                    { send: right }
                ]
            }
        }
        {
            name: redo_change
            modifier: control
            keycode: char_g
            mode: emacs
            event: { edit: redo }
        }
        {
            name: undo_change
            modifier: control
            keycode: char_z
            mode: emacs
            event: { edit: undo }
        }
        {
            name: paste_before
            modifier: control
            keycode: char_y
            mode: emacs
            event: { edit: pastecutbufferbefore }
        }
        {
            name: cut_word_left
            modifier: control
            keycode: char_w
            mode: emacs
            event: { edit: cutwordleft }
        }
        {
            name: cut_line_to_end
            modifier: control
            keycode: char_k
            mode: emacs
            event: { edit: cuttoend }
        }
        {
            name: cut_line_from_start
            modifier: control
            keycode: char_u
            mode: emacs
            event: { edit: cutfromstart }
        }
        {
            name: swap_graphemes
            modifier: control
            keycode: char_t
            mode: emacs
            event: { edit: swapgraphemes }
        }
        {
            name: move_one_word_left
            modifier: alt
            keycode: left
            mode: emacs
            event: { edit: movewordleft }
        }
        {
            name: move_one_word_right_or_take_history_hint
            modifier: alt
            keycode: right
            mode: emacs
            event: {
                until: [
                    { send: historyhintwordcomplete }
                    { edit: movewordright }
                ]
            }
        }
        {
            name: move_one_word_left
            modifier: alt
            keycode: char_b
            mode: emacs
            event: { edit: movewordleft }
        }
        {
            name: move_one_word_right_or_take_history_hint
            modifier: alt
            keycode: char_f
            mode: emacs
            event: {
                until: [
                    { send: historyhintwordcomplete }
                    { edit: movewordright }
                ]
            }
        }
        {
            name: delete_one_word_forward
            modifier: alt
            keycode: delete
            mode: emacs
            event: { edit: deleteword }
        }
        {
            name: delete_one_word_backward
            modifier: alt
            keycode: backspace
            mode: emacs
            event: { edit: backspaceword }
        }
        {
            name: delete_one_word_backward
            modifier: alt
            keycode: char_m
            mode: emacs
            event: { edit: backspaceword }
        }
        {
            name: cut_word_to_right
            modifier: alt
            keycode: char_d
            mode: emacs
            event: { edit: cutwordright }
        }
        {
            name: upper_case_word
            modifier: alt
            keycode: char_u
            mode: emacs
            event: { edit: uppercaseword }
        }
        {
            name: lower_case_word
            modifier: alt
            keycode: char_l
            mode: emacs
            event: { edit: lowercaseword }
        }
        {
            name: capitalize_char
            modifier: alt
            keycode: char_c
            mode: emacs
            event: { edit: capitalizechar }
        }
        # The following bindings with `*system` events require that Nushell has
        # been compiled with the `system-clipboard` feature.
        # This should be the case for Windows, macOS, and most Linux distributions
        # Not available for example on Android (termux)
        # If you want to use the system clipboard for visual selection or to
        # paste directly, uncomment the respective lines and replace the version
        # using the internal clipboard.
        {
            name: copy_selection
            modifier: control_shift
            keycode: char_c
            mode: emacs
            event: { edit: copyselection }
            # event: { edit: copyselectionsystem }
        }
        {
            name: cut_selection
            modifier: control_shift
            keycode: char_x
            mode: emacs
            event: { edit: cutselection }
            # event: { edit: cutselectionsystem }
        }
        # {
        #     name: paste_system
        #     modifier: control_shift
        #     keycode: char_v
        #     mode: emacs
        #     event: { edit: pastesystem }
        # }
        {
            name: select_all
            modifier: control_shift
            keycode: char_a
            mode: emacs
            event: { edit: selectall }
        }
    ]
}

# ── Yazi file manager (CWD sync wrapper) ──
def --env y [...args] {
    let tmp = (mktemp -t "yazi-cwd.XXXXXX")
    yazi ...$args --cwd-file $tmp
    let cwd = (open $tmp)
    if $cwd != "" and $cwd != $env.PWD and ($cwd | path exists) {
        cd $cwd
    }
    rm -fp $tmp
}

def --env cx [arg] {
    cd $arg
    ls -l
}

# ── Drop-in Rust replacements ──
alias l = ls --all
alias c = clear
alias ll = ls -l
alias lt = ls -l
alias eza = echo "eza is gone. Nushell's built-in ls is better. Use: ls, ls -l, or ls --all"
alias cat = bat
alias du = dua
alias top = btm
alias ps = procs
alias diff = delta
alias v = nvim
alias hms = home-manager switch
alias as = aerospace

# ── Reminder aliases (incompatible syntax — use the modern tool) ──
# Only when I'm the one typing — agents get real grep/find/sed.
# Only block when I'm at a real terminal — not an agent subshell
let _my_terminal = ($env.TERM_PROGRAM? | default "") in ["ghostty" "WezTerm" "Alacritty"]
let _has_tty = (do { ^tty } | complete).exit_code == 0
if $_my_terminal and $_has_tty {
    alias grep = echo "grep is gone. Use rg (ripgrep) instead: rg PATTERN"
    alias find = echo "find is gone. Use fd instead: fd PATTERN"
    alias sed = echo "sed is gone. Use sd instead: sd 'old' 'new' file"
}

# ── Block legacy Python tooling — agents and humans alike ──
alias pipenv = echo "pipenv is disabled. Use uv instead: uv run, uv sync, uv add, uv venv"
alias poetry = echo "poetry is disabled. Use uv instead: uv init, uv add, uv run, uv build, uv publish"
alias pipx = echo "pipx is disabled. Use uv instead: uv tool install, uv tool run, uv tool list"
alias python = echo "Direct python is disabled. Use: uv run python, uv run script.py, or uv run pytest"
alias python3 = echo "Direct python3 is disabled. Use: uv run python, uv run script.py, or uv run pytest"

# ── Block legacy Node tooling — use bun instead ──
alias node = echo "node is disabled. Use bun instead: bun run, bun index.js"
alias npm = echo "npm is disabled. Use bun instead: bun install, bun add, bun remove, bun run"
alias pnpm = echo "pnpm is disabled. Use bun instead: bun install, bun add, bun remove, bun run"
# alias yarn = echo "yarn is disabled. Use bun instead: bun install, bun add, bun remove, bun run"
alias npx = echo "npx is disabled. Use bunx instead: bunx <package>"


def ff [] {
    aerospace list-windows --all | fzf --bind 'enter:execute(bash -c "aerospace focus --window-id {1}")+abort'
}


# Git
alias gc = git commit -m
alias gca = git commit -a -m
alias gp = git push origin HEAD
alias gpu = git pull origin
alias gst = git status
alias glog = git log --graph --topo-order --pretty='%w(100,0,6)%C(yellow)%h%C(bold)%C(black)%d %C(cyan)%ar %C(green)%an%n%C(bold)%C(white)%s %N' --abbrev-commit
alias gdiff = git diff
alias gco = git checkout
alias gb = git branch
alias gba = git branch -a
alias gadd = git add
alias ga = git add -p
alias gcoall = git checkout -- .
alias gr = git remote
alias gre = git reset


# K8s
alias k = kubectl
alias ka = kubectl apply -f
alias kg = kubectl get
alias kd = kubectl describe
alias kdel = kubectl delete
alias kl = kubectl logs -f
alias kgpo = kubectl get pod
alias kgd = kubectl get deployments
alias kc = kubectx
alias kns = kubens
alias ke = kubectl exec -it
alias xtotxt = yek

# GlobalProtect VPN (modern launchctl syntax)
alias stop_gp = sudo launchctl bootout gui/(id -u) /Library/LaunchAgents/com.paloaltonetworks.gp.pangp*
alias start_gp = sudo launchctl bootstrap gui/(id -u) /Library/LaunchAgents/com.paloaltonetworks.gp.pangp*

# Flux
alias fluxr = flux reconcile source git flux-system --namespace=flux-system

# ── Cloudflare Tunnel to Talos K8s ──
def k8s_up [] {
  print "Starting cloudflared tunnel to k8s.amernas.work → localhost:16443..."
  cloudflared access tcp --hostname k8s.amernas.work --url localhost:16443 out+err> /dev/null &
  sleep 2sec
  print "Tunnel running. Use: kubectl --context talos-tunnel get nodes"
  print "Stop with: ps | where name == cloudflared | get pid | each { |p| kill $p }"
}

# ── Quick references ──
alias tldr = tealdeer
def oc [] {
  let refcount_file = "/tmp/.oc_tunnel_refcount"

  # Increment reference count
  let count = if ($refcount_file | path exists) {
    (open $refcount_file | str trim | into int)
  } else {
    0
  }
  ($count + 1 | into string) | save -f $refcount_file

  # Start cloudflared tunnel if not already running
  let running = (^pgrep -f "cloudflared tunnel run opencode" | complete | get exit_code) == 0
  if not $running {
    print "Starting cloudflared tunnel..."
    ^cloudflared tunnel run opencode out+err> /dev/null &
  }

  # Ensure opencode serve is running on port 4096
  let port_open = (^nc -z localhost 4096 | complete | get exit_code) == 0
  if not $port_open {
    print "opencode serve not responding \u{2014} restarting service..."
    ^launchctl kickstart -k $"gui/(id -u | str trim)/com.opencode.serve"
  }

  # Wait for port 4096 with timeout
  mut retries = 0
  let max_retries = 10
  mut serve_ready = false
  loop {
    let check = (^nc -z localhost 4096 | complete | get exit_code) == 0
    if $check {
      $serve_ready = true
      break
    }
    $retries += 1
    if $retries >= $max_retries {
      break
    }
    sleep 1sec
  }

  if $serve_ready {
    opencode attach http://localhost:4096 --dir $env.PWD --log-level ERROR
  } else {
    print "\u{26a0}\u{fe0f}  opencode serve not ready after 10s \u{2014} launching opencode locally."
    opencode --dir $env.PWD
  }

  # Decrement reference count and stop tunnel if last session
  let count = (open $refcount_file | str trim | into int)
  if $count <= 1 {
    rm -f $refcount_file
    ^pkill -f "cloudflared tunnel run opencode"
    print "Tunnel stopped."
  } else {
    ($count - 1 | into string) | save -f $refcount_file
  }
}

# source ~/.config/nushell/env.nu
if (which zoxide | is-not-empty) and (("~/.zoxide.nu" | path expand) | path exists) {
    source ~/.zoxide.nu
}
if (("~/.cache/carapace/init.nu" | path expand) | path exists) {
    source ~/.cache/carapace/init.nu
}
if (which atuin | is-not-empty) and (("~/.local/share/atuin/init.nu" | path expand) | path exists) {
    source ~/.local/share/atuin/init.nu
}
if (which starship | is-not-empty) and (("~/.cache/starship/init.nu" | path expand) | path exists) {
    use ~/.cache/starship/init.nu
}
source ~/.config/nushell/scripts/gpr.nu
use ~/.config/nushell/scripts/profiler.nu *

$env.config.hooks.pre_prompt = (
    ($env.config.hooks.pre_prompt? | default [])
    | append {||
        if (which direnv | is-not-empty) {
            direnv export json
                | from json --strict
                | default {}
                | items {|key, value|
                    let value = do (
                        {
                            "PATH": {
                                from_string: {|s| $s | split row (char esep) | path expand --no-symlink }
                                to_string: {|v| $v | path expand --no-symlink | str join (char esep) }
                            }
                        }
                        | merge ($env.ENV_CONVERSIONS? | default {})
                        | get ([[value, optional, insensitive]; [$key, true, true] [from_string, true, false]] | into cell-path)
                        | if ($in | is-empty) { {|x| $x} } else { $in }
                    ) $value
                    return [ $key $value ]
                }
                | into record
                | load-env
        }
    }
)

# ── REPL timing hooks (appended after all sources so Atuin hooks are preserved) ──
$env.config.hooks.pre_execution = (
    ($env.config.hooks.pre_execution? | default [])
    | append {||
        if ($env.__nu_profile_enabled? | default false) {
            $env.__nu_profile_start = (date now)
            $env.__nu_profile_cmd = (commandline)
        }
    }
)

$env.config.hooks.pre_prompt = (
    ($env.config.hooks.pre_prompt? | default [])
    | append {||
        if $env.__nu_profile_start != null {
            let elapsed = (date now) - $env.__nu_profile_start
            $env.__nu_profile_log = (
                $env.__nu_profile_log
                | append {
                    when: (date now)
                    cmd: $env.__nu_profile_cmd
                    duration: $elapsed
                }
            )
            print $"[($elapsed)] ($env.__nu_profile_cmd)"
            $env.__nu_profile_start = null
            $env.__nu_profile_cmd = null
        }
    }
)

# olmocr shortcut
alias ocr = olmocr
alias pdfmd = olmocr

# OpenCode cleanup & restart
def oc-restart [] {
    let log_dir = $"($env.HOME)/.local/share/opencode/log"
    let serve_log = $"($env.HOME)/.local/share/opencode/serve.log"

    print "🔍 Current log usage:"
    du $log_dir | get apparent | first

    print "🗑️  Removing logs..."
    glob $"($log_dir)/*.log" | each { |f| rm -f $f }
    "" | save -f $serve_log
    print "✅ Logs cleared"

    print "🔄 Restarting opencode service..."
    run-external "launchctl" "kickstart" "-k" $"gui/(id -u | str trim)/com.opencode.serve"

    sleep 2sec
    print "📊 Disk status:"
    df / | print
}
