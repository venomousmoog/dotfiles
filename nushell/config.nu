# config.nu -- Main nushell configuration
# Sources modules, sets aliases, hooks, and keybindings

# Source modules (order doesn't matter for function availability)
source listing.nu
source tools.nu
source ~/.cache/nushell/zoxide.nu

# ls -- eza wrapper with icons, grid by default (eza's default mode)
# Use ^ls for nushell's built-in structured ls (pipeline use)
# Post-processing: moves -F suffixes inside color spans, replaces -> with nerd font arrow
def --wrapped ls [...rest] {
    let esc = (char -u "1b")
    let w = (term size).columns
    ^eza --icons --group-directories-first -F --color=always $"--width=($w)" ...$rest
    | str replace --all $"($esc)[0m/" $"/($esc)[0m"
    | str replace --all $"($esc)[0m@" $"@($esc)[0m"
    | str replace --all " -> " " \u{ea9c} "
    | print -n
}
def --wrapped ll [...rest] {
    let esc = (char -u "1b")
    ^eza --icons --group-directories-first -F --color=always -l ...$rest
    | str replace --all $"($esc)[0m/" $"/($esc)[0m"
    | str replace --all $"($esc)[0m@" $"@($esc)[0m"
    | str replace --all " -> " " \u{ea9c} "
    | print -n
}
alias tree = ^eza --icons --group-directories-first --tree

# Aliases -- bat as cat/less replacement
alias cat = ^bat
alias less = ^bat
alias iex = load-bash-env

# Startup banner -- show only startup time
$env.config.show_banner = false
print $"Startup Time: ($nu.startup-time)"

# Disable terminal title (OSC 2) -- tmux status line handles this
$env.config.shell_integration.osc2 = false

# display_output hook -- adds Nerd Font icons, colors, and type suffixes
# to ^ls (nushell built-in) table output (/ for directories, @ for symlinks)
$env.config.hooks.display_output = {||
    let input = $in
    let type_str = ($input | describe)
    if ($type_str | str starts-with "table") {
        let cols = ($input | columns)
        if ("name" in $cols and "type" in $cols) {
            $input | each {|row|
                $row | upsert name (format-file-entry $row.name $row.type)
            } | table
        } else {
            $input | table
        }
    } else {
        $input | table
    }
}

# pre_prompt hook -- update tmux env vars and window title
$env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt | default [] | append {||
    if "TMUX" in $env {
        update-tmux-env
    }
})
