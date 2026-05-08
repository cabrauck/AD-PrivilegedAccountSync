# Protected Users Sync for Active Directory

This repository contains a PowerShell-based sync for the Active Directory `Protected Users` group.

The script is designed to stay usable as a scheduled task entry point while keeping the decision logic testable and predictable.

## How the script works

On every run, the entry script loads the internal module from the same directory, resolves relative paths against the script folder, and then performs these steps:

1. Read the current direct user members of the target `Protected Users` group.
2. Build the desired membership set from:
   - recursive members of the configured privileged groups
   - optional `AdminCount=1` users when `-IncludeAdminCount` is enabled
   - explicit include users
3. Remove explicit exclude users from the desired set.
4. Compare current and desired membership by SID, not by `SamAccountName`.
5. Apply the difference according to `RemovalMode`:
   - `AddOnly`: add only missing desired users
   - `Authoritative`: add missing desired users and remove direct members that are no longer desired
6. Write a rotating log file and return a structured summary object.

This means the script is idempotent: if nothing changed in AD and the configuration stays the same, a second run should not perform new membership changes.

## Repository layout

- `AddRemove-AdminCount-Users-To-ProtectedUsers.ps1`
  Stable entry point for manual execution and scheduled tasks.
- `ProtectedUsersSync.psm1`
  Internal logic for desired-state calculation, diffing, AD operations, and logging.
- `ProtectedUsersSync.example.psd1`
  Example configuration file.
- `tests/`
  Pester 5 unit, orchestration, and integration test scaffolding.

## Requirements

- Windows host joined to the domain
- Active Directory PowerShell module
- Permission to read users/groups and modify the target `Protected Users` group
- Windows PowerShell 5.1 or newer for production execution
- PowerShell 7 recommended for local test execution

## Parameters

| Parameter | Default | Purpose |
| --- | --- | --- |
| `ProtectedUsersGroupIdentity` | `Protected Users` | Target group to maintain |
| `PrivilegedGroupIdentities` | Built-in list of 7 privileged groups | Source groups used to build the desired membership |
| `IncludeAdminCount` | `false` | Optionally include `AdminCount=1` users |
| `ExplicitIncludeUsers` | empty | Always include these users |
| `ExplicitExcludeUsers` | empty | Always exclude these users, even if another source would include them |
| `RemovalMode` | `AddOnly` | Membership enforcement mode |
| `ConfigPath` | none | Optional `.psd1` configuration file |
| `LogDirectory` | `<script directory>\Logs` | Log directory |
| `LogFileName` | `ProtectedUsersSync.log` | Current log file name |

## Configuration precedence

The script applies configuration in this order:

1. Explicit script parameters
2. Values from the `.psd1` configuration file
3. Built-in defaults

`AdminCount` is intentionally not part of the default behavior. It must be enabled explicitly with `-IncludeAdminCount` or via the configuration file.

## Path behavior and scheduled task safety

The script is built to remain scheduled-task friendly:

- The entry script keeps the original file name.
- The internal module is loaded by using `$PSScriptRoot`, so it is found even when the scheduled task starts in `C:\Windows\System32`.
- Relative `-ConfigPath` and `-LogDirectory` values are resolved relative to the script directory.
- If you do not set `-LogDirectory`, logs are written to `Logs` under the script directory.

Because of that, you can keep the task simple and do not have to rely on the task's `Start in` directory for module or config resolution.

## Example configuration

Copy the sample file and adjust it for your environment:

```powershell
Copy-Item .\ProtectedUsersSync.example.psd1 .\ProtectedUsersSync.psd1
```

Example:

```powershell
@{
    ProtectedUsersGroupIdentity = 'Protected Users'
    PrivilegedGroupIdentities   = @(
        'Domain Admins'
        'Enterprise Admins'
        'Schema Admins'
        'Administrators'
    )
    IncludeAdminCount           = $false
    ExplicitIncludeUsers        = @('svc-breakglass')
    ExplicitExcludeUsers        = @('legacy-service-account')
    RemovalMode                 = 'AddOnly'
    LogDirectory                = '.\Logs'
    LogFileName                 = 'ProtectedUsersSync.log'
}
```

## Usage examples

Dry run:

```powershell
.\AddRemove-AdminCount-Users-To-ProtectedUsers.ps1 -WhatIf -Verbose
```

Run with a configuration file:

```powershell
.\AddRemove-AdminCount-Users-To-ProtectedUsers.ps1 -ConfigPath .\ProtectedUsersSync.psd1 -Verbose
```

Enable `AdminCount` as an additional source:

```powershell
.\AddRemove-AdminCount-Users-To-ProtectedUsers.ps1 -IncludeAdminCount -Verbose
```

Add explicit break-glass users and exclude a legacy service account:

```powershell
.\AddRemove-AdminCount-Users-To-ProtectedUsers.ps1 `
    -ExplicitIncludeUsers 'svc-breakglass' `
    -ExplicitExcludeUsers 'legacy-service-account' `
    -Verbose
```

Run in full authoritative mode:

```powershell
.\AddRemove-AdminCount-Users-To-ProtectedUsers.ps1 `
    -RemovalMode Authoritative `
    -Verbose
```

## Scheduled task examples

Recommended program:

```text
powershell.exe
```

Minimal arguments:

```text
-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\AD-PrivilegedAccountSync\AddRemove-AdminCount-Users-To-ProtectedUsers.ps1"
```

Using a config file next to the script:

```text
-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\AD-PrivilegedAccountSync\AddRemove-AdminCount-Users-To-ProtectedUsers.ps1" -ConfigPath ".\ProtectedUsersSync.psd1"
```

Using explicit authoritative mode:

```text
-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\AD-PrivilegedAccountSync\AddRemove-AdminCount-Users-To-ProtectedUsers.ps1" -RemovalMode Authoritative
```

Task Scheduler example settings:

- Program/script: `powershell.exe`
- Add arguments: one of the examples above
- Run whether user is logged on or not
- Run with highest privileges
- Start in: optional

## Logging

The script creates the log directory if needed and rotates the current log before each run.

- Current log: `ProtectedUsersSync.log`
- Archive pattern: `ProtectedUsersSync_yyyy-MM-dd_HH-mm-ss.log`

Each run logs:

- effective configuration
- planned adds and removals
- executed actions
- warnings and errors
- final summary

## Output

The script returns a summary object with at least these properties:

- `Mode`
- `IncludeAdminCount`
- `CurrentCount`
- `DesiredCount`
- `PlannedAddUsers`
- `PlannedRemoveUsers`
- `AddedUsers`
- `RemovedUsers`
- `SkippedExistingUsers`
- `ExcludedUsers`
- `FailedActions`
- `Succeeded`

If one or more membership changes fail, the script still returns the summary object and exits with code `1`.

## Tests

Run the local test suite with:

```powershell
pwsh .\tests\Invoke-Tests.ps1
```

The test runner installs Pester 5 in `CurrentUser` scope when required.

Integration tests are tagged with `Integration` and are skipped by default until you wire them to a lab environment.

## License

MIT
