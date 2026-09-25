#!/usr/bin/env pwsh
# =====================================================================
#  CertForge — new-ca.ps1
#  Cria a hierarquia PKI (CA Raiz + CA Intermediária).
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
#
#  Exemplo:
#    ./scripts/new-ca.ps1 -Store ./minha-pki
# =====================================================================
[CmdletBinding()]
param(
    [string]$Store,
    [string]$Config,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\CertForge.psd1') -Force

$cfg = Get-CfConfig -Path $Config
$storeRoot = if ($Store) { [System.IO.Path]::GetFullPath($Store) } `
             else { [System.IO.Path]::GetFullPath($cfg.paths.storeRoot) }

Write-Host ""
Write-Host "CertForge — criacao de Autoridade Certificadora" -ForegroundColor Cyan
Write-Host "Store: $storeRoot" -ForegroundColor DarkGray
Write-Host ""

function Get-Plain([SecureString]$s) { [System.Net.NetworkCredential]::new('', $s).Password }

$rootPass = Read-Host "Passphrase da CA RAIZ (min. $($cfg.security.minPassphraseLength) chars)" -AsSecureString
$rootPass2 = Read-Host "Confirme a passphrase da CA RAIZ" -AsSecureString
if ((Get-Plain $rootPass) -ne (Get-Plain $rootPass2)) { throw "Passphrases da raiz nao conferem." }

$intPass = Read-Host "Passphrase da CA INTERMEDIARIA" -AsSecureString
$intPass2 = Read-Host "Confirme a passphrase da CA INTERMEDIARIA" -AsSecureString
if ((Get-Plain $intPass) -ne (Get-Plain $intPass2)) { throw "Passphrases da intermediaria nao conferem." }

$result = New-CfAuthority -StoreRoot $storeRoot -Config $cfg `
    -RootPassphrase $rootPass -IntermediatePassphrase $intPass -Force:$Force

Write-Host ""
$result | Format-List
