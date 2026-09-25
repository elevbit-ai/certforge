#!/usr/bin/env pwsh
# =====================================================================
#  CertForge — Run-SelfTest.ps1
#  Teste automatizado de ponta a ponta (nao interativo). Cria uma CA
#  temporaria, emite certificados, gera bundles, revoga e valida o
#  ledger — inclusive a deteccao de adulteracao. Retorna codigo 0 se OK.
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
#
#  Uso:  pwsh ./tests/Run-SelfTest.ps1
# =====================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $ProjectRoot 'src\CertForge.psd1') -Force

$failures = 0
function Assert-True($cond, $msg) {
    if ($cond) { Write-Host "  [PASS] $msg" -ForegroundColor Green }
    else { Write-Host "  [FAIL] $msg" -ForegroundColor Red; $script:failures++ }
}

$store = Join-Path ([System.IO.Path]::GetTempPath()) ("cf-selftest-{0}" -f (Get-Random))
Write-Host "Store temporario: $store`n" -ForegroundColor DarkGray

try {
    $cfg = Get-CfConfig -Path (Join-Path $ProjectRoot 'config\certforge.config.json')
    $rootPass = ConvertTo-SecureString 'RaizSuperForte#2026!'         -AsPlainText -Force
    $intPass  = ConvertTo-SecureString 'IntermediariaForte#2026!'     -AsPlainText -Force
    $expPass  = ConvertTo-SecureString 'ExportP12Forte#2026!'         -AsPlainText -Force

    Write-Host "1) Criacao da hierarquia PKI" -ForegroundColor Cyan
    $ca = New-CfAuthority -StoreRoot $store -Config $cfg -RootPassphrase $rootPass -IntermediatePassphrase $intPass
    Assert-True (Test-Path $ca.RootCert) "Certificado raiz criado"
    Assert-True (Test-Path $ca.IntermediateCert) "Certificado intermediario criado"
    Assert-True (Test-Path $ca.ChainFile) "Cadeia (bundle) criada"
    Assert-True ($ca.RootFingerprint -match '^[0-9A-F:]+$') "Fingerprint da raiz valido"

    Write-Host "`n2) Emissao de certificado de cliente" -ForegroundColor Cyan
    $c1 = New-CfClientCertificate -StoreRoot $store -Config $cfg -CommonName 'svc-teste' `
        -Email 'svc-teste@empresa.com' -Upn 'svc-teste@empresa.com' `
        -IntermediatePassphrase $intPass -ExportPassphrase $expPass
    Assert-True (Test-Path $c1.CertFile) "Certificado do cliente emitido"
    Assert-True (Test-Path $c1.Pkcs12File) "PKCS#12 gerado"
    Assert-True (Test-Path $c1.DerFile) "DER (.cer) gerado para Azure"

    Write-Host "`n3) Cadeia e perfil do certificado" -ForegroundColor Cyan
    $verify = & openssl verify -CAfile $ca.ChainFile $c1.CertFile 2>&1
    Assert-True ($verify -match ': OK') "openssl verify aprovou a cadeia"
    $certText = & openssl x509 -in $c1.CertFile -noout -text 2>&1 | Out-String
    Assert-True ($certText -match 'TLS Web Client Authentication') "EKU = clientAuth presente"
    Assert-True ($certText -notmatch 'TLS Web Server Authentication') "NAO ha serverAuth (uso restrito)"
    Assert-True ($certText -match 'CRL Distribution') "CRL Distribution Point presente"

    Write-Host "`n4) Bundle Oracle" -ForegroundColor Cyan
    $walletPass = ConvertTo-SecureString 'WalletForte#2026!' -AsPlainText -Force
    $ora = New-CfOracleWalletBundle -ClientResult $c1 -StoreRoot $store -WalletPassphrase $walletPass -DbHost 'db.empresa.com'
    Assert-True (Test-Path $ora.SqlnetOra) "sqlnet.ora gerado"
    Assert-True (Test-Path $ora.TnsnamesOra) "tnsnames.ora gerado"
    Assert-True (Test-Path $ora.OrapkiScript) "roteiro orapki gerado"

    Write-Host "`n5) Bundle Azure SQL" -ForegroundColor Cyan
    $az = New-CfAzureSqlBundle -ClientResult $c1 -SqlServer 'srv.database.windows.net' -Database 'db' -AppDisplayName 'CertForge-Teste'
    Assert-True (Test-Path $az.CerFile) "arquivo .cer para App Registration gerado"
    Assert-True (Test-Path $az.AzureScript) "roteiro Azure CLI gerado"

    Write-Host "`n6) Revogacao e CRL" -ForegroundColor Cyan
    $crl = Revoke-CfCertificate -StoreRoot $store -Config $cfg -IntermediatePassphrase $intPass -CertFile $c1.CertFile -Reason keyCompromise
    Assert-True (Test-Path $crl) "CRL gerada apos revogacao"
    $crlText = & openssl crl -in $crl -noout -text 2>&1 | Out-String
    Assert-True ($crlText -match 'Serial Number') "CRL contem o serial revogado"

    Write-Host "`n7) Integridade do ledger" -ForegroundColor Cyan
    Assert-True (Test-CfLedger -StoreRoot $store) "Ledger integro"

    Write-Host "`n8) Deteccao de adulteracao do ledger" -ForegroundColor Cyan
    $ledgerPath = Join-Path $store 'ledger.jsonl'
    (Get-Content $ledgerPath) -replace 'svc-teste','svc-HACK' | Set-Content -Path $ledgerPath
    Assert-True (-not (Test-CfLedger -StoreRoot $store)) "Adulteracao detectada"
}
finally {
    Remove-Item $store -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($failures -eq 0) {
    Write-Host "==================== TODOS OS TESTES PASSARAM ====================" -ForegroundColor Green
    exit 0
} else {
    Write-Host "==================== $failures TESTE(S) FALHARAM ====================" -ForegroundColor Red
    exit 1
}
