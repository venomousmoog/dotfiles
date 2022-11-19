$iterations = 25
$p = 0
1..$iterations | ForEach-Object {
    Write-Progress -Id 1 -Activity 'pwsh' -PercentComplete ($_*100/$iterations)
    $p += (Measure-Command {
        pwsh -noprofile -command 1
    }).TotalMilliseconds 
}
Write-Progress -id 1 -Activity 'profile' -Completed
$p = $p/$iterations
"baseline: $p milliseconds"

$a = 0
1..$iterations | ForEach-Object {
    Write-Progress -Id 1 -Activity 'profile' -PercentComplete ($_*100/$iterations)
    $a += (Measure-Command {
        pwsh -command 1
    }).TotalMilliseconds
}
Write-Progress -id 1 -activity 'profile' -Completed

"profile: $($a/$iterations - $p) milliseconds"
