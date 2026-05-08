Set-StrictMode -Version Latest

$modulePath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'ProtectedUsersSync.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop

Describe 'Invoke-ProtectedUsersSync integration scenarios' -Tag 'Integration' {
    BeforeAll {
        $script:integrationReason = $null

        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            $script:integrationReason = 'ActiveDirectory module is not available on this host.'
        } elseif (-not $env:PROTECTED_USERS_TEST_GROUP) {
            $script:integrationReason = 'Set PROTECTED_USERS_TEST_GROUP for the lab Protected Users target group.'
        } elseif (-not $env:PROTECTED_USERS_TEST_PRIV_GROUP) {
            $script:integrationReason = 'Set PROTECTED_USERS_TEST_PRIV_GROUP for the lab privileged source group.'
        } elseif (-not $env:PROTECTED_USERS_TEST_USER) {
            $script:integrationReason = 'Set PROTECTED_USERS_TEST_USER for the lab test user identity.'
        }
    }

    It 'adds a newly eligible user in AddOnly mode' {
        if ($script:integrationReason) {
            Set-ItResult -Skipped -Because $script:integrationReason
            return
        }

        Set-ItResult -Skipped -Because 'Customize fixture setup for your lab before enabling this integration test.'
    }

    It 'removes a no-longer-desired direct member in Authoritative mode' {
        if ($script:integrationReason) {
            Set-ItResult -Skipped -Because $script:integrationReason
            return
        }

        Set-ItResult -Skipped -Because 'Customize fixture setup for your lab before enabling this integration test.'
    }

    It 'does not remove unknown members in AddOnly mode' {
        if ($script:integrationReason) {
            Set-ItResult -Skipped -Because $script:integrationReason
            return
        }

        Set-ItResult -Skipped -Because 'Customize fixture setup for your lab before enabling this integration test.'
    }

    It 'is idempotent on a second run with unchanged AD state' {
        if ($script:integrationReason) {
            Set-ItResult -Skipped -Because $script:integrationReason
            return
        }

        Set-ItResult -Skipped -Because 'Customize fixture setup for your lab before enabling this integration test.'
    }
}
