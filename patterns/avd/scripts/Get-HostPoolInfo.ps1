[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$CloudEnvironment,
    [Parameter(Mandatory)]
    [string]$SubscriptionId
)

# Section 1 - Connect and set subscription context
Connect-AzAccount -Identity -Environment $CloudEnvironment | Out-Null
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

# Section 2 - Get all Pooled host pools
$AVDHostPools = Get-AzWvdHostPool | Where-Object HostPoolType -EQ "Pooled"

$Output = [System.Collections.Generic.List[string]]::new()

foreach ($AVDHostPool in $AVDHostPools) {

    # Section 3 - Basic host pool properties
    $HPName           = $AVDHostPool.Name
    $HPResGroup       = ($AVDHostPool.Id -split '/')[4]
    $HPType           = $AVDHostPool.HostPoolType
    $HPMaxSessionLimit = $AVDHostPool.MaxSessionLimit
    $HP_ResID         = $AVDHostPool.Id

    # Section 4 - Session hosts (single call, reused for all derived counts)
    $HPSessionHosts                         = Get-AzWvdSessionHost -HostPoolName $HPName -ResourceGroupName $HPResGroup
    $HPNumSessionHosts                      = $HPSessionHosts.Count
    $HPNumHostsAllowingSessions             = ($HPSessionHosts | Where-Object { $_.AllowNewSession }).Count
    $HPNumHostsAvailable                    = ($HPSessionHosts | Where-Object { $_.Status -eq "Available" }).Count
    $HPNumHostsAvailableAndAllowingSessions = ($HPSessionHosts | Where-Object { $_.Status -eq "Available" -and $_.AllowNewSession }).Count

    # Section 5 - User sessions
    $HPUsrSessions    = Get-AzWvdUserSession -HostPoolName $HPName -ResourceGroupName $HPResGroup
    $HPUsrSession     = $HPUsrSessions.Count
    $HPUsrDisconnected = ($HPUsrSessions | Where-Object { $_.SessionState -eq "Disconnected" -and $_.UserPrincipalName -ne $null }).Count
    $HPUsrActive      = ($HPUsrSessions | Where-Object { $_.SessionState -eq "Active" -and $_.UserPrincipalName -ne $null }).Count

    # Section 6 - Capacity calculations
    $TotalCapacity    = $HPMaxSessionLimit * $HPNumHostsAvailableAndAllowingSessions

    # Clamp to 0 to avoid negative values when pool is overloaded
    $HPSessionsAvail  = [Math]::Max(0, $TotalCapacity - $HPUsrSession)

    # Guard against division by zero when no hosts are available and allowing sessions
    if ($HPUsrSession -ne 0 -and $HPNumHostsAvailableAndAllowingSessions -ne 0) {
        $HPLoadPercent = ($HPUsrSession / $TotalCapacity) * 100
    } else {
        $HPLoadPercent = 0
    }

    # Section 7 - Build output row
    $Output.Add(
        $HPName           + "|" +
        $HPResGroup       + "|" +
        $HPType           + "|" +
        $HPMaxSessionLimit + "|" +
        $HPNumSessionHosts + "|" +
        $HPUsrSession     + "|" +
        $HPUsrDisconnected + "|" +
        $HPUsrActive      + "|" +
        $HPSessionsAvail  + "|" +
        $HPLoadPercent    + "|" +
        $HP_ResID
    )
}

Write-Output $Output
