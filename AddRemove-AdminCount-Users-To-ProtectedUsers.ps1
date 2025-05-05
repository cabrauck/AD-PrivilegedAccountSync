# Import the Active Directory module
Import-Module ActiveDirectory

# Define the Protected Users group
$protectedUsersGroup = "CN=Protected Users,CN=Users,DC=YourDomain,DC=com"

# Function to add users to Protected Users group
function Add-ToProtectedUsers {
    param (
        [string]$SamAccountName
    )
    Add-ADGroupMember -Identity $protectedUsersGroup -Members $SamAccountName -ErrorAction SilentlyContinue
}

# Function to remove users from Protected Users group
function Remove-FromProtectedUsers {
    param (
        [string]$SamAccountName
    )
    Remove-ADGroupMember -Identity $protectedUsersGroup -Members $SamAccountName -Confirm:$false -ErrorAction SilentlyContinue
}

# Get current members of the Protected Users group
$currentProtectedUsers = Get-ADGroupMember -Identity $protectedUsersGroup | Where-Object { $_.ObjectClass -eq 'user' }

# Get all users with AdminCount=1
$adminUsers = Get-ADUser -Filter {AdminCount -eq 1} -Properties AdminCount
$adminUsersSam = $adminUsers | Select-Object -ExpandProperty SamAccountName

# Process each user in the domain
$allUsers = Get-ADUser -Filter * -Properties AdminCount
foreach ($user in $allUsers) {
    if ($user.AdminCount -eq 1) {
        # Add user to Protected Users group if not already a member
        if ($currentProtectedUsers -notcontains $user.SamAccountName) {
            Add-ToProtectedUsers -SamAccountName $user.SamAccountName
            Write-Host "Added $($user.SamAccountName) to Protected Users group"
        }
    } else {
        # Remove user from Protected Users group if they are currently a member
        if ($currentProtectedUsers -contains $user.SamAccountName) {
            Remove-FromProtectedUsers -SamAccountName $user.SamAccountName
            Write-Host "Removed $($user.SamAccountName) from Protected Users group"
        }
    }
}

# Get all users in specific privileged groups
$privilegedGroups = @(
    "Domain Admins",
    "Enterprise Admins",
    "Schema Admins",
    "Administrators",
    "Backup Operators",
    "Server Operators",
    "Account Operators"
)

foreach ($group in $privilegedGroups) {
    $groupMembers = Get-ADGroupMember -Identity $group -Recursive | Where-Object { $_.ObjectClass -eq "user" }
    foreach ($member in $groupMembers) {
        if ($currentProtectedUsers -notcontains $member.SamAccountName) {
            Add-ToProtectedUsers -SamAccountName $member.SamAccountName
            Write-Host "Added $($member.SamAccountName) to Protected Users group from $group"
        }
    }
}

Write-Host "Script execution completed."
