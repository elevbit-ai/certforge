# =====================================================================
#  CertForge — CaEngine.ps1
#  Criação da hierarquia PKI de dois níveis: Raiz (offline) + Emissora.
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
# =====================================================================

Set-StrictMode -Version Latest

# Prepara o layout de diretórios exigido pelo comando `openssl ca`.
function Initialize-CaLayout {
    param([Parameter(Mandatory)][string]$Dir)
    foreach ($sub in 'certs', 'crl', 'newcerts', 'private', 'csr') {
        $p = Join-Path $Dir $sub
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
    $index = Join-Path $Dir 'index.txt'
    if (-not (Test-Path $index)) { New-Item -ItemType File -Path $index -Force | Out-Null }
    $serial = Join-Path $Dir 'serial'
    if (-not (Test-Path $serial)) { Set-Content -Path $serial -Value '1000' -NoNewline }
    $crlnum = Join-Path $Dir 'crlnumber'
    if (-not (Test-Path $crlnum)) { Set-Content -Path $crlnum -Value '1000' -NoNewline }
}

# Exporta variáveis de ambiente que os arquivos .cnf consomem.
function Set-CfCnfEnvironment {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$RootDir,
        [Parameter(Mandatory)][string]$IntDir
    )
    $env:CERTFORGE_ROOT_DIR = $RootDir
    $env:CERTFORGE_INT_DIR  = $IntDir
    $env:CERTFORGE_COUNTRY  = $Config.organization.country
    $env:CERTFORGE_STATE    = $Config.organization.state
    $env:CERTFORGE_ORG      = $Config.organization.org
    $env:CERTFORGE_OU       = $Config.organization.orgUnit
    $env:CERTFORGE_ROOT_CN  = $Config.organization.rootCommonName
    $env:CERTFORGE_INT_CN   = $Config.organization.intermediateCommonName
    $env:CERTFORGE_CRL_URI  = $Config.revocation.crlDistributionUri
    # Placeholder para o SAN de cliente. O OpenSSL 3.x expande TODAS as
    # variaveis $ENV:: ao carregar o .cnf, mesmo secoes nao usadas; sem
    # este valor a criacao da CA falharia. E sobrescrito na emissao.
    if (-not $env:CERTFORGE_CLIENT_SAN) { $env:CERTFORGE_CLIENT_SAN = 'email:placeholder@certforge.local' }
}

# Retorna o fingerprint SHA-256 de um certificado.
function Get-CfFingerprint {
    param([Parameter(Mandatory)][string]$CertPath)
    $r = Invoke-OpenSsl -Arguments @('x509', '-in', $CertPath, '-noout', '-fingerprint', '-sha256')
    return ($r.StdOut -replace '.*=', '').Trim()
}

# ---------------------------------------------------------------------
#  New-CfAuthority — cria toda a hierarquia PKI.
# ---------------------------------------------------------------------
function New-CfAuthority {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][SecureString]$RootPassphrase,
        [Parameter(Mandatory)][SecureString]$IntermediatePassphrase,
        [string]$CnfDir,
        [switch]$Force
    )
    if (-not $CnfDir) {
        $CnfDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\openssl'))
    }
    $rootDir = Join-Path $StoreRoot 'root-ca'
    $intDir  = Join-Path $StoreRoot 'intermediate-ca'

    if ((Test-Path (Join-Path $rootDir 'certs\root-ca.cert.pem')) -and -not $Force) {
        throw "Já existe uma CA em '$StoreRoot'. Use -Force para recriar (DESTRUTIVO)."
    }

    Write-CfLog "Validando passphrases..." 'STEP'
    Test-CfPassphrase -Passphrase $RootPassphrase -MinLength $Config.security.minPassphraseLength | Out-Null
    Test-CfPassphrase -Passphrase $IntermediatePassphrase -MinLength $Config.security.minPassphraseLength | Out-Null

    Write-CfLog "Preparando diretórios da CA em $StoreRoot" 'STEP'
    Initialize-CaLayout -Dir $rootDir
    Initialize-CaLayout -Dir $intDir
    Set-CfCnfEnvironment -Config $Config -RootDir $rootDir -IntDir $intDir

    $rootCnf = Join-Path $CnfDir 'root-ca.cnf'
    $intCnf  = Join-Path $CnfDir 'intermediate-ca.cnf'
    $rootKey = Join-Path $rootDir 'private\root-ca.key.pem'
    $rootCert = Join-Path $rootDir 'certs\root-ca.cert.pem'
    $intKey  = Join-Path $intDir 'private\intermediate-ca.key.pem'
    $intCsr  = Join-Path $intDir 'csr\intermediate-ca.csr.pem'
    $intCert = Join-Path $intDir 'certs\intermediate-ca.cert.pem'
    $chain   = Join-Path $intDir 'certs\ca-chain.cert.pem'

    # --- 1. Chave + certificado raiz (auto-assinado) ---
    Write-CfLog "Gerando chave da CA Raiz ($($Config.keys.rootAlgorithm)-$($Config.keys.rootBits))..." 'STEP'
    New-CfPrivateKey -OutFile $rootKey -Algorithm $Config.keys.rootAlgorithm `
        -Bits $Config.keys.rootBits -Passphrase $RootPassphrase `
        -Cipher $Config.security.keyEncryptionCipher | Out-Null

    Write-CfLog "Auto-assinando o certificado da CA Raiz..." 'STEP'
    $rootPass = ConvertFrom-CfSecure $RootPassphrase
    Invoke-OpenSsl -Arguments @(
        'req', '-config', $rootCnf, '-key', $rootKey, '-new', '-x509',
        '-days', "$($Config.validity.rootDays)", '-sha384', '-extensions', 'v3_ca',
        '-out', $rootCert, '-passin', "pass:$rootPass"
    ) | Out-Null

    # --- 2. Chave + CSR da intermediária ---
    Write-CfLog "Gerando chave da CA Intermediária ($($Config.keys.intermediateAlgorithm)-$($Config.keys.intermediateBits))..." 'STEP'
    New-CfPrivateKey -OutFile $intKey -Algorithm $Config.keys.intermediateAlgorithm `
        -Bits $Config.keys.intermediateBits -Passphrase $IntermediatePassphrase `
        -Cipher $Config.security.keyEncryptionCipher | Out-Null

    Write-CfLog "Gerando CSR da CA Intermediária..." 'STEP'
    $intPass = ConvertFrom-CfSecure $IntermediatePassphrase
    Invoke-OpenSsl -Arguments @(
        'req', '-config', $intCnf, '-new', '-sha384', '-key', $intKey,
        '-out', $intCsr, '-passin', "pass:$intPass"
    ) | Out-Null

    # --- 3. Raiz assina a intermediária ---
    Write-CfLog "CA Raiz assinando a CA Intermediária..." 'STEP'
    Invoke-OpenSsl -Arguments @(
        'ca', '-config', $rootCnf, '-extensions', 'v3_intermediate_ca',
        '-days', "$($Config.validity.intermediateDays)", '-notext', '-md', 'sha384',
        '-in', $intCsr, '-out', $intCert, '-passin', "pass:$rootPass", '-batch'
    ) | Out-Null

    # --- 4. Verificar a cadeia ---
    Write-CfLog "Verificando a cadeia de confiança..." 'STEP'
    Invoke-OpenSsl -Arguments @('verify', '-CAfile', $rootCert, $intCert) | Out-Null

    # --- 5. Montar o bundle da cadeia (intermediária + raiz) ---
    $intPem  = Get-Content -Raw $intCert
    $rootPem = Get-Content -Raw $rootCert
    Set-Content -Path $chain -Value ($intPem + $rootPem) -NoNewline

    $rootFp = Get-CfFingerprint -CertPath $rootCert
    $intFp  = Get-CfFingerprint -CertPath $intCert

    # --- 6. Registrar no ledger ---
    if ($Config.security.enforceLedger) {
        Add-CfLedgerEntry -StoreRoot $StoreRoot -Action 'CA_CREATED' `
            -Subject $Config.organization.rootCommonName -Fingerprint $rootFp | Out-Null
        Add-CfLedgerEntry -StoreRoot $StoreRoot -Action 'CA_CREATED' `
            -Subject $Config.organization.intermediateCommonName -Fingerprint $intFp | Out-Null
    }

    Write-CfLog "Hierarquia PKI criada com sucesso." 'OK'
    Write-CfLog "  Raiz         : $rootFp" 'INFO'
    Write-CfLog "  Intermediária: $intFp" 'INFO'
    Write-CfLog "IMPORTANTE: mova '$rootKey' para armazenamento OFFLINE." 'WARN'

    return [pscustomobject]@{
        StoreRoot        = $StoreRoot
        RootCert         = $rootCert
        RootFingerprint  = $rootFp
        IntermediateCert = $intCert
        IntermediateFingerprint = $intFp
        ChainFile        = $chain
    }
}
