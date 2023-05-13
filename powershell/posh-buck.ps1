$bpath = Join-Path "$PSScriptRoot" "../b"
$bfile = Join-Path "$bpath" "b.py"

function bb { python3 $bfile build @args }
function br { python3 $bfile run @args }
function bt { python3 $bfile test @args }
function bq { python3 $bfile query @args }
function bg { python3 $bfile targets @args }
function bd { python3 $bfile debug @args }
function bbq { python3 $bfile buildq @args }
function brq { python3 $bfile runq @args }
function btq { python3 $bfile testq @args }
function bdq { python3 $bfile debugq @args }
function bgq { python3 $bfile targetsq @args }
function b { python3 $bfile @args }
function udpb { python3 $bpath\update_compilation_database.py @args }
function tidy { python3 $bpath\run_clang_tidy.py @args }

function bmode(
    [string]$Mode,
    [switch]$Clear,
    [switch]$None,
    [switch]$Auto)
{
    if ($Clear) {
        if (Test-Path env:BUCK_MODE) {
            Remove-Item env:BUCK_MODE
        }
    }
    elseif ($None) {
        $env:BUCK_MODE = "@"
    }
    elseif ($Mode) {
        Write-Host "setting new mode"
        $env:BUCK_MODE = "@" + $Mode
    }
    elseif ($Auto) {
        Write-Host "setting auto mode"
        $env:BUCK_MODE = "@" + "auto"
    }

    # print current ode
    Push-Location $bpath
    python3 -c "from b import get_default_mode; print(f'{get_default_mode()}')"
    Pop-Location
}
