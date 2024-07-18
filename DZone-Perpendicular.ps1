<# 
Script to duplicate Willow zones with Line Mowing at perpendicular angles.

The script saves the "old" application configuration as Willow-Application-Config-<datetime>-Backup.json
If something goes wrong with the new zones the content of this file can be used via
Configurations - Application - Get Config - copy the file content - Set Config.
A reboot is required.

The new configuration is also saved in a file named Willow-Application-Config-<datetime>-New.json
#>

# Willow's IP address on your local WiFi network
$WillowIP = '192.168.1.160'

# The 1st angle for Line Mowing, the angle in the duplicated zone will be perpendicular, i.e. + 90 degrees
$angle = 45

# Function to make the HTTP calls to Willow
function Invoke-Willow {
    param(
        [String]$Method,
        [String]$Command,
        [String]$IP,
        [PSObject]$Body,
        [Switch]$DontWait = $false
    )

    $sWeb = @{
        Uri                = "http://$($IP):8080/$($Command)"
        Method             = $Method
        ContentType        = 'application/json'
        UseBasicParsing    = $true
        SkipHttpErrorCheck = $true
    }
    if ($Body) {
        $sWeb.Add('Body', $Body)
    }
    try {
        if ($DontWait) {
            Start-Job -ScriptBlock { 
                param($splat)
                Invoke-WebRequest @splat } -ArgumentList $sWeb | Out-Null
        } else {
            $reply = Invoke-WebRequest @sWeb
            Write-Verbose "Invoke-WebRequest Status $($reply.StatusCode) - $($reply.StatusDescription)"

            if ($reply.StatusCode -eq 200) {
                if ($reply.Content) {
                    $reply.Content
                }
            } else {
                throw "Call $($sWeb.Uri) to Willow failed with Status $($reply.StatusCode)"
            }
        }
    } catch {
        $error[0]
        throw "Call to Willow encountered an exception"
    }
}

$date = Get-Date -Format 'ddMMyyyy-HHmmss'

$zoneProp1 = [PSCustomObject]@{
    lineMowActivity = [PSCustomObject]@{
        lineDirection = $angle
    }
    mowingPlanner   = [PSCustomObject]@{
        mowingPattern = 'LINES'
    }
}
$zoneProp2 = [PSCustomObject]@{
    lineMowActivity = [PSCustomObject]@{
        lineDirection = $angle + 90
    }
    mowingPlanner   = [PSCustomObject]@{
        mowingPattern = 'LINES'
    }
}

# Get the current Application Configuration
$reply = Invoke-Willow -IP $WillowIP -Method 'Get' -Command 'api/configuration/application'
$configFile = ".\Willow-Application-Config-$($date)-Backup.json"
$reply | Out-File -FilePath $configFile
$appConfig = $reply | ConvertFrom-Json

# Check if the script already ran aginst this configuration
if ($appConfig.zones.features.properties.description -match "code to duplicate a zone") {
    throw "Zone duplication appears to already have run. Restore an older Application config first."
}

# Create the new Application Configuration
$newAppConfig = $appConfig | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$newAppConfig.zones.features = @()
$appConfig.zones.features | ForEach-Object -Process {
    # Only duplicate Grass Zones
    if ($_.id -match "^GRASSZONE_") {
        $old = $_ | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $old.properties | Add-Member -MemberType NoteProperty -Name 'zoneProperties' -Value $zoneProp1 -Force
        $newAppConfig.zones.features += $old

        $new = $_ | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $new.Id = "GRASSZONE_$(New-Guid)"
        $new.properties.description = 'GRASSZONE created by code to duplicate a zone.'
        $new.properties | Add-Member -MemberType NoteProperty -Name 'zoneProperties' -Value $zoneProp2 -Force
        $newAppConfig.zones.features += $new
        # Copy all other zones
    } else {
        $newAppConfig.zones.features += $_
    }
}

# Save the new Application Configuration
$newConfigFile = ".\Willow-Application-Config-$($date)-New.json"
$newAppConfig | ConvertTo-Json -Depth 99 | Out-File -FilePath $newConfigFile

# Activate the new Application Configuration
Invoke-Willow -IP $WillowIP -Method 'Post' -Command 'api/configuration/application' -Body ($newAppConfig | ConvertTo-Json -Depth 99)
Invoke-Willow -IP $WillowIP -Method 'Put' -Command 'api/configuration/application'

# Reboot Willow
Invoke-Willow -IP $WillowIP -Method 'Put' -Command 'api/maintenance/reboot' -DontWait
