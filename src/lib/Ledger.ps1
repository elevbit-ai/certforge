# =====================================================================
#  CertForge — Ledger.ps1
#  Livro-razão de auditoria à prova de adulteração (hash-chaining).
#  Cada evento carrega o hash do evento anterior; qualquer alteração
#  retroativa quebra a cadeia inteira e é detectada em Test-CfLedger.
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
# =====================================================================

Set-StrictMode -Version Latest

$script:CfGenesisHash = '0000000000000000000000000000000000000000000000000000000000000000'

function Get-CfLedgerPath {
    param([Parameter(Mandatory)][string]$StoreRoot)
    return (Join-Path $StoreRoot 'ledger.jsonl')
}

# Normaliza um timestamp para string ISO-8601 UTC canônica.
# Necessário porque ConvertFrom-Json converte a string ISO gravada em
# [DateTime]; sem normalizar, a re-serialização divergiria (perda de
# zeros à direita nos segundos) e quebraria o hash de forma intermitente.
function ConvertTo-CfCanonicalTimestamp {
    param($Value)
    if ($Value -is [datetime]) {
        return ([datetime]$Value).ToUniversalTime().ToString('o')
    }
    if ($Value -is [System.DateTimeOffset]) {
        return ([System.DateTimeOffset]$Value).UtcDateTime.ToString('o')
    }
    return [string]$Value
}

# Calcula o hash canônico de um evento (SHA-256 sobre JSON ordenado).
# Todos os campos são normalizados para string (exceto seq) de modo que
# o hash independa de o valor vir da gravação (string) ou da leitura
# via ConvertFrom-Json (que pode tipar datas/números).
function Get-CfEventHash {
    param(
        [Parameter(Mandatory)][hashtable]$Event,
        [Parameter(Mandatory)][string]$PrevHash
    )
    $canonical = [ordered]@{
        seq         = [int]$Event.seq
        timestamp   = (ConvertTo-CfCanonicalTimestamp $Event.timestamp)
        action      = [string]$Event.action
        subject     = [string]$Event.subject
        serial      = [string]$Event.serial
        fingerprint = [string]$Event.fingerprint
        actor       = [string]$Event.actor
        prevHash    = [string]$PrevHash
    }
    $json = ($canonical | ConvertTo-Json -Compress -Depth 6)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
    } finally { $sha.Dispose() }
    return -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
}

# Anexa um evento ao ledger, encadeado ao último hash.
function Add-CfLedgerEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][ValidateSet('CA_CREATED','ISSUE','REVOKE','RENEW','CRL_PUBLISHED')][string]$Action,
        [string]$Subject = '',
        [string]$Serial = '',
        [string]$Fingerprint = '',
        [string]$Actor = $env:USERNAME
    )
    $path = Get-CfLedgerPath -StoreRoot $StoreRoot
    $prevHash = $script:CfGenesisHash
    $seq = 0
    if (Test-Path $path) {
        $lines = @(Get-Content -Path $path | Where-Object { $_.Trim() })
        if ($lines.Count -gt 0) {
            $last = $lines[-1] | ConvertFrom-Json
            $prevHash = $last.hash
            $seq = [int]$last.seq + 1
        }
    }
    $event = @{
        seq         = $seq
        timestamp   = (Get-Date).ToUniversalTime().ToString('o')
        action      = $Action
        subject     = $Subject
        serial      = $Serial
        fingerprint = $Fingerprint
        actor       = $Actor
    }
    $hash = Get-CfEventHash -Event $event -PrevHash $prevHash
    $record = [ordered]@{
        seq         = $event.seq
        timestamp   = $event.timestamp
        action      = $event.action
        subject     = $event.subject
        serial      = $event.serial
        fingerprint = $event.fingerprint
        actor       = $event.actor
        prevHash    = $prevHash
        hash        = $hash
    }
    Add-Content -Path $path -Value ($record | ConvertTo-Json -Compress -Depth 6)
    return $record
}

# Verifica a integridade da cadeia inteira. Retorna $true se íntegra.
function Test-CfLedger {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot)
    $path = Get-CfLedgerPath -StoreRoot $StoreRoot
    if (-not (Test-Path $path)) {
        Write-CfLog "Ledger inexistente em $path" 'WARN'
        return $false
    }
    $prevHash = $script:CfGenesisHash
    $expectedSeq = 0
    $ok = $true
    $lineNo = 0
    foreach ($line in Get-Content -Path $path) {
        $lineNo++
        if (-not $line.Trim()) { continue }
        $rec = $line | ConvertFrom-Json
        if ([int]$rec.seq -ne $expectedSeq) {
            Write-CfLog "Sequência quebrada na linha $lineNo (esperado $expectedSeq, encontrado $($rec.seq))." 'ERRO'
            $ok = $false
        }
        if ($rec.prevHash -ne $prevHash) {
            Write-CfLog "Elo rompido na linha $lineNo (prevHash não confere)." 'ERRO'
            $ok = $false
        }
        $event = @{
            seq = $rec.seq; timestamp = $rec.timestamp; action = $rec.action
            subject = $rec.subject; serial = $rec.serial
            fingerprint = $rec.fingerprint; actor = $rec.actor
        }
        $recomputed = Get-CfEventHash -Event $event -PrevHash $rec.prevHash
        if ($recomputed -ne $rec.hash) {
            Write-CfLog "Hash adulterado na linha $lineNo." 'ERRO'
            $ok = $false
        }
        $prevHash = $rec.hash
        $expectedSeq++
    }
    if ($ok) {
        Write-CfLog "Ledger íntegro: $expectedSeq evento(s) verificado(s). Selo final: $prevHash" 'OK'
    }
    return $ok
}
