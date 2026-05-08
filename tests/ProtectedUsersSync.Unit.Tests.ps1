Set-StrictMode -Version Latest

$modulePath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'ProtectedUsersSync.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop

function script:New-TestUserRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Sid,
        [Parameter(Mandatory = $true)]
        [string]$SamAccountName,
        [string]$DistinguishedName = 'CN=User,DC=example,DC=com',
        [string[]]$Sources = @('Test')
    )

    [pscustomobject]@{
        Sid               = $Sid
        SamAccountName    = $SamAccountName
        DistinguishedName = $DistinguishedName
        Sources           = $Sources
    }
}

Describe 'Get-DesiredProtectedUsers' {
    It 'includes privileged group members by default' {
        $privileged = @(
            New-TestUserRecord -Sid 'S-1-5-21-1' -SamAccountName 'alice' -Sources @('PrivilegedGroup:Domain Admins')
        )

        $result = Get-DesiredProtectedUsers -PrivilegedGroupMembers $privileged

        $result.DesiredMembers.SamAccountName | Should -Be @('alice')
    }

    It 'includes admincount users only when explicitly enabled' {
        $adminCount = @(
            New-TestUserRecord -Sid 'S-1-5-21-2' -SamAccountName 'bob' -Sources @('AdminCount')
        )

        $withoutAdminCount = Get-DesiredProtectedUsers -AdminCountMembers $adminCount
        $withAdminCount = Get-DesiredProtectedUsers -AdminCountMembers $adminCount -IncludeAdminCount

        @($withoutAdminCount.DesiredMembers).Count | Should -Be 0
        $withAdminCount.DesiredMembers.SamAccountName | Should -Be @('bob')
    }

    It 'deduplicates users coming from multiple sources' {
        $privileged = @(
            New-TestUserRecord -Sid 'S-1-5-21-3' -SamAccountName 'charlie' -Sources @('PrivilegedGroup:Domain Admins')
        )
        $includes = @(
            New-TestUserRecord -Sid 'S-1-5-21-3' -SamAccountName 'charlie' -Sources @('ExplicitInclude')
        )

        $result = Get-DesiredProtectedUsers -PrivilegedGroupMembers $privileged -ExplicitIncludeMembers $includes

        @($result.DesiredMembers).Count | Should -Be 1
        $result.DesiredMembers[0].Sources | Should -Contain 'PrivilegedGroup:Domain Admins'
        $result.DesiredMembers[0].Sources | Should -Contain 'ExplicitInclude'
    }

    It 'applies explicit excludes as the strongest rule' {
        $privileged = @(
            New-TestUserRecord -Sid 'S-1-5-21-4' -SamAccountName 'dana' -Sources @('PrivilegedGroup:Domain Admins')
        )
        $adminCount = @(
            New-TestUserRecord -Sid 'S-1-5-21-4' -SamAccountName 'dana' -Sources @('AdminCount')
        )
        $excludes = @(
            New-TestUserRecord -Sid 'S-1-5-21-4' -SamAccountName 'dana' -Sources @('ExplicitExclude')
        )

        $result = Get-DesiredProtectedUsers `
            -PrivilegedGroupMembers $privileged `
            -AdminCountMembers $adminCount `
            -ExplicitExcludeMembers $excludes `
            -IncludeAdminCount

        @($result.DesiredMembers).Count | Should -Be 0
        $result.ExcludedUsers.SamAccountName | Should -Be @('dana')
    }
}

Describe 'Compare-ProtectedUsersMembership' {
    It 'does not add users that already exist when SID matches' {
        $current = @(
            New-TestUserRecord -Sid 'S-1-5-21-10' -SamAccountName 'alice'
        )
        $desired = @(
            New-TestUserRecord -Sid 'S-1-5-21-10' -SamAccountName 'ALICE'
        )

        $result = Compare-ProtectedUsersMembership -CurrentMembers $current -DesiredMembers $desired -RemovalMode AddOnly

        @($result.ToAdd).Count | Should -Be 0
        $result.SkippedExistingUsers.SamAccountName | Should -Be @('ALICE')
    }

    It 'returns only missing desired users in AddOnly mode' {
        $current = @(
            New-TestUserRecord -Sid 'S-1-5-21-11' -SamAccountName 'alice'
        )
        $desired = @(
            New-TestUserRecord -Sid 'S-1-5-21-11' -SamAccountName 'alice'
            New-TestUserRecord -Sid 'S-1-5-21-12' -SamAccountName 'bob'
        )

        $result = Compare-ProtectedUsersMembership -CurrentMembers $current -DesiredMembers $desired -RemovalMode AddOnly

        $result.ToAdd.SamAccountName | Should -Be @('bob')
        @($result.ToRemove).Count | Should -Be 0
    }

    It 'removes current users outside the desired set in Authoritative mode' {
        $current = @(
            New-TestUserRecord -Sid 'S-1-5-21-13' -SamAccountName 'alice'
            New-TestUserRecord -Sid 'S-1-5-21-14' -SamAccountName 'bob'
        )
        $desired = @(
            New-TestUserRecord -Sid 'S-1-5-21-13' -SamAccountName 'alice'
        )

        $result = Compare-ProtectedUsersMembership -CurrentMembers $current -DesiredMembers $desired -RemovalMode Authoritative

        $result.ToRemove.SamAccountName | Should -Be @('bob')
        @($result.ToAdd).Count | Should -Be 0
    }
}

Describe 'Resolve-ProtectedUsersSyncConfiguration' {
    It 'lets explicit parameters override config values' {
        $configPath = Join-Path -Path $TestDrive -ChildPath 'config.psd1'
        Set-Content -Path $configPath -Value @'
@{
    RemovalMode = 'Authoritative'
    IncludeAdminCount = $true
    LogDirectory = '.\ConfiguredLogs'
}
'@

        $result = Resolve-ProtectedUsersSyncConfiguration `
            -ConfigPath $configPath `
            -RemovalMode AddOnly `
            -IncludeAdminCount:$false `
            -LogDirectory '.\ExplicitLogs'

        $result.RemovalMode | Should -Be 'AddOnly'
        $result.IncludeAdminCount | Should -BeFalse
        $result.LogDirectory | Should -Match 'ExplicitLogs$'
    }
}
