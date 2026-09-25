#!/usr/bin/env pwsh
# =====================================================================
#  CertForge — issue-client.ps1
#  Emite um certificado de cliente e (opcionalmente) monta os bundles
#  para Oracle e/ou Azure SQL.
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
#
#  Exemplos:
#    ./scripts/issue-client.ps1 -CommonName "app-faturamento" -Email app@empresa.com
#    ./scripts/issue-client.ps1 -CommonName "svc-etl" -Upn svc-etl@empresa.com `
#         -Oracle -DbHost db.empresa.com -ServiceName ORCLPDB1
#    ./scripts/issue-client.ps1 -CommonName "svc-bi" -AzureSql `
#         -SqlServer meusrv.database.windows.net -Database vendas
# =====================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CommonName,
    [string]$Email,
    [string]$Upn,
    [string[]]$DnsNames,
    [int]$ValidityDays,
    [string]$Store,
    [string]$Config,

    [switch]$Oracle,
    [string]$DbHost = 'oracle.exemplo.com',
    [int]$DbPort = 2484,
    [string]$ServiceName = 'ORCLPDB1',

    [switch]$AzureSql,
    [string]$SqlServer,
    [string]$Database,
    [string]$AppDisplayName,
    [string]$TenantId,

    [switch]$ImportToWindows,
    [switch]$BindToTpm
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\CertForge.psd1') -Force

$cfg = Get-CfConfig -Path $Config
$storeRoot = if ($Store) { [System.IO.Path]::GetFullPath($Store) } `
             else { [System.IO.Path]::GetFullPath($cfg.paths.storeRoot) }

$intPass = Read-Host "Passphrase da CA INTERMEDIARIA" -AsSecureString
$expPass = Read-Host "Passphrase para proteger o PKCS#12 exportado" -AsSecureString

$client = New-CfClientCertificate -StoreRoot $storeRoot -Config $cfg `
    -CommonName $CommonName -IntermediatePassphrase $intPass `
    -Email $Email -Upn $Upn -DnsNames $DnsNames `
    -ExportPassphrase $expPass -ValidityDays $ValidityDays

Write-Host ""
$client | Format-List

if ($Oracle) {
    Write-Host "`n--- Bundle Oracle ---" -ForegroundColor Cyan
    $walletPass = Read-Host "Passphrase da Oracle Wallet" -AsSecureString
    New-CfOracleWalletBundle -ClientResult $client -StoreRoot $storeRoot `
        -WalletPassphrase $walletPass -DbHost $DbHost -DbPort $DbPort -ServiceName $ServiceName |
        Format-List
}

if ($AzureSql) {
    if (-not $SqlServer -or -not $Database) { throw "Para -AzureSql informe -SqlServer e -Database." }
    Write-Host "`n--- Bundle Azure SQL ---" -ForegroundColor Cyan
    $azParams = @{
        ClientResult = $client
        SqlServer    = $SqlServer
        Database     = $Database
    }
    if ($AppDisplayName) { $azParams.AppDisplayName = $AppDisplayName }
    if ($TenantId)       { $azParams.TenantId = $TenantId }
    New-CfAzureSqlBundle @azParams | Format-List
}

if ($ImportToWindows) {
    Write-Host "`n--- Importando no Windows Certificate Store ---" -ForegroundColor Cyan
    Import-CfClientToWindowsStore -Pkcs12File $client.Pkcs12File `
        -Pkcs12Passphrase $expPass -BindToTpm:$BindToTpm | Format-List
}
