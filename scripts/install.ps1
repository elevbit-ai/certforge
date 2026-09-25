#!/usr/bin/env pwsh
# =====================================================================
#  CertForge — install.ps1
#  Verifica os requisitos, registra o modulo no perfil do usuario e
#  valida a instalacao rodando o self-test.
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
#
#  Uso:  pwsh ./scripts/install.ps1
# =====================================================================
[CmdletBinding()]
param(
    [switch]$SkipSelfTest,
    [switch]$RegisterModulePath
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "  CertForge — instalacao" -ForegroundColor Cyan
Write-Host "  Autor: Joaquim Pedro de Morais Filho" -ForegroundColor DarkGray
Write-Host ""

# --- 1. Requisitos ---
Write-Host "[1/4] Verificando requisitos..." -ForegroundColor Yellow

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7.2+ e obrigatorio. Versao atual: $($PSVersionTable.PSVersion)"
}
Write-Host "  OK  PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green

$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) {
    Write-Host "  ERRO  OpenSSL nao encontrado no PATH." -ForegroundColor Red
    Write-Host "        Windows : winget install ShiningLight.OpenSSL.Light" -ForegroundColor DarkGray
    Write-Host "        Linux   : sudo apt install openssl" -ForegroundColor DarkGray
    Write-Host "        macOS   : brew install openssl@3" -ForegroundColor DarkGray
    throw "Instale o OpenSSL 3.x e rode novamente."
}
$ver = (& openssl version) 2>&1
Write-Host "  OK  $ver" -ForegroundColor Green

# --- 2. Importacao do modulo ---
Write-Host "[2/4] Importando o modulo CertForge..." -ForegroundColor Yellow
Import-Module (Join-Path $ProjectRoot 'src\CertForge.psd1') -Force
$mod = Get-Module CertForge
Write-Host "  OK  CertForge v$($mod.Version) — $($mod.ExportedFunctions.Count) funcoes exportadas" -ForegroundColor Green

# --- 3. Registro opcional no PSModulePath ---
if ($RegisterModulePath) {
    Write-Host "[3/4] Registrando o modulo no perfil..." -ForegroundColor Yellow
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
    $line = "Import-Module '$(Join-Path $ProjectRoot 'src\CertForge.psd1')' -ErrorAction SilentlyContinue"
    if (-not (Test-Path $PROFILE) -or -not (Select-String -Path $PROFILE -SimpleMatch 'CertForge.psd1' -Quiet)) {
        Add-Content -Path $PROFILE -Value $line
        Write-Host "  OK  Adicionado ao perfil: $PROFILE" -ForegroundColor Green
    } else {
        Write-Host "  OK  Ja registrado no perfil." -ForegroundColor Green
    }
} else {
    Write-Host "[3/4] Registro no perfil ignorado (use -RegisterModulePath para ativar)." -ForegroundColor DarkGray
}

# --- 4. Self-test ---
if (-not $SkipSelfTest) {
    Write-Host "[4/4] Rodando self-test de ponta a ponta..." -ForegroundColor Yellow
    & (Join-Path $ProjectRoot 'tests\Run-SelfTest.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Self-test falhou." }
} else {
    Write-Host "[4/4] Self-test ignorado." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Instalacao concluida. Proximo passo:" -ForegroundColor Green
Write-Host "    pwsh ./scripts/new-ca.ps1 -Store ./minha-pki" -ForegroundColor White
Write-Host ""
