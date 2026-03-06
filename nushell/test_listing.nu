# test_listing.nu -- Regression test for ls/ll wrappers and display_output hook
# Run with: nu --env-config ~/src/dotfiles/nushell/env.nu --config ~/src/dotfiles/nushell/config.nu ~/src/dotfiles/nushell/test_listing.nu
#
# Creates a temp directory with known file types, runs listing commands,
# captures raw output with ANSI codes, and checks for expected patterns.
# Results are saved to /tmp/nu_test_results.txt for inspection.

let test_dir = "/tmp/nu_listing_test"
let results_file = "/tmp/nu_test_results.txt"
let esc = (char -u "1b")

# --- Setup test directory ---
if ($test_dir | path exists) { rm -rf $test_dir }
mkdir $test_dir
mkdir $"($test_dir)/subdir"
"hello" | save $"($test_dir)/readme.md"
"print 1" | save $"($test_dir)/script.py"
"console.log(1)" | save $"($test_dir)/app.js"
"{}" | save $"($test_dir)/config.json"
"data" | save $"($test_dir)/archive.tar.gz"
"img" | save $"($test_dir)/photo.png"
^ln -s $"($test_dir)/readme.md" $"($test_dir)/link_to_readme"

mut output = "=== Nushell Listing Regression Test ===\n"
$output = $output + $"Date: (date now | format date '%Y-%m-%d %H:%M:%S')\n\n"

mut pass_count = 0
mut fail_count = 0

# --- Helper: run a check ---
def check [label: string, condition: bool] {
    if $condition {
        $"  PASS: ($label)\n"
    } else {
        $"  FAIL: ($label)\n"
    }
}

# =============================================
# Test 1: eza ls wrapper (grid view)
# =============================================
$output = $output + "--- Test 1: eza ls wrapper (grid view) ---\n"
let ls_raw = (^eza --icons --group-directories-first -F --color=always --width=120 $test_dir
    | str replace --all $"($esc)[0m/" $"/($esc)[0m"
    | str replace --all $"($esc)[0m@" $"@($esc)[0m"
    | str replace --all " -> " " \u{ea9c} ")

$output = $output + $"Raw output:\n($ls_raw)\n\n"

# Check: directory suffix '/' is present and colored (appears before reset, not after)
let has_dir_slash = ($ls_raw | str contains "subdir/")
let result = (check "directory has / suffix" $has_dir_slash)
$output = $output + $result
if $has_dir_slash { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: symlink suffix '@' is present
let has_link_at = ($ls_raw | str contains "link_to_readme@")
let result = (check "symlink has @ suffix" $has_link_at)
$output = $output + $result
if $has_link_at { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: ANSI color codes present (eza --color=always)
let has_ansi = ($ls_raw | str contains $"($esc)[")
let result = (check "ANSI color codes present" $has_ansi)
$output = $output + $result
if $has_ansi { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: suffix '/' comes BEFORE the reset, not after
# Pattern: the text should contain "subdir/\x1b[0m" (suffix then reset)
# and NOT contain "subdir\x1b[0m/" (reset then suffix)
let suffix_before_reset = ($ls_raw | str contains $"subdir/($esc)[0m")
let result = (check "dir suffix '/' is inside color span (before reset)" $suffix_before_reset)
$output = $output + $result
if $suffix_before_reset { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: @ suffix is inside color span
let at_before_reset = ($ls_raw | str contains $"link_to_readme@($esc)[0m")
let result = (check "symlink suffix '@' is inside color span (before reset)" $at_before_reset)
$output = $output + $result
if $at_before_reset { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

$output = $output + "\n"

# =============================================
# Test 2: eza ll wrapper (long view)
# =============================================
$output = $output + "--- Test 2: eza ll wrapper (long view) ---\n"
let ll_raw = (^eza --icons --group-directories-first -F --color=always -l $test_dir
    | str replace --all $"($esc)[0m/" $"/($esc)[0m"
    | str replace --all $"($esc)[0m@" $"@($esc)[0m"
    | str replace --all " -> " " \u{ea9c} ")

$output = $output + $"Raw output:\n($ll_raw)\n\n"

# Check: long format has permissions (eza colorizes each char, so strip ANSI first)
let ll_plain = ($ll_raw | ansi strip)
let has_perms = ($ll_plain =~ "[drwxl.-]{10}")
let result = (check "long format shows permissions" $has_perms)
$output = $output + $result
if $has_perms { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: directory suffix in long format
let ll_dir_slash = ($ll_raw | str contains "subdir/")
let result = (check "long format: directory has / suffix" $ll_dir_slash)
$output = $output + $result
if $ll_dir_slash { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: suffix colored in long format
let ll_suffix_colored = ($ll_raw | str contains $"subdir/($esc)[0m")
let result = (check "long format: dir suffix inside color span" $ll_suffix_colored)
$output = $output + $result
if $ll_suffix_colored { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: symlink arrow replaced with Nerd Font glyph (U+F178)
let has_nf_arrow = ($ll_raw | str contains "\u{ea9c}")
let result = (check "long format: symlink uses Nerd Font arrow" $has_nf_arrow)
$output = $output + $result
if $has_nf_arrow { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: plain -> is gone
let has_plain_arrow = ($ll_raw | str contains "->")
let result = (check "long format: plain -> arrow removed" (not $has_plain_arrow))
$output = $output + $result
if (not $has_plain_arrow) { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

$output = $output + "\n"

# =============================================
# Test 3: display_output hook (^ls / nushell built-in)
# =============================================
$output = $output + "--- Test 3: display_output hook (format-file-entry) ---\n"

# Test format-file-entry directly for each file type
let dir_entry = (format-file-entry "subdir" "dir")
$output = $output + $"  dir entry: ($dir_entry)\n"

let file_entry_py = (format-file-entry "script.py" "file")
$output = $output + $"  .py entry: ($file_entry_py)\n"

let file_entry_md = (format-file-entry "readme.md" "file")
$output = $output + $"  .md entry: ($file_entry_md)\n"

let link_entry = (format-file-entry "link_to_readme" "symlink")
$output = $output + $"  symlink entry: ($link_entry)\n"

$output = $output + "\n"

# Check: directory entry has icon and / suffix
let dir_has_slash = ($dir_entry | str contains "/")
let result = (check "format-file-entry: dir has / suffix" $dir_has_slash)
$output = $output + $result
if $dir_has_slash { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: symlink entry has @ suffix
let link_has_at = ($link_entry | str contains "@")
let result = (check "format-file-entry: symlink has @ suffix" $link_has_at)
$output = $output + $result
if $link_has_at { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: .py entry has ANSI color
let py_has_color = ($file_entry_py | str contains $"($esc)[")
let result = (check "format-file-entry: .py has ANSI color" $py_has_color)
$output = $output + $result
if $py_has_color { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: dir entry has ANSI color
let dir_has_color = ($dir_entry | str contains $"($esc)[")
let result = (check "format-file-entry: dir has ANSI color" $dir_has_color)
$output = $output + $result
if $dir_has_color { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

# Check: entries contain reset code (color properly terminated)
let dir_has_reset = ($dir_entry | str contains $"($esc)[0m")
let result = (check "format-file-entry: dir entry has ANSI reset" $dir_has_reset)
$output = $output + $result
if $dir_has_reset { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

$output = $output + "\n"

# =============================================
# Test 4: icon lookup
# =============================================
$output = $output + "--- Test 4: icon lookup ---\n"

let py_icon = (get-file-icon "script.py" "file")
let md_icon = (get-file-icon "readme.md" "file")
let dir_icon = (get-file-icon "subdir" "dir")
let js_icon = (get-file-icon "app.js" "file")
let json_icon = (get-file-icon "config.json" "file")

$output = $output + $"  .py icon: '($py_icon)'\n"
$output = $output + $"  .md icon: '($md_icon)'\n"
$output = $output + $"  dir icon: '($dir_icon)'\n"
$output = $output + $"  .js icon: '($js_icon)'\n"
$output = $output + $"  .json icon: '($json_icon)'\n\n"

# Check icons are non-empty
let py_icon_ok = ($py_icon | str length) > 0
let result = (check "get-file-icon: .py returns icon" $py_icon_ok)
$output = $output + $result
if $py_icon_ok { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

let dir_icon_ok = ($dir_icon | str length) > 0
let result = (check "get-file-icon: dir returns icon" $dir_icon_ok)
$output = $output + $result
if $dir_icon_ok { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

$output = $output + "\n"

# =============================================
# Test 5: color lookup
# =============================================
$output = $output + "--- Test 5: color lookup ---\n"

let py_color = (get-file-color "script.py" "file")
let dir_color = (get-file-color "subdir" "dir")
let md_color = (get-file-color "readme.md" "file")
let link_color = (get-file-color "link_to_readme" "symlink")

$output = $output + $"  .py color: '($py_color)'\n"
$output = $output + $"  dir color: '($dir_color)'\n"
$output = $output + $"  .md color: '($md_color)'\n"
$output = $output + $"  symlink color: '($link_color)'\n\n"

let py_color_ok = ($py_color | str length) > 0
let result = (check "get-file-color: .py returns ANSI code" $py_color_ok)
$output = $output + $result
if $py_color_ok { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

let dir_color_ok = ($dir_color | str length) > 0
let result = (check "get-file-color: dir returns ANSI code" $dir_color_ok)
$output = $output + $result
if $dir_color_ok { $pass_count = $pass_count + 1 } else { $fail_count = $fail_count + 1 }

$output = $output + "\n"

# =============================================
# Summary
# =============================================
$output = $output + $"=== Summary: ($pass_count) passed, ($fail_count) failed ===\n"

$output | save -f $results_file
print $output

# Cleanup
rm -rf $test_dir

if $fail_count > 0 {
    exit 1
}
