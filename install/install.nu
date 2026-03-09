#!/usr/bin/env nu

# Cross-platform dotfiles installer

def main [--dry-run] {
    let dotfiles_root = ($env.FILE_PWD | path join ".." | path expand)

    let platform = match ($nu.os-info.name) {
        "linux" => "linux"
        "macos" => "macos"
        "windows" => "windows"
        _ => { error make {msg: $"Unsupported platform: ($nu.os-info.name)"} }
    }

    let is_meta = (sys host | get hostname | str contains "facebook")

    print $"Platform: ($platform)(if $is_meta { ' (meta)' })"
    if $dry_run { print "[DRY RUN] No changes will be made." }
    print ""

    let links = [
        # --- git ---
        { source: "git/gitconfig", method: symlink, target: "~/.gitconfig" }
        { source: "git/gitconfig.{platform}", method: symlink, target: "~/.gitconfig.os" }

        # --- nushell ---
        { source: "nushell/env.nu", method: copy, target: { linux: "~/.config/nushell/env.nu", macos: "~/.config/nushell/env.nu", windows: "~/AppData/Roaming/nushell/env.nu" } }
        { source: "nushell/config.nu", method: symlink, target: { linux: "~/.config/nushell/config.nu", macos: "~/.config/nushell/config.nu", windows: "~/AppData/Roaming/nushell/config.nu" } }

        # --- tmux ---
        { source: "tmux/tmux.conf.stub", method: copy, target: { linux: "~/.tmux.conf", macos: "~/.tmux.conf" } }

        # --- powershell ---
        { source: "powershell/profile.ps1.stub", method: copy, target: { linux: "~/.config/powershell/Microsoft.PowerShell_profile.ps1", macos: "~/.config/powershell/Microsoft.PowerShell_profile.ps1", windows: "~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1" } }

        # --- vscode ---
        # { source: "vscode/settings.json", method: symlink, target: { linux: "~/.config/Code - Insiders/User/settings.json", macos: "~/Library/Application Support/Code - Insiders/User/settings.json", windows: "~/AppData/Roaming/Code - Insiders/User/settings.json" } }

        # --- vsc-meta ---
        # { source: "vsc-meta/settings.json", method: symlink, target: { linux: "~/.config/VS Code @ FB - Dev/User/settings.json", macos: "~/Library/Application Support/VS Code @ FB - Dev/User/settings.json", windows: "~/AppData/Roaming/VS Code @ FB - Dev/User/settings.json" } }

        # --- windows terminal ---
        { source: "terminal/settings.json", method: symlink, target: { windows: "~/AppData/Local/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json" } }
    ]

    mut created = 0
    mut updated = 0
    mut skipped = 0
    mut backed_up = 0

    for entry in $links {
        # Resolve target for this platform
        let target_raw = if ($entry.target | describe | str starts-with "record") {
            let t = $entry.target
            if ($platform in ($t | columns)) {
                $t | get $platform
            } else {
                null
            }
        } else {
            $entry.target
        }

        if $target_raw == null {
            continue
        }

        let source_resolved = $entry.source | str replace "{platform}" $platform
        let source_path = if $is_meta {
            let meta_path = $dotfiles_root | path join $"($source_resolved).meta"
            if ($meta_path | path exists) { $meta_path } else { $dotfiles_root | path join $source_resolved }
        } else {
            $dotfiles_root | path join $source_resolved
        }
        let target_path = $target_raw | path expand --no-symlink
        let target_dir = $target_path | path dirname
        let bak_path = $"($target_path).bak"

        # Check if target is already a correct symlink
        let is_correct_symlink = if ($target_path | path exists) {
            let target_type = (ls -l $target_path | get type.0)
            if $target_type == "symlink" {
                (ls -l $target_path | get target.0) == ($source_path | path expand)
            } else {
                false
            }
        } else {
            false
        }

        if $entry.method == "symlink" {
            if $is_correct_symlink {
                print $"  [skip] ($target_path) -> ($source_path) \(already correct)"
                $skipped += 1
            } else if $dry_run {
                if ($target_path | path exists) {
                    print $"  [backup] ($target_path) -> ($bak_path)"
                    print $"  [symlink] ($target_path) -> ($source_path) \(update)"
                } else {
                    print $"  [mkdir] ($target_dir)"
                    print $"  [symlink] ($target_path) -> ($source_path) \(create)"
                }
            } else {
                mkdir $target_dir
                if ($target_path | path exists) {
                    # Backup existing file
                    if ($bak_path | path exists) { rm $bak_path }
                    mv $target_path $bak_path
                    print $"  [backup] ($target_path) -> ($bak_path)"
                    $backed_up += 1

                    ln -s $source_path $target_path
                    print $"  [symlink] ($target_path) -> ($source_path) \(updated)"
                    $updated += 1
                } else {
                    ln -s $source_path $target_path
                    print $"  [symlink] ($target_path) -> ($source_path) \(created)"
                    $created += 1
                }
            }
        } else if $entry.method == "copy" {
            if $dry_run {
                if ($target_path | path exists) {
                    let source_hash = (open --raw $source_path | hash md5)
                    let target_hash = (open --raw $target_path | hash md5)
                    if $source_hash == $target_hash {
                        print $"  [skip] ($target_path) \(identical)"
                    } else {
                        print $"  [diff] ($target_path) differs from ($source_path):"
                        try { diff $target_path $source_path } catch { }
                        print $"  [copy] ($target_path) <- ($source_path) \(would prompt to overwrite)"
                    }
                } else {
                    if not ($target_dir | path exists) {
                        print $"  [mkdir] ($target_dir)"
                    }
                    print $"  [copy] ($target_path) <- ($source_path) \(create)"
                }
            } else {
                mkdir $target_dir
                if ($target_path | path exists) {
                    let source_hash = (open --raw $source_path | hash md5)
                    let target_hash = (open --raw $target_path | hash md5)

                    if $source_hash == $target_hash {
                        print $"  [skip] ($target_path) \(identical)"
                        $skipped += 1
                    } else {
                        # Show diff
                        print $"  [diff] ($target_path) differs from ($source_path):"
                        try { diff $target_path $source_path } catch { }

                        let answer = (input $"  Overwrite ($target_path)? [O]verwrite / [S]kip: ")
                        if ($answer | str downcase | str starts-with "o") {
                            if ($bak_path | path exists) { rm $bak_path }
                            mv $target_path $bak_path
                            print $"  [backup] ($target_path) -> ($bak_path)"
                            $backed_up += 1

                            cp $source_path $target_path
                            print $"  [copy] ($target_path) \(updated)"
                            $updated += 1
                        } else {
                            print $"  [skip] ($target_path) \(user skipped)"
                            $skipped += 1
                        }
                    }
                } else {
                    cp $source_path $target_path
                    print $"  [copy] ($target_path) \(created)"
                    $created += 1
                }
            }
        }
    }

    print ""
    if $dry_run {
        print "[DRY RUN] Summary of planned actions above. No changes were made."
    } else {
        print $"Done. Created: ($created), Updated: ($updated), Skipped: ($skipped), Backed up: ($backed_up)"
    }
}
