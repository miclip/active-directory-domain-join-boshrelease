$ErrorActionPreference="Stop"
# ref: https://blogs.technet.microsoft.com/chadcox/2016/10/25/chads-quick-notes-installing-a-domain-controller-with-server-2016-core/

. $PSScriptRoot\env.ps1

$domainFQDN=(Get-Item env:DOMAIN_FQDN).Value
$domainAdminUsername=(Get-Item env:DOMAIN_ADMIN_USERNAME).Value
$domainAdminPassword=(Get-Item env:DOMAIN_ADMIN_PASSWORD).Value
$networkAdapterName=(Get-Item env:NETWORK_ADAPTER_NAME).Value
$windowsFeaturesSource=(Get-Item env:WINDOWS_FEATURES_SOURCE).Value
$runAfterRebootPS1Path=(Get-Item env:RUN_AFTER_REBOOT_PS1 -ErrorAction Ignore).Value
$runAfterRebootLogPath=(Get-Item env:RUN_AFTER_REBOOT_LOG).Value

$domainAdminPasswordObject = ConvertTo-SecureString -String $domainAdminPassword -AsPlainText -Force
$localAdminCredObject = New-Object System.Management.Automation.PSCredential ($domainAdminUsername, $domainAdminPasswordObject)

if (Get-Service NTDS -ErrorAction Ignore) {
    echo "Already promoted to domain controller"
    Exit 0
}

if ($runAfterRebootPS1Path) {
    $taskName = "RunAfterReboot"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $scriptRoot = Split-Path $runAfterRebootPS1Path

    # Commmand will:
    #  Set PSScriptRoot since Scheduled Tasks don't set it automatically
    #  Start logging
    #  Start bosh-agent
    $command = "`$PSScriptRoot=`"$scriptRoot`"; Start-Transcript -Append $runAfterRebootLogPath; Start-Service bosh-agent; $runAfterRebootPS1Path"

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $command 
    Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -RunLevel Highest -Force -User "System"
}

# Install AD Features
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -Source $windowsFeaturesSource
Install-WindowsFeature DNS -IncludeManagementTools -Source $windowsFeaturesSource

# Prepend localhost to exising DNS getservers
$originalDNSServers=(Get-DnsClientServerAddress -InterfaceAlias $networkAdapterName -AddressFamily IPv4).ServerAddresses
$updatedDNSServers=@("127.0.0.1") + $originalDNSServers
Set-DnsClientServerAddress -InterfaceAlias $networkAdapterName -ServerAddresses $updatedDNSServers

# Create AD forrest
Install-ADDSForest -DomainName $domainFQDN -SafeModeAdministratorPassword $domainAdminPasswordObject -InstallDns -NoRebootOnCompletion -Confirm:$False

# Restart
Restart-Computer