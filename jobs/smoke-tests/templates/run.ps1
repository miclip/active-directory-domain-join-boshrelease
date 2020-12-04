$ErrorActionPreference="Stop"

. $PSScriptRoot\env.ps1

$domainFQDN=(Get-Item env:DOMAIN_FQDN).Value
$domainServiceAccountName=(Get-Item env:DOMAIN_SERVICE_ACCOUNT_NAME).Value
$smokeTestCommand=(Get-Item env:SMOKE_TEST_COMMAND).Value

Invoke-Expression ($smokeTestCommand -f $domainServiceAccountName,$domainFQDN)

