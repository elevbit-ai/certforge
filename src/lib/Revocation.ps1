# =====================================================================
#  CertForge — Revocation.ps1
#  Revogação de certificados e publicação de CRL.
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
# =====================================================================

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------
#  Revoke-CfCertificate — revoga um certificado emitido e regenera a CRL.
# ---------------------------------------------------------------------
function Revoke-CfCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][SecureString]$IntermediatePassphrase,
        [Parameter(Mandatory, ParameterSetName = 'ByFile')][string]$CertFile,
        [Parameter(Mandatory, ParameterSetName = 'BySerial')][string]$Serial,
        [ValidateSet('unspecified','keyCompromise','caCompromise','affiliationChanged',
                     'superseded','cessationOfOperation','certificateHold')]
        [string]$Reason = 'unspecified',
        [string]$CnfDir
    )
    if (-not $CnfDir) {
        $CnfDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\openssl'))
    }
    $intDir = Join-Path $StoreRoot 'intermediate-ca'
    $intCnf = Join-Path $CnfDir 'intermediate-ca.cnf'
    $env:CERTFORGE_INT_DIR = $intDir
    $intPass = ConvertFrom-CfSecure $IntermediatePassphrase

    if ($PSCmdlet.ParameterSetName -eq 'BySerial') {
        $CertFile = Join-Path $intDir ("newcerts\{0}.pem" -f $Serial.ToUpper())
        if (-not (Test-Path $CertFile)) {
            throw "Certificado com serial '$Serial' não encontrado em $CertFile."
        }
    }

    $subjR = Invoke-OpenSsl -Arguments @('x509', '-in', $CertFile, '-noout', '-subject')
    $serialR = Invoke-OpenSsl -Arguments @('x509', '-in', $CertFile, '-noout', '-serial')
    $subject = ($subjR.StdOut -replace 'subject=', '').Trim()
    $serial = ($serialR.StdOut -replace 'serial=', '').Trim()

    Write-CfLog "Revogando '$subject' (serial $serial, motivo: $Reason)..." 'STEP'
    Invoke-OpenSsl -Arguments @(
        'ca', '-config', $intCnf, '-revoke', $CertFile,
        '-crl_reason', $Reason, '-passin', "pass:$intPass", '-batch'
    ) | Out-Null

    $crl = Publish-CfCrl -StoreRoot $StoreRoot -Config $Config `
        -IntermediatePassphrase $IntermediatePassphrase -CnfDir $CnfDir

    if ($Config.security.enforceLedger) {
        Add-CfLedgerEntry -StoreRoot $StoreRoot -Action 'REVOKE' `
            -Subject $subject -Serial $serial | Out-Null
    }
    Write-CfLog "Certificado revogado e CRL atualizada: $crl" 'OK'
    return $crl
}

# ---------------------------------------------------------------------
#  Publish-CfCrl — (re)gera a Lista de Revogação de Certificados.
# ---------------------------------------------------------------------
function Publish-CfCrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][SecureString]$IntermediatePassphrase,
        [string]$CnfDir
    )
    if (-not $CnfDir) {
        $CnfDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\openssl'))
    }
    $intDir = Join-Path $StoreRoot 'intermediate-ca'
    $intCnf = Join-Path $CnfDir 'intermediate-ca.cnf'
    $crlPem = Join-Path $intDir 'crl\intermediate-ca.crl.pem'
    $env:CERTFORGE_INT_DIR = $intDir
    $intPass = ConvertFrom-CfSecure $IntermediatePassphrase

    Invoke-OpenSsl -Arguments @(
        'ca', '-config', $intCnf, '-gencrl', '-out', $crlPem,
        '-passin', "pass:$intPass"
    ) | Out-Null

    if ($Config.security.enforceLedger) {
        Add-CfLedgerEntry -StoreRoot $StoreRoot -Action 'CRL_PUBLISHED' -Subject 'intermediate-ca.crl.pem' | Out-Null
    }
    return $crlPem
}
