# tools.nu -- Utility functions ported from PowerShell profile

# Load environment variables from a command that outputs bash 'export' syntax
# Usage: load-bash-env ek ae -x       (runs command, parses output)
#        ek ae -x | load-bash-env     (parses piped input)
def --env load-bash-env [...cmd: string] {
    let raw = if ($cmd | is-empty) { $in } else { ^($cmd | first) ...($cmd | skip 1) }
    let env_record = ($raw
        | parse --regex "([A-Za-z_][A-Za-z0-9_]*)='([^']*)'"
        | reduce -f {} {|row, acc| $acc | merge {($row.capture0): $row.capture1}})
    load-env $env_record
}

# Activate a Python virtual environment by walking up the directory tree
# Manually sets VIRTUAL_ENV and prepends bin dir to PATH (oh-my-posh handles prompt)
def --env venv [dir?: path] {
    let start_dir = if $dir != null { $dir } else { $env.PWD }
    mut current = ($start_dir | path expand)

    loop {
        let venv_path = ($current | path join ".venv")
        if ($venv_path | path exists) {
            let bin_dir = if $nu.os-info.name == "windows" {
                $venv_path | path join "Scripts"
            } else {
                $venv_path | path join "bin"
            }
            if ($bin_dir | path exists) {
                print $"using environment ($venv_path)"
                $env.VIRTUAL_ENV = ($venv_path | str replace ([$env.HOME "/"] | str join) "~/")
                $env.PATH = ($env.PATH | prepend $bin_dir)
                return
            } else {
                print $"(ansi yellow)Found .venv at ($venv_path) but no bin directory(ansi reset)"
                return
            }
        }
        let parent = ($current | path dirname)
        if $parent == $current {
            print $"(ansi red)No .venv/ found in directory tree(ansi reset)"
            return
        }
        $current = $parent
    }
}

# Update VSCode environment variables from tmux and set window title
# No-op when not in a tmux session
def --env update-tmux-env [] {
    if "TMUX" not-in $env { return }

    # Parse tmux environment for VSCode-related vars
    let tmux_lines = (^tmux show-environment | lines)

    for $var_name in [VSCODE_IPC_HOOK_CLI VSCODE_GIT_IPC_HANDLE VSCODE_GIT_ASKPASS_NODE VSCODE_GIT_ASKPASS_MAIN] {
        let matching = ($tmux_lines | where {|line| $line | str starts-with $"($var_name)="})
        if not ($matching | is-empty) {
            let line = ($matching | first)
            let parts = ($line | split row "=")
            let value = ($parts | skip 1 | str join "=")
            match $var_name {
                "VSCODE_IPC_HOOK_CLI" => { $env.VSCODE_IPC_HOOK_CLI = $value }
                "VSCODE_GIT_IPC_HANDLE" => { $env.VSCODE_GIT_IPC_HANDLE = $value }
                "VSCODE_GIT_ASKPASS_NODE" => { $env.VSCODE_GIT_ASKPASS_NODE = $value }
                "VSCODE_GIT_ASKPASS_MAIN" => { $env.VSCODE_GIT_ASKPASS_MAIN = $value }
            }
        }
    }

    # Update tmux window title using oh-my-posh
    if not (which oh-my-posh | is-empty) {
        let title_config = ($env.DOTFILES_PATH | path join "powershell" "tmux-title.omp.json")
        if ($title_config | path exists) {
            let title = (oh-my-posh print primary
                $"--config=($title_config)"
                --plain --shell=nu $"--pwd=($env.PWD)"
                | str trim)
            ^tmux rename-window -t $env.TMUX_PANE $title
        }
    }
}
alias ue = update-tmux-env

# Cross-platform symlink/hardlink creation
# Usage: ln <target> [link_path] [-s for symbolic]
def ln [
    target: path        # The file or directory to link to
    link?: path         # Where to create the link (default: current dir)
    --symbolic (-s)     # Create a symbolic link instead of a hard link
] {
    let target_path = ($target | path expand)
    if not ($target_path | path exists) {
        error make {msg: $"target not found: ($target)"}
    }

    mut link_path = if $link != null { $link | path expand } else { $env.PWD }

    # If link path is an existing directory, append the target's filename
    if ($link_path | path exists) and (($link_path | path type) == "dir") {
        $link_path = ($link_path | path join ($target_path | path basename))
    }

    if $nu.os-info.name == "windows" {
        let is_dir = ($target_path | path type) == "dir"
        if $symbolic {
            if $is_dir {
                ^cmd /c mklink /D $link_path $target_path
            } else {
                ^cmd /c mklink $link_path $target_path
            }
        } else {
            ^cmd /c mklink /H $link_path $target_path
        }
    } else {
        if $symbolic {
            ^ln -s $target_path $link_path
        } else {
            ^ln $target_path $link_path
        }
    }
}

# Detect python command (python3 on most systems, python on some Windows installs)
def --wrapped _python3 [...rest] {
    if not (which python3 | is-empty) {
        ^python3 ...$rest
    } else {
        ^python ...$rest
    }
}

# Buck build helpers -- wrappers around b/b.py
def --wrapped bb [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") build ...$rest }
def --wrapped br [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") run ...$rest }
def --wrapped bt [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") test ...$rest }
def --wrapped bq [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") query ...$rest }
def --wrapped bg [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") targets ...$rest }
def --wrapped bd [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") debug ...$rest }
def --wrapped bbq [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") buildq ...$rest }
def --wrapped brq [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") runq ...$rest }
def --wrapped btq [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") testq ...$rest }
def --wrapped bdq [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") debugq ...$rest }
def --wrapped bgq [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") targetsq ...$rest }
def --wrapped b [...rest] { _python3 ($env.DOTFILES_PATH | path join "b" "b.py") ...$rest }

# Set/clear/query BUCK_MODE environment variable
def --env bmode [
    mode?: string       # Mode name to set (e.g., "dev", "opt")
    --clear (-c)        # Clear the current mode
    --none (-n)         # Set mode to empty ("@")
    --auto (-a)         # Set mode to auto
] {
    if $clear {
        hide-env -i BUCK_MODE
    } else if $none {
        $env.BUCK_MODE = "@"
    } else if $auto {
        print "setting auto mode"
        $env.BUCK_MODE = "@auto"
    } else if $mode != null {
        print "setting new mode"
        $env.BUCK_MODE = $"@($mode)"
    }

    # Print current mode
    let buck_dir = ($env.DOTFILES_PATH | path join "b")
    _python3 -c $"import sys; sys.path.insert\(0, '($buck_dir)'\); from b import get_default_mode; print\(get_default_mode\(\)\)"
}

# Reversed hg smartlog -- shows history bottom-to-top
def sl [...rest] {
    let output = (^hg sl --color=always ...$rest)
    ($output
        | lines
        | reverse
        | str join "\n"
        | str replace --all '╯' '╮'
        | str replace --all '╭' '╰')
}

# grep with color auto
def grep [...rest] {
    ^grep --color=auto ...$rest
}
