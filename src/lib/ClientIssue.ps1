# =====================================================================
#  CertForge — ClientIssue.ps1
#  Emissão de certificados de CLIENTE (autenticação mútua TLS).
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
# =====================================================================

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------
#  New-CfClientCertificate — emite um certificado de cliente completo.
#  Retorna caminhos do certificado, chave, cadeia e pacote PKCS#12.
# ---------------------------------------------------------------------
function New-CfClientCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$CommonName,
        [Parameter(Mandatory)][SecureString]$IntermediatePassphrase,
        [string]$Email,
        [string]$Upn,                # userPrincipalName (mapeamento Entra ID / Azure)
        [string[]]$DnsNames,
        [SecureString]$ExportPassphrase,   # protege o .p12 exportado
        [int]$ValidityDays,
        [string]$CnfDir,
        [string]$OutputDir
    )
    if (-not $CnfDir) {
        $CnfDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\openssl'))
    }
    $intDir  = Join-Path $StoreRoot 'intermediate-ca'
    $intCnf  = Join-Path $CnfDir 'intermediate-ca.cnf'
    $intKey  = Join-Path $intDir 'private\intermediate-ca.key.pem'
    $intCert = Join-Path $intDir 'certs\intermediate-ca.cert.pem'
    $chain   = Join-Path $intDir 'certs\ca-chain.cert.pem'

    if (-not (Test-Path $intCert)) {
        throw "CA Intermediária não encontrada. Rode New-CfAuthority primeiro."
    }
    if (-not $ValidityDays) { $ValidityDays = $Config.validity.clientDays }

    $safeName = ($CommonName -replace '[^\w\.\-]', '_')
    $outDir = if ($OutputDir) { $OutputDir } else { Join-Path $StoreRoot "issued\$safeName" }
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    $clientKey = Join-Path $outDir "$safeName.key.pem"
    $clientCsr = Join-Path $outDir "$safeName.csr.pem"
    $clientCert = Join-Path $outDir "$safeName.cert.pem"
    $clientChain = Join-Path $outDir "$safeName.chain.pem"
    $clientCer = Join-Path $outDir "$safeName.cer"        # DER, para upload no Azure
    $clientP12 = Join-Path $outDir "$safeName.p12"

    # Monta o subjectAltName (crítico para o mapeamento no Entra ID).
    $sanParts = @()
    if ($Email) { $sanParts += "email:$Email" }
    if ($Upn)   { $sanParts += "otherName:msUPN;UTF8:$Upn" }
    foreach ($d in $DnsNames) { $sanParts += "DNS:$d" }
    if ($sanParts.Count -eq 0) { $sanParts += "email:$CommonName" }
    $env:CERTFORGE_CLIENT_SAN = ($sanParts -join ',')
    $env:CERTFORGE_CRL_URI = $Config.revocation.crlDistributionUri
    $env:CERTFORGE_INT_DIR = $intDir
    $env:CERTFORGE_COUNTRY = $Config.organization.country
    $env:CERTFORGE_STATE   = $Config.organization.state
    $env:CERTFORGE_ORG     = $Config.organization.org
    $env:CERTFORGE_OU      = $Config.organization.orgUnit
    $env:CERTFORGE_INT_CN  = $Config.organization.intermediateCommonName

    Write-CfLog "Gerando chave do cliente '$CommonName' ($($Config.keys.clientAlgorithm)-$($Config.keys.clientBits))..." 'STEP'
    New-CfPrivateKey -OutFile $clientKey -Algorithm $Config.keys.clientAlgorithm `
        -Bits $Config.keys.clientBits | Out-Null

    # Subject DN do cliente.
    $subj = "/C=$($Config.organization.country)/ST=$($Config.organization.state)/O=$($Config.organization.org)/OU=$($Config.organization.orgUnit)/CN=$CommonName"
    if ($Email) { $subj += "/emailAddress=$Email" }

    Write-CfLog "Gerando CSR do cliente..." 'STEP'
    Invoke-OpenSsl -Arguments @(
        'req', '-config', $intCnf, '-new', '-sha384', '-key', $clientKey,
        '-subj', $subj, '-out', $clientCsr
    ) | Out-Null

    Write-CfLog "CA Intermediária assinando o certificado do cliente..." 'STEP'
    $intPass = ConvertFrom-CfSecure $IntermediatePassphrase
    Invoke-OpenSsl -Arguments @(
        'ca', '-config', $intCnf, '-extensions', 'client_cert',
        '-days', "$ValidityDays", '-notext', '-md', 'sha384',
        '-in', $clientCsr, '-out', $clientCert, '-passin', "pass:$intPass", '-batch'
    ) | Out-Null

    # Cadeia completa (cliente + intermediária + raiz).
    $clientPem = Get-Content -Raw $clientCert
    $chainPem = Get-Content -Raw $chain
    Set-Content -Path $clientChain -Value ($clientPem + $chainPem) -NoNewline

    # Versão DER (.cer) — formato aceito no upload de credencial do Azure.
    Invoke-OpenSsl -Arguments @('x509', '-in', $clientCert, '-outform', 'DER', '-out', $clientCer) | Out-Null

    # Pacote PKCS#12 (chave + cert + cadeia) para importar no Windows/apps.
    Write-CfLog "Empacotando PKCS#12..." 'STEP'
    $p12Args = @('pkcs12', '-export', '-inkey', $clientKey, '-in', $clientCert,
        '-certfile', $chain, '-out', $clientP12, '-name', $CommonName)
    if ($ExportPassphrase) {
        $exp = ConvertFrom-CfSecure $ExportPassphrase
        $p12Args += @('-passout', "pass:$exp")
    } else {
        $p12Args += @('-passout', 'pass:')
    }
    Invoke-OpenSsl -Arguments $p12Args | Out-Null

    $fp = Get-CfFingerprint -CertPath $clientCert
    $serialR = Invoke-OpenSsl -Arguments @('x509', '-in', $clientCert, '-noout', '-serial')
    $serial = ($serialR.StdOut -replace 'serial=', '').Trim()

    if ($Config.security.enforceLedger) {
        Add-CfLedgerEntry -StoreRoot $StoreRoot -Action 'ISSUE' `
            -Subject $CommonName -Serial $serial -Fingerprint $fp | Out-Null
    }

    Write-CfLog "Certificado emitido para '$CommonName' (serial $serial)." 'OK'
    Write-CfLog "  Fingerprint SHA-256: $fp" 'INFO'

    return [pscustomobject]@{
        CommonName  = $CommonName
        Serial      = $serial
        Fingerprint = $fp
        KeyFile     = $clientKey
        CertFile    = $clientCert
        ChainFile   = $clientChain
        DerFile     = $clientCer
        Pkcs12File  = $clientP12
        OutputDir   = $outDir
    }
}
