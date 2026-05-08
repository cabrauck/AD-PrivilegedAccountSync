Set-StrictMode -Version Latest

$minimumPesterVersion = [version]'5.0.0'
$availablePester = Get-Module -ListAvailable -Name Pester |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $availablePester -or $availablePester.Version -lt $minimumPesterVersion) {
    Write-Host 'Installing Pester 5 into CurrentUser scope...'
    Install-Module -Name Pester -Scope CurrentUser -Repository PSGallery -MinimumVersion $minimumPesterVersion -Force -SkipPublisherCheck
}

$pesterModule = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -ge $minimumPesterVersion } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pesterModule) {
    throw 'Pester 5 installation succeeded but no usable module version was found.'
}

Import-Module -Name $pesterModule.Path -Force -ErrorAction Stop

$testRoot = Split-Path -Parent $PSCommandPath
$result = Invoke-Pester -Path $testRoot -ExcludeTag Integration -Output Detailed -PassThru

if ($result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0) {
    exit 1
}
