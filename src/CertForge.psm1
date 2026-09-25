# =====================================================================
#  CertForge — Módulo principal
#  Autoridade Certificadora emissora de certificados de cliente para
#  autenticação em Oracle Database (TCPS) e Azure SQL (Entra ID).
#
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
#  Licença: MIT
# =====================================================================

Set-StrictMode -Version Latest

$libPath = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libPath 'Common.ps1')
. (Join-Path $libPath 'Ledger.ps1')
. (Join-Path $libPath 'CaEngine.ps1')
. (Join-Path $libPath 'ClientIssue.ps1')
. (Join-Path $libPath 'Revocation.ps1')
. (Join-Path $libPath 'OracleWallet.ps1')
. (Join-Path $libPath 'AzureSql.ps1')
. (Join-Path $libPath 'WindowsStore.ps1')

Export-ModuleMember -Function @(
    'Get-CfConfig',
    'New-CfAuthority',
    'New-CfClientCertificate',
    'Revoke-CfCertificate',
    'Publish-CfCrl',
    'New-CfOracleWalletBundle',
    'New-CfAzureSqlBundle',
    'Import-CfClientToWindowsStore',
    'Add-CfLedgerEntry',
    'Test-CfLedger',
    'Get-CfFingerprint',
    'Write-CfLog'
)
