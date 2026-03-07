# env.nu -- Dotfiles bootstrap
# Clones dotfiles if missing, sets up paths so config.nu can source from dotfiles
#
# NEW MACHINE SETUP: copy this file to ~/.config/nushell/env.nu
#   cp ~/src/dotfiles/nushell/env.nu ~/.config/nushell/env.nu
#   cp ~/src/dotfiles/nushell/config.nu ~/.config/nushell/config.nu
# These files must NOT be symlinks -- env.nu must exist before dotfiles are cloned

# Bootstrap: clone dotfiles repo if missing
let dotfiles_dir = ($env.HOME | path join "src" "dotfiles")
if not ($dotfiles_dir | path exists) {
    let src_dir = ($env.HOME | path join "src")
    if not ($src_dir | path exists) {
        mkdir $src_dir
    }
    print "Cloning dotfiles repository..."
    ^git clone https://github.com/venomousmoog/dotfiles $dotfiles_dir
}

$env.DOTFILES_PATH = ($env.HOME | path join "src" "dotfiles")

$env.NU_LIB_DIRS = [
    ($nu.default-config-dir | path join 'scripts')
    ($nu.data-dir | path join 'completions')
    ($env.DOTFILES_PATH | path join 'nushell')
]

# zoxide init -- generate cache file before config.nu parses (it sources the result)
mkdir ~/.cache/nushell
if not (which zoxide | is-empty) {
    zoxide init nushell | save -f ~/.cache/nushell/zoxide.nu
} else {
    "" | save -f ~/.cache/nushell/zoxide.nu
}
