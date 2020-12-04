$ErrorActionPreference="Stop"

. $PSScriptRoot\env.ps1

$domainFQDN=(Get-Item env:DOMAIN_FQDN).Value
$domainAdminUsername=(Get-Item env:DOMAIN_ADMIN_USERNAME).Value
$domainAdminPassword=(Get-Item env:DOMAIN_ADMIN_PASSWORD).Value
$domainUserUsername=(Get-Item env:DOMAIN_USER_USERNAME).Value
$domainUserPassword=(Get-Item env:DOMAIN_USER_PASSWORD).Value
$domainGroupName=(Get-Item env:DOMAIN_GROUP_NAME).Value
$domainServiceAccountName=(Get-Item env:DOMAIN_SERVICE_ACCOUNT_NAME).Value
$windowsFeaturesSource=(Get-Item env:WINDOWS_FEATURES_SOURCE).Value

$domainAdminPasswordObject = ConvertTo-SecureString -String $domainAdminPassword -AsPlainText -Force
$domainAdminCredObject = New-Object System.Management.Automation.PSCredential ("$domainAdminUsername@$domainFQDN", $domainAdminPasswordObject)

Install-WindowsFeature RSAT-AD-PowerShell -Source $windowsFeaturesSource
Import-Module ActiveDirectory

# Check for presence or creatability of AD drive for readiness
while (-Not ((Get-PSDrive -PSProvider ActiveDirectory -ErrorAction Ignore) -Or (New-PSDrive -Name AD -PSProvider ActiveDirectory -Root "" -ErrorAction Ignore))) {
    Write-Host "Waiting for domain controller to initialize"
    Start-Sleep 1
}

# Exit if GMSA already created
if (Get-ADServiceAccount -Filter "Name -Eq '$domainServiceAccountName'" -Credential $domainAdminCredObject -Server localhost) {
    echo "Service account already exists"
    Exit 0
}

# Init KDS Root key immediately
Add-KdsRootKey -EffectiveTime ((get-date).addhours(-10))

New-ADUser -Name $domainUserUsername -PasswordNotRequired $True -Enabled $True -Credential $domainAdminCredObject

Set-ADAccountPassword -Identity $domainUserUsername -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $domainUserPassword -Force) -Credential $domainAdminCredObject

New-ADGroup -Name $domainGroupName -SamAccountName $domainGroupName -GroupScope Global -ManagedBy $domainUserUsername -Credential $domainAdminCredObject

# Allow domain user to add memberships https://adamtheautomator.com/active-directory-group-powershell/
$domainUser = Get-ADUser $domainUserUsername
$domainGroup = Get-ADGroup $domainGroupName
$NTPrincipal = New-Object System.Security.Principal.NTAccount($domainUser.samAccountName)
$writeMembersPropertyGUID = New-Object GUID('bf9679c0-0de6-11d0-a285-00aa003049e2')
$acl = Get-ACL "AD:$($domainGroup.distinguishedName)"
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($NTPrincipal,'WriteProperty','Allow',$writeMembersPropertyGUID)
$acl.AddAccessRule($ace)
Set-ACL -AclObject $acl -Path "AD:$($domainGroup.distinguishedName)"

# Increase maximum allow domain joins
Get-ADDomain | Set-ADDomain -Replace @{"ms-ds-MachineAccountQuota"="99999"}

Write-Host "Create service account"
New-ADServiceAccount -Name $domainServiceAccountName -DNSHostName "$domainServiceAccountName.$domainFQDN" -ServicePrincipalNames "http/$domainServiceAccountName.$domainFQDN" -PrincipalsAllowedToRetrieveManagedPassword $domainGroupName -PrincipalsAllowedToDelegateToAccount $domainGroupName -Credential $domainAdminCredObject

# Verify the group is added to the AD
# service account named $domainServiceAccountName
Get-ADServiceAccount $domainServiceAccountName -Properties PrincipalsAllowedToRetrieveManagedPassword, PrincipalsAllowedToDelegateToAccount -Credential $domainAdminCredObject
