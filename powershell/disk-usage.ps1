function Format-Bytes($num)
{
    $suffix = "bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"
    $index = 0
    while ($num -gt 1kb)
    {
        $num = $num / 1kb
        $index++
    }

    if ($index -eq 0) {
        return "{0:N0} {1}" -f $num, $suffix[$index]
    } else {
        return "{0:N1} {1}" -f $num, $suffix[$index]
    }
}

class DiskSpaceValue : System.IComparable
{
    [int64]$Value
    [string]$Friendly

    DiskSpaceValue($value) {
        $this.Value = [int64]$value;
        $this.Friendly = Format-Bytes($this.Value)
    }

    [int] CompareTo([object] $obj)
    {
        if ($null -eq $obj)
        {
            return 1;
        }

        if ($obj -isnot [DiskSpaceValue])
        {
            Write-Host ($obj.ToString() + "not comparable to " + $this.ToString())
            Throw ($obj.ToString() + "not comparable to " + $this.ToString())
        }
        Write-Host ("comparing " + $this.Friendly + " to " + $obj.Friendly)

        $result = switch ($this.Value - $obj.Value)
        {
            { $_ -gt 0 } { 1 }
            { $_ -lt 0 } { -1 }
            default { 0 }
        }
        return $result
    }

    [string]ToString()
    {
        return $this.Friendly
    }
}

function Get-DiskUsedSummary($dir = ".")
{
    get-childitem $dir |
        ForEach-Object {
            $f = $_ ;
            get-childitem -r $_.FullName |
                measure-object -property length -sum |
                Select-Object @{Name = "Name"; Expression = { $f } },
                              @{Name = "Sum"; Expression = { [DiskSpaceValue]::new($_.Sum) } }
        }
}
Set-Alias -Name du -Value Get-DiskUsedSummary -Option AllScope

function Get-DiskFreeSummary
{
    Get-Volume |
        ForEach-Object  {
            [PSCustomObject]@{
                "Drive" = $_.DriveLetter;
                "Total Size" = [DiskSpaceValue]::new($_.Size);
                "Space Remaining" = [DiskSpaceValue]::new($_.SizeRemaining);
            }
        } |
        Format-Table -AutoSize
}
Set-Alias -Name df -Value Get-DiskFreeSummary -Option AllScope
