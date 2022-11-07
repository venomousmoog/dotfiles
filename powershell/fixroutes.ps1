# Ensure WSL has been run as least once to start the WSL interface:
wsl pwd

# Gather the interfaces and current WSL network IP:
$wsl = Get-NetIPInterface -InterfaceAlias "vEthernet (WSL)" -AddressFamily IPv4
$vpn = Get-NetIPInterface -InterfaceAlias "Ethernet 2" -AddressFamily IPv4
$ip = Get-NetIPAddress -InterfaceAlias "vEthernet (WSL)" -AddressFamily IPv4
$networkIp = "$($ip.IPAddress -replace "\.\d+$", ".0")"

# Delete the associated VPN route
Write-Output "Deleting route for $($networkIp) with index $($vpn.ifIndex)..."
route delete $networkIp IF $vpn.ifIndex
Start-Sleep 1
route delete $networkIp IF $vpn.ifIndex