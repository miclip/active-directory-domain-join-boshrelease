$ErrorActionPreference="Stop"

. $PSScriptRoot\env.ps1

$domainFQDN=(Get-Item env:DOMAIN_FQDN).Value
$domainControllerIpAddress=(Get-Item env:DOMAIN_CONTROLLER_IP_ADDRESS).Value
$domainUserUsername=(Get-Item env:DOMAIN_USER_USERNAME).Value
$domainUserPassword=(Get-Item env:DOMAIN_USER_PASSWORD).Value
$networkAdapterName=(Get-Item env:NETWORK_ADAPTER_NAME).Value
$rebootAfterJoin=(Get-Item env:REBOOT_AFTER_JOIN).Value

$domainUserPasswordObject = ConvertTo-SecureString -String $domainUserPassword -AsPlainText -Force
$domainUserCredObject = New-Object System.Management.Automation.PSCredential ("$domainUserUsername@$domainFQDN", $domainUserPasswordObject)

# Skip joining if already joined
if ((Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain) {
    echo "Already joined to domain"
    Exit 0
}

# Always prepend localhost to exising DNS servers
Set-DnsClientServerAddress -InterfaceAlias $networkAdapterName -ServerAddresses @($domainControllerIpAddress)

# Wait for Domain controller by attempting connection. 
# NOTE: netdom was the only command I found that won't succeed until DC and accounts are fully up but also it can test w/o being joined to domain 
while ((netdom query DC /domain $domainFQDN /userd $domainUserUsername /passwordd $domainUserPassword) -And $LASTEXITCODE -ne 0) {
    Write-Host (Get-Date)": Waiting for domain controller"
    Start-Sleep 10
}

# Join computer to domain
Add-Computer -DomainName $domainFQDN -Credential $domainUserCredObject

# Check connection after joining
Test-ComputerSecureChannel -Credential $domainUserCredObject -Repair

if ($rebootAfterJoin -eq "true") {
    # Set bosh-agent to start automatically
    Set-Service bosh-agent -StartupType Automatic

    # Restart to apply changes
    Restart-Computer
}
