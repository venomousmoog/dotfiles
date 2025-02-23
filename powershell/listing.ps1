# and add format data for our custom "listing" (or ls) support
Update-FormatData -Prepend "$PSScriptRoot/listings.format.ps1xml"

function Format-Listing {
    $a = $false
    $l = $false
    $aa = $false
    $r = $false
    if (($args.Length -gt 0) -and ($args[0].StartsWith('-'))) {
        $a = $args[0].Contains('a')
        $l = $args[0].Contains('l')
        $aa = $args[0].Contains('A')
        $r = $args[0].Contains('R') -or $args[0].Contains('r')
        $rest = $args[1..$args.Length]
    } else {
        $rest = $args
    }


    $extra = @{}
    $format = @{}
    if ($r) {
        $extra += @{Recurse = $true }
        $format = @{View = 'ListingChildren' }
    } else {
        $format = @{View = 'ListingChildrenUngrouped' }
    }
    if ($aa) {
        $extra += @{Attributes = 'Hidden, !Hidden' }
    }
    $files = Get-ChildItem @extra @rest

    if (-not $a -and -not $aa) {
        $files = $files | Where-Object { -not $_.Name.StartsWith('.') }
    }

    if ($l) {
        $files | Format-Table @format
    } else {
        $files | Format-Wide -AutoSize @format
    }
}

function Format-Location {
    Get-Location @args | Format-Table -HideTableHeaders
}

Set-Alias -Name ls -Value Format-Listing -Option AllScope
Set-Alias -Name pwd -Value Format-Location  -Option AllScope
