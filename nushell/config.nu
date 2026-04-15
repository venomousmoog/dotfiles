# config.nu -- Main nushell configuration
# Environment setup, modules, aliases, hooks, and keybindings
# Bootstrap (cloning, DOTFILES_PATH, NU_LIB_DIRS) handled by ~/.config/nushell/env.nu

# ENV_CONVERSIONS -- tells nushell how to convert PATH between string and list
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

# Platform detection
let os = $nu.os-info.name

# Platform directory name (matches Tools/ subdirectory names)
let platform_dir = match $os {
    "linux" => "Unix"
    "macos" => "MacOS"
    "windows" => "Win32NT"
    _ => "Unix"
}

# PATH additions (before dependency checks so tools in dotfiles are found)
$env.PATH = ($env.PATH | prepend $"($env.DOTFILES_PATH)/powershell/Tools/($platform_dir)")
$env.PATH = ($env.PATH | prepend $"($env.DOTFILES_PATH)/scripts")

if $os == "linux" {
    $env.PATH = ($env.PATH | append "/packages/adb/latest/")
}

if $os == "macos" {
    let brew_path = ($env.HOME | path join "homebrew/bin/brew")
    if ($brew_path | path exists) {
        let brew_prefix = (^$brew_path --prefix | str trim)
        $env.PATH = ($env.PATH | prepend [
            $"($brew_prefix)/bin"
            $"($brew_prefix)/sbin"
        ])
    }
    $env.PATH = ($env.PATH | append "/Users/ddriver/Library/Android/sdk/platform-tools/")
}

if $os == "windows" {
    let program_files_x86 = ($env | get? "ProgramFiles(x86)" | default "C:\\Program Files (x86)")
    $env.PATH = ($env.PATH | append [
        $"($program_files_x86)\\Windows Kits\\10\\Debuggers\\x64\\"
        $"($env.LOCALAPPDATA)\\Programs\\WinMerge"
        $"($env.LOCALAPPDATA)\\Android\\sdk\\platform-tools\\"
    ])
    if 'OneDriveConsumer' in $env {
        $env.PATH = ($env.PATH | append [
            $"($env.OneDriveConsumer)\\tools\\platform-tools\\"
            $"($env.OneDriveConsumer)\\tools\\"
        ])
    }
}

# Dependency checks (after PATH so dotfiles tools are discoverable)
for $tool in [oh-my-posh bat zoxide] {
    if (which $tool | is-empty) {
        print $"(ansi red)Warning: '($tool)' is not installed. Some features will be unavailable.(ansi reset)"
    }
}
if (which eza | is-empty) {
    print $"(ansi yellow_dimmed)Note: 'eza' is not installed. Grid view \(l command\) will be unavailable.(ansi reset)"
}

# Environment variables
$env.VIRTUAL_ENV_DISABLE_PROMPT = "1"
$env.EDITOR = "code-fb --wait"
# USERNAME -- oh-my-posh config references .Env.USERNAME (Windows convention)
if "USER" in $env and not ("USERNAME" in $env) {
    $env.USERNAME = $env.USER
}


# oh-my-posh prompt (inline setup, no source/cache needed)
if not (which oh-my-posh | is-empty) {
    let omp_config = ($env.DOTFILES_PATH | path join "powershell" "ddriver.omp.json")
    # Verify the config file exists
    if ($omp_config | path exists) {
        $env.PROMPT_COMMAND = {||
            let width = (term size).columns
            (oh-my-posh print primary
                $"--config=($env.DOTFILES_PATH)/powershell/ddriver.omp.json"
                --shell=nu
                $"--shell-version=(version | get version)"
                $"--terminal-width=($width)")
        }
        # oh-my-posh embeds the rprompt inline in `print primary` (via cursor save/restore),
        # so we suppress nushell's separate right prompt to avoid double-rendering.
        $env.PROMPT_COMMAND_RIGHT = {|| "" }
        $env.PROMPT_INDICATOR = ""
        $env.PROMPT_MULTILINE_INDICATOR = ""
    }
}

# Source modules (order doesn't matter for function availability)
source listing.nu
source tools.nu
source theme.nu
source ~/.cache/nushell/zoxide.nu

# ls -- eza wrapper with icons, grid by default (eza's default mode)
# Use ^ls for nushell's built-in structured ls (pipeline use)
# Post-processing: moves -F suffixes inside color spans, replaces -> with nerd font arrow
def --wrapped ls [...rest] {
    let esc = (char -u "1b")
    let w = (term size).columns
    let args = ($rest | each {|a| if ($a | str starts-with "~") { $a | path expand } else { $a }})
    ^eza --icons --group-directories-first -F --color=always $"--width=(($w * 3 / 4) | into int)" ...$args
    | str replace --all $"($esc)[0m/" $"/($esc)[0m"
    | str replace --all $"($esc)[0m@" $"@($esc)[0m"
    | str replace --all " -> " " \u{ea9c} "
    | print -n
}
def --wrapped ll [...rest] {
    let esc = (char -u "1b")
    let args = ($rest | each {|a| if ($a | str starts-with "~") { $a | path expand } else { $a }})
    ^eza --icons --group-directories-first -F --color=always -l ...$args
    | str replace --all $"($esc)[0m/" $"/($esc)[0m"
    | str replace --all $"($esc)[0m@" $"@($esc)[0m"
    | str replace --all " -> " " \u{ea9c} "
    | print -n
}
alias tree = ^eza --icons --group-directories-first --tree

# nls -- nushell-native structured directory listing (since ls is shadowed by eza wrapper)
def nls [path?: string] {
    let p = ($path | default "." | path expand)
    glob ($p | path join "*") | each {|f| $f | path parse}
}

# Aliases -- bat as cat/less replacement
alias cat = ^bat --paging=never
alias less = ^bat --paging=auto
alias iex = load-bash-env

# Startup banner -- show only startup time
$env.config.show_banner = false
print $"Startup Time: ($nu.startup-time)"

# Disable terminal title (OSC 2) -- tmux status line handles this
$env.config.shell_integration.osc2 = false

# pre_prompt hook -- update tmux env vars and window title
$env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt | default [] | append {||
    if "TMUX" in $env {
        update-tmux-env
    }
})

# myclaw instance: rodan
alias myclaw-rodan = do {|...rest|
    with-env { MYCLAW_HOME: "/home/ddriver/.myclaw-rodan" } {
        myclaw ...$rest
    }
}
