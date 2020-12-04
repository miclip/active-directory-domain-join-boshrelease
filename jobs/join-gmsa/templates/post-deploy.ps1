$ErrorActionPreference="Stop"

. $PSScriptRoot\env.ps1

$domainFQDN=(Get-Item env:DOMAIN_FQDN).Value
$domainUserUsername=(Get-Item env:DOMAIN_USER_USERNAME).Value
$domainUserPassword=(Get-Item env:DOMAIN_USER_PASSWORD).Value
$domainGroupName=(Get-Item env:DOMAIN_GROUP_NAME).Value
$domainServiceAccountName=(Get-Item env:DOMAIN_SERVICE_ACCOUNT_NAME).Value
$windowsFeaturesSource=(Get-Item env:WINDOWS_FEATURES_SOURCE).Value
$computerName=$env:COMPUTERNAME
$rebootAfterJoin=(Get-Item env:REBOOT_AFTER_JOIN).Value

$domainUserPasswordObject = ConvertTo-SecureString -String $domainUserPassword -AsPlainText -Force
$domainUserCredObject = New-Object System.Management.Automation.PSCredential ("$domainFQDN\$domainUserUsername", $domainUserPasswordObject)

# Wait for VM to be joined to domain
while (!((Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain)) {
    Write-Host (Get-Date)": Waiting for vm to be joined to domain controller"
    Start-Sleep 1
}

# Install AD powershell scripts
Install-WindowsFeature RSAT-AD-PowerShell -Source $windowsFeaturesSource
Import-Module ActiveDirectory

# Make computer a member of the gmsa group
$computer=Get-ADComputer $computerName -Credential $domainUserCredObject

# Exit if already joined GMSA
if ((Get-ADGroupMember -Identity $domainGroupName -Credential $domainUserCredObject).SID -Contains $computer.SID) {
    echo "Already member of GMSA group"
    Exit 0
}

Add-ADGroupMember -Identity $domainGroupName -Members $computer -Credential $domainUserCredObject

# Generate credential spec
$dockerCredentialSpecDir="c:\ProgramData\docker\credentialspecs"

# create directory 
If(!(test-path $dockerCredentialSpecDir))
{
      New-Item -ItemType Directory -Force -Path $dockerCredentialSpecDir
}

$dockerCredentialSpecPath="$dockerCredentialSpecDir\$domainServiceAccountName.json"

# Use credentials to fetch ADDomain (note: this is why CredentialSpec won't work - can't supply alternate credentials)
$ADDomain = Get-ADDomain -Server $domainFQDN -Credential $domainUserCredObject

# Create CredSpec Object (ref: https://github.com/MicrosoftDocs/Virtualization-Documentation/blob/master/windows-server-container-tools/ServiceAccounts/CredentialSpec.psm1)
$dockerCredentialData = @{
    "ActiveDirectoryConfig" = @{
        "GroupManagedServiceAccounts" = @(
             @{"Name" = $domainServiceAccountName; "Scope" = $ADDomain.DNSRoot }
             @{"Name" = $domainServiceAccountName; "Scope" = $ADDomain.NetBIOSName }
        )
    }
    "CmsPlugins" = @("ActiveDirectory");
    "DomainJoinConfig" = @{
        "DnsName" = $ADDomain.DNSRoot
        "Guid" = $ADDomain.ObjectGUID
        "DnsTreeName" = $ADDomain.Forest
        "NetBiosName" = $ADDomain.NetBIOSName
        "Sid" = $ADDomain.DomainSID.Value
        "MachineAccountName" = $domainServiceAccountName
    }
}

$dockerCredentialData | ConvertTo-Json -Depth 5 | Out-File -FilePath $dockerCredentialSpecPath -Encoding ascii

if ($rebootAfterJoin -eq "true") {
    # Set bosh-agent to start automatically
    Set-Service bosh-agent -StartupType Automatic
    Set-Service bosh-dns-windows -StartupType Automatic
    Set-Service bosh-dns-healthcheck-windows -StartupType Automatic
    Set-Service bosh-dns-nameserverconfig-windows -StartupType Automatic
    Set-Service kubelet -StartupType Automatic
    Set-Service kube-proxy -StartupType Automatic
    Set-Service nsx-kube-proxy -StartupType Automatic
    Set-Service nsx-node-agent -StartupType Automatic
    Set-Service dockerd -StartupType Automatic
    Set-Service ovs-vswitchd -StartupType Automatic
    Set-Service ovsdb-server -StartupType Automatic
    Set-Service system-metrics-agent -StartupType Automatic

    Get-Service bosh-agent | Select-Object -Property Name, StartType, Status
    Stop-Service -Name bosh-agent -Force -NoWait
    

    # Restart to apply changes
    echo "Restarting vm"
    Restart-Computer
}
