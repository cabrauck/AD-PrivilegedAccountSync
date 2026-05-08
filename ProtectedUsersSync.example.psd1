@{
    ProtectedUsersGroupIdentity = 'Protected Users'
    PrivilegedGroupIdentities   = @(
        'Domain Admins'
        'Enterprise Admins'
        'Schema Admins'
        'Administrators'
        'Backup Operators'
        'Server Operators'
        'Account Operators'
    )
    IncludeAdminCount           = $false
    ExplicitIncludeUsers        = @(
        'svc-breakglass'
    )
    ExplicitExcludeUsers        = @(
        'legacy-service-account'
    )
    RemovalMode                 = 'AddOnly'
    LogDirectory                = '.\Logs'
    LogFileName                 = 'ProtectedUsersSync.log'
}
