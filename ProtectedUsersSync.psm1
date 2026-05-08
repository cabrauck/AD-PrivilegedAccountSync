Set-StrictMode -Version Latest

$script:DefaultPrivilegedGroupIdentities = @(
    'Domain Admins',
    'Enterprise Admins',
    'Schema Admins',
    'Administrators',
    'Backup Operators',
    'Server Operators',
    'Account Operators'
)

function Resolve-AbsolutePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Get-DisplayName {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Record
    )

    if ($Record.SamAccountName) {
        return [string]$Record.SamAccountName
    }

    return [string]$Record.Sid
}

function Get-SidValue {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$InputObject
    )

    $sidPropertyNames = @('SID', 'Sid', 'ObjectSid')

    foreach ($propertyName in $sidPropertyNames) {
        if ($InputObject.PSObject.Properties[$propertyName]) {
            $sidValue = $InputObject.$propertyName

            if ($sidValue) {
                return [string]$sidValue
            }
        }
    }

    return $null
}

function New-ProtectedUserRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Sid,
        [string]$SamAccountName,
        [string]$DistinguishedName,
        [string[]]$Sources = @()
    )

    return [pscustomobject]@{
        Sid               = $Sid
        SamAccountName    = $SamAccountName
        DistinguishedName = $DistinguishedName
        Sources           = @($Sources | Where-Object { $_ } | Select-Object -Unique)
    }
}

function ConvertTo-ProtectedUserRecord {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$AdObject,
        [string[]]$Sources = @()
    )

    $sidValue = Get-SidValue -InputObject $AdObject

    if (-not $sidValue) {
        throw 'Unable to resolve SID for the supplied Active Directory object.'
    }

    $samAccountName = $null
    if ($AdObject.PSObject.Properties['SamAccountName']) {
        $samAccountName = [string]$AdObject.SamAccountName
    }

    $distinguishedName = $null
    if ($AdObject.PSObject.Properties['DistinguishedName']) {
        $distinguishedName = [string]$AdObject.DistinguishedName
    }

    return New-ProtectedUserRecord -Sid $sidValue -SamAccountName $samAccountName -DistinguishedName $distinguishedName -Sources $Sources
}

function Add-ProtectedUserRecordToMap {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Map,
        [Parameter(Mandatory = $true)]
        [psobject]$Record
    )

    if (-not $Map.ContainsKey($Record.Sid)) {
        $Map[$Record.Sid] = New-ProtectedUserRecord `
            -Sid $Record.Sid `
            -SamAccountName $Record.SamAccountName `
            -DistinguishedName $Record.DistinguishedName `
            -Sources $Record.Sources
        return
    }

    $existingRecord = $Map[$Record.Sid]

    if (-not $existingRecord.SamAccountName -and $Record.SamAccountName) {
        $existingRecord.SamAccountName = $Record.SamAccountName
    }

    if (-not $existingRecord.DistinguishedName -and $Record.DistinguishedName) {
        $existingRecord.DistinguishedName = $Record.DistinguishedName
    }

    $existingRecord.Sources = @(
        @($existingRecord.Sources) + @($Record.Sources) |
            Where-Object { $_ } |
            Select-Object -Unique
    )
}

function ConvertTo-ProtectedUserMap {
    param(
        [psobject[]]$Records = @()
    )

    $map = @{}

    foreach ($record in @($Records | Where-Object { $_ })) {
        Add-ProtectedUserRecordToMap -Map $map -Record $record
    }

    return $map
}

function Get-SortedProtectedUserRecords {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Map
    )

    return @(
        $Map.Values |
            Sort-Object `
                @{ Expression = { if ($_.SamAccountName) { $_.SamAccountName.ToLowerInvariant() } else { $_.Sid } } }, `
                @{ Expression = { $_.Sid } }
    )
}

function Get-MergedArrayValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [hashtable]$BoundParameters,
        [Parameter(Mandatory = $true)]
        [hashtable]$ConfigurationData,
        $CurrentValue
    )

    if ($BoundParameters.ContainsKey($Name)) {
        return @($CurrentValue)
    }

    if ($ConfigurationData.ContainsKey($Name)) {
        return @($ConfigurationData[$Name])
    }

    return @($CurrentValue)
}

function Get-MergedScalarValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [hashtable]$BoundParameters,
        [Parameter(Mandatory = $true)]
        [hashtable]$ConfigurationData,
        $CurrentValue
    )

    if ($BoundParameters.ContainsKey($Name)) {
        return $CurrentValue
    }

    if ($ConfigurationData.ContainsKey($Name)) {
        return $ConfigurationData[$Name]
    }

    return $CurrentValue
}

function Resolve-ProtectedUsersSyncConfiguration {
    [CmdletBinding()]
    param(
        [string]$ProtectedUsersGroupIdentity = 'Protected Users',
        [string[]]$PrivilegedGroupIdentities = $script:DefaultPrivilegedGroupIdentities,
        [switch]$IncludeAdminCount,
        [string[]]$ExplicitIncludeUsers = @(),
        [string[]]$ExplicitExcludeUsers = @(),
        [ValidateSet('AddOnly', 'Authoritative')]
        [string]$RemovalMode = 'AddOnly',
        [string]$ConfigPath,
        [string]$LogDirectory = '.\Logs',
        [string]$LogFileName = 'ProtectedUsersSync.log'
    )

    $boundParameters = $PSBoundParameters
    $configurationData = @{}
    $resolvedConfigPath = $null

    if ($boundParameters.ContainsKey('ConfigPath') -and $ConfigPath) {
        $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath -ErrorAction Stop).ProviderPath
        $configurationData = Import-PowerShellDataFile -Path $resolvedConfigPath
    }

    $resolvedRemovalMode = [string](Get-MergedScalarValue -Name 'RemovalMode' -BoundParameters $boundParameters -ConfigurationData $configurationData -CurrentValue $RemovalMode)
    if ($resolvedRemovalMode -notin @('AddOnly', 'Authoritative')) {
        throw "Unsupported RemovalMode '$resolvedRemovalMode'. Valid values are AddOnly and Authoritative."
    }

    $resolvedLogFileName = [string](Get-MergedScalarValue -Name 'LogFileName' -BoundParameters $boundParameters -ConfigurationData $configurationData -CurrentValue $LogFileName)
    if ([string]::IsNullOrWhiteSpace($resolvedLogFileName)) {
        throw 'LogFileName must not be empty.'
    }

    if ([System.IO.Path]::GetFileName($resolvedLogFileName) -ne $resolvedLogFileName) {
        throw 'LogFileName must be a file name without directory components.'
    }

    return [pscustomobject]@{
        ProtectedUsersGroupIdentity = [string](Get-MergedScalarValue -Name 'ProtectedUsersGroupIdentity' -BoundParameters $boundParameters -ConfigurationData $configurationData -CurrentValue $ProtectedUsersGroupIdentity)
        PrivilegedGroupIdentities   = @(
            Get-MergedArrayValue -Name 'PrivilegedGroupIdentities' -BoundParameters $boundParameters -ConfigurationData $configurationData -CurrentValue $PrivilegedGroupIdentities |
                Where-Object { $_ }
        )
        IncludeAdminCount           = [bool](Get-MergedScalarValue -Name 'IncludeAdminCount' -BoundParameters $boundParameters -ConfigurationData $configurationData -CurrentValue ([bool]$IncludeAdminCount))
        ExplicitIncludeUsers        = @(
            Get-MergedArrayValue -Name 'ExplicitIncludeUsers' -BoundParameters $boundParameters -ConfigurationData $configurationData -CurrentValue $ExplicitIncludeUsers |
                Where-Object { $_ }
        )
        ExplicitExcludeUsers        = @(
            Get-MergedArrayValue -Name 'ExplicitExcludeUsers' -BoundParameters $boundParameters -ConfigurationData $configurationData -CurrentValue $ExplicitExcludeUsers |
                Where-Object { $_ }
        )
        RemovalMode                 = $resolvedRemovalMode
        ConfigPath                  = $resolvedConfigPath
        LogDirectory                = Resolve-AbsolutePath -Path ([string](Get-MergedScalarValue -Name 'LogDirectory' -BoundParameters $boundParameters -ConfigurationData $configurationData -CurrentValue $LogDirectory))
        LogFileName                 = $resolvedLogFileName
    }
}

function Get-ArchiveLogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [Parameter(Mandatory = $true)]
        [string]$LogFileName
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($LogFileName)
    $extension = [System.IO.Path]::GetExtension($LogFileName)
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $archivePath = Join-Path -Path $Directory -ChildPath ('{0}_{1}{2}' -f $baseName, $timestamp, $extension)
    $suffix = 1

    while (Test-Path -LiteralPath $archivePath) {
        $archivePath = Join-Path -Path $Directory -ChildPath ('{0}_{1}-{2}{3}' -f $baseName, $timestamp, $suffix, $extension)
        $suffix++
    }

    return $archivePath
}

function Initialize-ProtectedUsersLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogDirectory,
        [Parameter(Mandatory = $true)]
        [string]$LogFileName
    )

    $null = New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop
    $logPath = Join-Path -Path $LogDirectory -ChildPath $LogFileName

    if (Test-Path -LiteralPath $logPath) {
        $archivePath = Get-ArchiveLogPath -Directory $LogDirectory -LogFileName $LogFileName
        Move-Item -LiteralPath $logPath -Destination $archivePath -Force -ErrorAction Stop
    }

    $null = New-Item -Path $logPath -ItemType File -Force -ErrorAction Stop
    return $logPath
}

function Write-ProtectedUsersLogMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogPath -Value ('{0}`t[{1}] {2}' -f $timestamp, $Level, $Message) -Encoding UTF8

    switch ($Level) {
        'INFO' {
            Write-Verbose $Message
        }
        'WARN' {
            Write-Warning $Message
        }
        'ERROR' {
            Write-Error -Message $Message -ErrorAction Continue
        }
    }
}

function Resolve-ADUsersByIdentity {
    param(
        [string[]]$Identities = @(),
        [Parameter(Mandatory = $true)]
        [string]$SourceName
    )

    $records = @()

    foreach ($identity in @($Identities | Where-Object { $_ })) {
        $user = Get-ADUser -Identity $identity -Properties ObjectSid, SamAccountName, DistinguishedName -ErrorAction Stop
        $records += ConvertTo-ProtectedUserRecord -AdObject $user -Sources @($SourceName)
    }

    return @($records)
}

function Get-PrivilegedGroupMembers {
    param(
        [string[]]$GroupIdentities = @()
    )

    $records = @()

    foreach ($groupIdentity in @($GroupIdentities | Where-Object { $_ })) {
        $groupMembers = Get-ADGroupMember -Identity $groupIdentity -Recursive -ErrorAction Stop |
            Where-Object { $_.ObjectClass -eq 'user' }

        foreach ($groupMember in $groupMembers) {
            $records += ConvertTo-ProtectedUserRecord -AdObject $groupMember -Sources @("PrivilegedGroup:$groupIdentity")
        }
    }

    return @($records)
}

function Get-AdminCountMembers {
    $records = @()
    $users = Get-ADUser -LDAPFilter '(adminCount=1)' -Properties ObjectSid, SamAccountName, DistinguishedName -ErrorAction Stop

    foreach ($user in $users) {
        $records += ConvertTo-ProtectedUserRecord -AdObject $user -Sources @('AdminCount')
    }

    return @($records)
}

function Get-CurrentProtectedUsersMembers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProtectedUsersGroupIdentity
    )

    $records = @()
    $groupMembers = Get-ADGroupMember -Identity $ProtectedUsersGroupIdentity -ErrorAction Stop |
        Where-Object { $_.ObjectClass -eq 'user' }

    foreach ($groupMember in $groupMembers) {
        $records += ConvertTo-ProtectedUserRecord -AdObject $groupMember -Sources @('CurrentMembership')
    }

    return @($records)
}

function Get-DesiredProtectedUsers {
    [CmdletBinding()]
    param(
        [psobject[]]$PrivilegedGroupMembers = @(),
        [psobject[]]$AdminCountMembers = @(),
        [psobject[]]$ExplicitIncludeMembers = @(),
        [psobject[]]$ExplicitExcludeMembers = @(),
        [switch]$IncludeAdminCount
    )

    $desiredMap = @{}

    foreach ($record in @($PrivilegedGroupMembers | Where-Object { $_ })) {
        Add-ProtectedUserRecordToMap -Map $desiredMap -Record $record
    }

    if ($IncludeAdminCount) {
        foreach ($record in @($AdminCountMembers | Where-Object { $_ })) {
            Add-ProtectedUserRecordToMap -Map $desiredMap -Record $record
        }
    }

    foreach ($record in @($ExplicitIncludeMembers | Where-Object { $_ })) {
        Add-ProtectedUserRecordToMap -Map $desiredMap -Record $record
    }

    $excludeMap = ConvertTo-ProtectedUserMap -Records $ExplicitExcludeMembers

    foreach ($sid in @($excludeMap.Keys)) {
        if ($desiredMap.ContainsKey($sid)) {
            $desiredMap.Remove($sid)
        }
    }

    return [pscustomobject]@{
        DesiredMembers = Get-SortedProtectedUserRecords -Map $desiredMap
        ExcludedUsers  = Get-SortedProtectedUserRecords -Map $excludeMap
    }
}

function Compare-ProtectedUsersMembership {
    [CmdletBinding()]
    param(
        [psobject[]]$CurrentMembers = @(),
        [psobject[]]$DesiredMembers = @(),
        [ValidateSet('AddOnly', 'Authoritative')]
        [string]$RemovalMode = 'AddOnly'
    )

    $currentMap = ConvertTo-ProtectedUserMap -Records $CurrentMembers
    $desiredMap = ConvertTo-ProtectedUserMap -Records $DesiredMembers
    $toAddMap = @{}
    $toRemoveMap = @{}
    $skippedMap = @{}

    foreach ($sid in @($desiredMap.Keys)) {
        if ($currentMap.ContainsKey($sid)) {
            Add-ProtectedUserRecordToMap -Map $skippedMap -Record $desiredMap[$sid]
            continue
        }

        Add-ProtectedUserRecordToMap -Map $toAddMap -Record $desiredMap[$sid]
    }

    if ($RemovalMode -eq 'Authoritative') {
        foreach ($sid in @($currentMap.Keys)) {
            if (-not $desiredMap.ContainsKey($sid)) {
                Add-ProtectedUserRecordToMap -Map $toRemoveMap -Record $currentMap[$sid]
            }
        }
    }

    return [pscustomobject]@{
        ToAdd                = Get-SortedProtectedUserRecords -Map $toAddMap
        ToRemove             = Get-SortedProtectedUserRecords -Map $toRemoveMap
        SkippedExistingUsers = Get-SortedProtectedUserRecords -Map $skippedMap
    }
}

function Invoke-ProtectedUsersMembershipChanges {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Comparison,
        [Parameter(Mandatory = $true)]
        [psobject]$Configuration,
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]$PSCmdlet
    )

    $addedUsers = @()
    $removedUsers = @()
    $failedActions = @()

    foreach ($record in @($Comparison.ToAdd)) {
        $displayName = Get-DisplayName -Record $record
        Write-ProtectedUsersLogMessage -LogPath $LogPath -Message "Planned add: $displayName"

        if ($PSCmdlet.ShouldProcess($displayName, "Add to '$($Configuration.ProtectedUsersGroupIdentity)'")) {
            try {
                Add-ADGroupMember -Identity $Configuration.ProtectedUsersGroupIdentity -Members $record.DistinguishedName -ErrorAction Stop
                $addedUsers += $record
                Write-ProtectedUsersLogMessage -LogPath $LogPath -Message "Added $displayName to $($Configuration.ProtectedUsersGroupIdentity)"
            } catch {
                $failure = [pscustomobject]@{
                    Action  = 'Add'
                    User    = $displayName
                    Message = $_.Exception.Message
                }
                $failedActions += $failure
                Write-ProtectedUsersLogMessage -LogPath $LogPath -Level 'ERROR' -Message "Failed to add ${displayName}: $($_.Exception.Message)"
            }
        }
    }

    foreach ($record in @($Comparison.ToRemove)) {
        $displayName = Get-DisplayName -Record $record
        Write-ProtectedUsersLogMessage -LogPath $LogPath -Message "Planned remove: $displayName"

        if ($PSCmdlet.ShouldProcess($displayName, "Remove from '$($Configuration.ProtectedUsersGroupIdentity)'")) {
            try {
                Remove-ADGroupMember -Identity $Configuration.ProtectedUsersGroupIdentity -Members $record.DistinguishedName -Confirm:$false -ErrorAction Stop
                $removedUsers += $record
                Write-ProtectedUsersLogMessage -LogPath $LogPath -Message "Removed $displayName from $($Configuration.ProtectedUsersGroupIdentity)"
            } catch {
                $failure = [pscustomobject]@{
                    Action  = 'Remove'
                    User    = $displayName
                    Message = $_.Exception.Message
                }
                $failedActions += $failure
                Write-ProtectedUsersLogMessage -LogPath $LogPath -Level 'ERROR' -Message "Failed to remove ${displayName}: $($_.Exception.Message)"
            }
        }
    }

    return [pscustomobject]@{
        AddedUsers    = @($addedUsers)
        RemovedUsers  = @($removedUsers)
        FailedActions = @($failedActions)
    }
}

function Invoke-ProtectedUsersSync {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [string]$ProtectedUsersGroupIdentity = 'Protected Users',
        [string[]]$PrivilegedGroupIdentities = $script:DefaultPrivilegedGroupIdentities,
        [switch]$IncludeAdminCount,
        [string[]]$ExplicitIncludeUsers = @(),
        [string[]]$ExplicitExcludeUsers = @(),
        [ValidateSet('AddOnly', 'Authoritative')]
        [string]$RemovalMode = 'AddOnly',
        [string]$ConfigPath,
        [string]$LogDirectory = '.\Logs',
        [string]$LogFileName = 'ProtectedUsersSync.log'
    )

    Import-Module ActiveDirectory -ErrorAction Stop

    $configurationParameters = @{}
    foreach ($parameterName in @(
            'ProtectedUsersGroupIdentity',
            'PrivilegedGroupIdentities',
            'IncludeAdminCount',
            'ExplicitIncludeUsers',
            'ExplicitExcludeUsers',
            'RemovalMode',
            'ConfigPath',
            'LogDirectory',
            'LogFileName'
        )) {
        if ($PSBoundParameters.ContainsKey($parameterName)) {
            $configurationParameters[$parameterName] = $PSBoundParameters[$parameterName]
        }
    }

    $configuration = Resolve-ProtectedUsersSyncConfiguration @configurationParameters
    $logPath = Initialize-ProtectedUsersLog -LogDirectory $configuration.LogDirectory -LogFileName $configuration.LogFileName

    Write-ProtectedUsersLogMessage -LogPath $logPath -Message "Starting Protected Users sync in mode '$($configuration.RemovalMode)'."
    Write-ProtectedUsersLogMessage -LogPath $logPath -Message "Protected Users group: $($configuration.ProtectedUsersGroupIdentity)"
    Write-ProtectedUsersLogMessage -LogPath $logPath -Message "Privileged groups: $($configuration.PrivilegedGroupIdentities -join ', ')"
    Write-ProtectedUsersLogMessage -LogPath $logPath -Message "IncludeAdminCount: $($configuration.IncludeAdminCount)"

    if ($configuration.ConfigPath) {
        Write-ProtectedUsersLogMessage -LogPath $logPath -Message "Loaded configuration from $($configuration.ConfigPath)"
    }

    $currentMembers = Get-CurrentProtectedUsersMembers -ProtectedUsersGroupIdentity $configuration.ProtectedUsersGroupIdentity
    $privilegedGroupMembers = Get-PrivilegedGroupMembers -GroupIdentities $configuration.PrivilegedGroupIdentities
    $adminCountMembers = @()

    if ($configuration.IncludeAdminCount) {
        $adminCountMembers = Get-AdminCountMembers
    }

    $explicitIncludeMembers = Resolve-ADUsersByIdentity -Identities $configuration.ExplicitIncludeUsers -SourceName 'ExplicitInclude'
    $explicitExcludeMembers = Resolve-ADUsersByIdentity -Identities $configuration.ExplicitExcludeUsers -SourceName 'ExplicitExclude'

    $desiredState = Get-DesiredProtectedUsers `
        -PrivilegedGroupMembers $privilegedGroupMembers `
        -AdminCountMembers $adminCountMembers `
        -ExplicitIncludeMembers $explicitIncludeMembers `
        -ExplicitExcludeMembers $explicitExcludeMembers `
        -IncludeAdminCount:$configuration.IncludeAdminCount

    $comparison = Compare-ProtectedUsersMembership `
        -CurrentMembers $currentMembers `
        -DesiredMembers $desiredState.DesiredMembers `
        -RemovalMode $configuration.RemovalMode

    Write-ProtectedUsersLogMessage -LogPath $logPath -Message "Current direct members: $(@($currentMembers).Count)"
    Write-ProtectedUsersLogMessage -LogPath $logPath -Message "Desired members: $(@($desiredState.DesiredMembers).Count)"
    Write-ProtectedUsersLogMessage -LogPath $logPath -Message "Planned adds: $(@($comparison.ToAdd).Count)"
    Write-ProtectedUsersLogMessage -LogPath $logPath -Message "Planned removals: $(@($comparison.ToRemove).Count)"

    $changeResult = Invoke-ProtectedUsersMembershipChanges `
        -Comparison $comparison `
        -Configuration $configuration `
        -LogPath $logPath `
        -PSCmdlet $PSCmdlet

    $summary = [pscustomobject]@{
        Mode                 = $configuration.RemovalMode
        IncludeAdminCount    = $configuration.IncludeAdminCount
        CurrentCount         = @($currentMembers).Count
        DesiredCount         = @($desiredState.DesiredMembers).Count
        PlannedAddUsers      = @($comparison.ToAdd | ForEach-Object { Get-DisplayName -Record $_ })
        PlannedRemoveUsers   = @($comparison.ToRemove | ForEach-Object { Get-DisplayName -Record $_ })
        AddedUsers           = @($changeResult.AddedUsers | ForEach-Object { Get-DisplayName -Record $_ })
        RemovedUsers         = @($changeResult.RemovedUsers | ForEach-Object { Get-DisplayName -Record $_ })
        SkippedExistingUsers = @($comparison.SkippedExistingUsers | ForEach-Object { Get-DisplayName -Record $_ })
        ExcludedUsers        = @($desiredState.ExcludedUsers | ForEach-Object { Get-DisplayName -Record $_ })
        FailedActions        = @($changeResult.FailedActions)
        Succeeded            = (@($changeResult.FailedActions).Count -eq 0)
    }

    Write-ProtectedUsersLogMessage -LogPath $logPath -Message (
        'Summary: desired={0}, plannedAdds={1}, plannedRemovals={2}, added={3}, removed={4}, failedActions={5}, succeeded={6}' -f
        $summary.DesiredCount,
        @($summary.PlannedAddUsers).Count,
        @($summary.PlannedRemoveUsers).Count,
        @($summary.AddedUsers).Count,
        @($summary.RemovedUsers).Count,
        @($summary.FailedActions).Count,
        $summary.Succeeded
    )

    return $summary
}

Export-ModuleMember -Function Compare-ProtectedUsersMembership, Get-DesiredProtectedUsers, Invoke-ProtectedUsersSync, Resolve-ProtectedUsersSyncConfiguration
