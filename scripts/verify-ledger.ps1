#!/usr/bin/env pwsh
# =====================================================================
#  CertForge — verify-ledger.ps1
#  Verifica a integridade do livro-razao de auditoria (hash-chain).
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
# =====================================================================
[CmdletBinding()]
param(
    [string]$Store,
    [string]$Config
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\CertForge.psd1') -Force

$cfg = Get-CfConfig -Path $Config
$storeRoot = if ($Store) { [System.IO.Path]::GetFullPath($Store) } `
             else { [System.IO.Path]::GetFullPath($cfg.paths.storeRoot) }

$ok = Test-CfLedger -StoreRoot $storeRoot
if (-not $ok) { exit 1 }
