#!/usr/bin/env pwsh
# =====================================================================
#  CertForge — revoke.ps1
#  Revoga um certificado e regenera a CRL.
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
#
#  Exemplos:
#    ./scripts/revoke.ps1 -CertFile ./.certforge-store/issued/svc-etl/svc-etl.cert.pem -Reason keyCompromise
#    ./scripts/revoke.ps1 -Serial 1000 -Reason superseded
# =====================================================================
[CmdletBinding(DefaultParameterSetName = 'ByFile')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ByFile')][string]$CertFile,
    [Parameter(Mandatory, ParameterSetName = 'BySerial')][string]$Serial,
    [ValidateSet('unspecified','keyCompromise','caCompromise','affiliationChanged',
                 'superseded','cessationOfOperation','certificateHold')]
    [string]$Reason = 'unspecified',
    [string]$Store,
    [string]$Config
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\CertForge.psd1') -Force

$cfg = Get-CfConfig -Path $Config
$storeRoot = if ($Store) { [System.IO.Path]::GetFullPath($Store) } `
             else { [System.IO.Path]::GetFullPath($cfg.paths.storeRoot) }

$intPass = Read-Host "Passphrase da CA INTERMEDIARIA" -AsSecureString

if ($PSCmdlet.ParameterSetName -eq 'BySerial') {
    Revoke-CfCertificate -StoreRoot $storeRoot -Config $cfg `
        -IntermediatePassphrase $intPass -Serial $Serial -Reason $Reason
} else {
    Revoke-CfCertificate -StoreRoot $storeRoot -Config $cfg `
        -IntermediatePassphrase $intPass -CertFile $CertFile -Reason $Reason
}
