[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$ProtectedUsersGroupIdentity = 'Protected Users',
    [string[]]$PrivilegedGroupIdentities = @(
        'Domain Admins',
        'Enterprise Admins',
        'Schema Admins',
        'Administrators',
        'Backup Operators',
        'Server Operators',
        'Account Operators'
    ),
    [switch]$IncludeAdminCount,
    [string[]]$ExplicitIncludeUsers = @(),
    [string[]]$ExplicitExcludeUsers = @(),
    [ValidateSet('AddOnly', 'Authoritative')]
    [string]$RemovalMode = 'AddOnly',
    [string]$ConfigPath,
    [string]$LogDirectory = (Join-Path -Path $PSScriptRoot -ChildPath 'Logs'),
    [string]$LogFileName = 'ProtectedUsersSync.log'
)

Set-StrictMode -Version Latest

$scriptParameters = @{}
foreach ($entry in $PSBoundParameters.GetEnumerator()) {
    $scriptParameters[$entry.Key] = $entry.Value
}

if ($scriptParameters.ContainsKey('ConfigPath') -and -not [System.IO.Path]::IsPathRooted($scriptParameters.ConfigPath)) {
    $scriptParameters.ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath $scriptParameters.ConfigPath
}

if ($scriptParameters.ContainsKey('LogDirectory') -and -not [System.IO.Path]::IsPathRooted($scriptParameters.LogDirectory)) {
    $scriptParameters.LogDirectory = Join-Path -Path $PSScriptRoot -ChildPath $scriptParameters.LogDirectory
}

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'ProtectedUsersSync.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop

$result = Invoke-ProtectedUsersSync @scriptParameters
$result

if (-not $result.Succeeded) {
    exit 1
}
