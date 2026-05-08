Set-StrictMode -Version Latest

function global:Get-ADGroupMember {
    param(
        [string]$Identity,
        [switch]$Recursive,
        $ErrorAction
    )

    throw 'Get-ADGroupMember stub should be mocked.'
}

function global:Get-ADUser {
    param(
        [string]$Identity,
        [string]$LDAPFilter,
        [string[]]$Properties,
        $ErrorAction
    )

    throw 'Get-ADUser stub should be mocked.'
}

function global:Add-ADGroupMember {
    param(
        [string]$Identity,
        [string[]]$Members,
        $ErrorAction
    )

    throw 'Add-ADGroupMember stub should be mocked.'
}

function global:Remove-ADGroupMember {
    param(
        [string]$Identity,
        [string[]]$Members,
        [switch]$Confirm,
        $ErrorAction
    )

    throw 'Remove-ADGroupMember stub should be mocked.'
}

$modulePath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'ProtectedUsersSync.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop
$script:moduleName = 'ProtectedUsersSync'

function script:New-AdPrincipal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Sid,
        [Parameter(Mandatory = $true)]
        [string]$SamAccountName,
        [Parameter(Mandatory = $true)]
        [string]$DistinguishedName,
        [string]$ObjectClass = 'user'
    )

    [pscustomobject]@{
        SID               = $Sid
        SamAccountName    = $SamAccountName
        DistinguishedName = $DistinguishedName
        ObjectClass       = $ObjectClass
    }
}

function script:New-TestLogDirectory {
    param(
        [string]$Prefix = 'Logs'
    )

    return Join-Path -Path $TestDrive -ChildPath ('{0}-{1}' -f $Prefix, [guid]::NewGuid().ToString('N'))
}

Describe 'Invoke-ProtectedUsersSync' {
    BeforeEach {
        $script:protectedUsersMembers = @(
            New-AdPrincipal -Sid 'S-1-5-21-1' -SamAccountName 'alice' -DistinguishedName 'CN=alice,DC=example,DC=com'
        )
        $script:domainAdminsMembers = @(
            New-AdPrincipal -Sid 'S-1-5-21-1' -SamAccountName 'alice' -DistinguishedName 'CN=alice,DC=example,DC=com'
            New-AdPrincipal -Sid 'S-1-5-21-2' -SamAccountName 'bob' -DistinguishedName 'CN=bob,DC=example,DC=com'
        )
        $script:adminCountMembers = @(
            New-AdPrincipal -Sid 'S-1-5-21-3' -SamAccountName 'charlie' -DistinguishedName 'CN=charlie,DC=example,DC=com'
        )

        Mock Import-Module {} -ModuleName $moduleName

        Mock Get-ADGroupMember {
            param($Identity, [switch]$Recursive)

            if ($Identity -eq 'Protected Users') {
                return $script:protectedUsersMembers
            }

            if ($Identity -eq 'Domain Admins') {
                return $script:domainAdminsMembers
            }

            return @()
        } -ModuleName $moduleName

        Mock Get-ADUser {
            param($Identity, $LDAPFilter, $Properties)

            if ($LDAPFilter -eq '(adminCount=1)') {
                return $script:adminCountMembers
            }

            switch ($Identity) {
                'svc-breakglass' {
                    return New-AdPrincipal -Sid 'S-1-5-21-4' -SamAccountName 'svc-breakglass' -DistinguishedName 'CN=svc-breakglass,DC=example,DC=com'
                }
                'legacy-service' {
                    return New-AdPrincipal -Sid 'S-1-5-21-2' -SamAccountName 'bob' -DistinguishedName 'CN=bob,DC=example,DC=com'
                }
                default {
                    throw "Unexpected identity lookup: $Identity"
                }
            }
        } -ModuleName $moduleName

        Mock Add-ADGroupMember {} -ModuleName $moduleName
        Mock Remove-ADGroupMember {} -ModuleName $moduleName
    }

    It 'adds only missing users in AddOnly mode and does not remove' {
        $logDirectory = New-TestLogDirectory
        $result = Invoke-ProtectedUsersSync `
            -ProtectedUsersGroupIdentity 'Protected Users' `
            -PrivilegedGroupIdentities @('Domain Admins') `
            -RemovalMode AddOnly `
            -LogDirectory $logDirectory `
            -ErrorAction SilentlyContinue 2>$null

        $result.PlannedAddUsers | Should -Be @('bob')
        @($result.PlannedRemoveUsers).Count | Should -Be 0
        $result.AddedUsers | Should -Be @('bob')
        @($result.RemovedUsers).Count | Should -Be 0

        Assert-MockCalled Add-ADGroupMember -Times 1 -Exactly -ModuleName $moduleName
        Assert-MockCalled Remove-ADGroupMember -Times 0 -Exactly -ModuleName $moduleName
    }

    It 'removes users outside the desired set in Authoritative mode' {
        $script:protectedUsersMembers = @(
            New-AdPrincipal -Sid 'S-1-5-21-1' -SamAccountName 'alice' -DistinguishedName 'CN=alice,DC=example,DC=com'
            New-AdPrincipal -Sid 'S-1-5-21-9' -SamAccountName 'zoe' -DistinguishedName 'CN=zoe,DC=example,DC=com'
        )

        $logDirectory = New-TestLogDirectory
        $result = Invoke-ProtectedUsersSync `
            -ProtectedUsersGroupIdentity 'Protected Users' `
            -PrivilegedGroupIdentities @('Domain Admins') `
            -RemovalMode Authoritative `
            -LogDirectory $logDirectory

        $result.PlannedRemoveUsers | Should -Be @('zoe')
        $result.RemovedUsers | Should -Be @('zoe')

        Assert-MockCalled Remove-ADGroupMember -Times 1 -Exactly -ModuleName $moduleName
    }

    It 'does not mutate when run with WhatIf' {
        $logDirectory = New-TestLogDirectory
        $result = Invoke-ProtectedUsersSync `
            -ProtectedUsersGroupIdentity 'Protected Users' `
            -PrivilegedGroupIdentities @('Domain Admins') `
            -RemovalMode AddOnly `
            -LogDirectory $logDirectory `
            -WhatIf

        $result.PlannedAddUsers | Should -Be @('bob')
        @($result.AddedUsers).Count | Should -Be 0

        Assert-MockCalled Add-ADGroupMember -Times 0 -Exactly -ModuleName $moduleName
        Assert-MockCalled Remove-ADGroupMember -Times 0 -Exactly -ModuleName $moduleName
    }

    It 'rotates the previous log and writes a summary line' {
        $logDirectory = New-TestLogDirectory
        $null = New-Item -Path $logDirectory -ItemType Directory -Force
        Set-Content -Path (Join-Path -Path $logDirectory -ChildPath 'ProtectedUsersSync.log') -Value 'old log'

        $result = Invoke-ProtectedUsersSync `
            -ProtectedUsersGroupIdentity 'Protected Users' `
            -PrivilegedGroupIdentities @('Domain Admins') `
            -RemovalMode AddOnly `
            -LogDirectory $logDirectory

        $archivedLogs = Get-ChildItem -Path $logDirectory -Filter 'ProtectedUsersSync_*.log'
        $currentLog = Join-Path -Path $logDirectory -ChildPath 'ProtectedUsersSync.log'

        @($archivedLogs).Count | Should -Be 1
        Get-Content -Path $currentLog -Raw | Should -Match 'Summary: desired='
        $result.Succeeded | Should -BeTrue
    }

    It 'collects mutation failures and reports them in the summary' {
        Mock Add-ADGroupMember {
            throw 'Access denied.'
        } -ModuleName $moduleName

        $logDirectory = New-TestLogDirectory
        $previousErrorActionPreference = $ErrorActionPreference

        try {
            $ErrorActionPreference = 'SilentlyContinue'
            $result = Invoke-ProtectedUsersSync `
                -ProtectedUsersGroupIdentity 'Protected Users' `
                -PrivilegedGroupIdentities @('Domain Admins') `
                -RemovalMode AddOnly `
                -LogDirectory $logDirectory `
                -ErrorAction SilentlyContinue
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        $result.Succeeded | Should -BeFalse
        @($result.FailedActions).Count | Should -Be 1
        $result.FailedActions[0].Action | Should -Be 'Add'
        $result.FailedActions[0].User | Should -Be 'bob'
    }

    It 'honors explicit include and exclude overrides' {
        $logDirectory = New-TestLogDirectory
        $result = Invoke-ProtectedUsersSync `
            -ProtectedUsersGroupIdentity 'Protected Users' `
            -PrivilegedGroupIdentities @('Domain Admins') `
            -ExplicitIncludeUsers @('svc-breakglass') `
            -ExplicitExcludeUsers @('legacy-service') `
            -RemovalMode AddOnly `
            -LogDirectory $logDirectory

        $result.PlannedAddUsers | Should -Be @('svc-breakglass')
        $result.ExcludedUsers | Should -Contain 'bob'
    }

    It 'includes AdminCount users only when requested' {
        $logDirectory = New-TestLogDirectory
        $withoutAdminCount = Invoke-ProtectedUsersSync `
            -ProtectedUsersGroupIdentity 'Protected Users' `
            -PrivilegedGroupIdentities @('Domain Admins') `
            -RemovalMode AddOnly `
            -LogDirectory $logDirectory

        $secondLogDirectory = New-TestLogDirectory -Prefix 'LogsWithAdminCount'
        $withAdminCount = Invoke-ProtectedUsersSync `
            -ProtectedUsersGroupIdentity 'Protected Users' `
            -PrivilegedGroupIdentities @('Domain Admins') `
            -IncludeAdminCount `
            -RemovalMode AddOnly `
            -LogDirectory $secondLogDirectory

        $withoutAdminCount.PlannedAddUsers | Should -Be @('bob')
        $withAdminCount.PlannedAddUsers | Should -Contain 'bob'
        $withAdminCount.PlannedAddUsers | Should -Contain 'charlie'

        Assert-MockCalled Get-ADUser -ParameterFilter { $LDAPFilter -eq '(adminCount=1)' } -Times 1 -ModuleName $moduleName
    }
}
