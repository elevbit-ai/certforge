# =====================================================================
#  CertForge — OracleWallet.ps1
#  Prepara os artefatos para autenticar em Oracle Database via TCPS
#  (TLS mútuo com Oracle Wallet).
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
# =====================================================================

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------
#  New-CfOracleWalletBundle — gera o pacote para a Oracle Wallet do
#  cliente, mais os arquivos sqlnet.ora / tnsnames.ora e os comandos
#  orapki prontos para converter em wallet auto-login (cwallet.sso).
# ---------------------------------------------------------------------
function New-CfOracleWalletBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ClientResult,       # saída de New-CfClientCertificate
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][SecureString]$WalletPassphrase,
        [string]$DbHost = 'oracle.exemplo.com',
        [int]$DbPort = 2484,
        [string]$ServiceName = 'ORCLPDB1',
        [string]$OutputDir
    )
    $intDir = Join-Path $StoreRoot 'intermediate-ca'
    $chain  = Join-Path $intDir 'certs\ca-chain.cert.pem'
    $outDir = if ($OutputDir) { $OutputDir } else { Join-Path $ClientResult.OutputDir 'oracle' }
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    $walletP12 = Join-Path $outDir 'ewallet.p12.source'
    Copy-Item $ClientResult.Pkcs12File $walletP12 -Force
    Copy-Item $chain (Join-Path $outDir 'ca-chain.cert.pem') -Force

    $pass = ConvertFrom-CfSecure $WalletPassphrase

    # sqlnet.ora — exige TLS e aponta para a wallet.
    $sqlnet = @"
# CertForge — sqlnet.ora (cliente Oracle, TCPS)
WALLET_LOCATION =
  (SOURCE =
    (METHOD = FILE)
    (METHOD_DATA = (DIRECTORY = $($outDir -replace '\\','/')))
  )
SSL_CLIENT_AUTHENTICATION = TRUE
SSL_VERSION = 1.2
SQLNET.AUTHENTICATION_SERVICES = (TCPS)
SSL_SERVER_DN_MATCH = TRUE
"@
    Set-Content -Path (Join-Path $outDir 'sqlnet.ora') -Value $sqlnet

    # tnsnames.ora — descritor de conexão TCPS.
    $tns = @"
# CertForge — tnsnames.ora
CERTFORGE_TCPS =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = $DbHost)(PORT = $DbPort))
    (CONNECT_DATA = (SERVICE_NAME = $ServiceName))
    (SECURITY = (SSL_SERVER_CERT_DN = "CN=$DbHost"))
  )
"@
    Set-Content -Path (Join-Path $outDir 'tnsnames.ora') -Value $tns

    # Roteiro orapki (executado numa máquina com Oracle client instalado).
    $orapki = @"
# ============================================================
# CertForge — construir a Oracle Wallet a partir do PKCS#12
# Requer Oracle client (orapki) instalado nesta máquina.
# ============================================================

# 1) Criar wallet auto-login (gera ewallet.p12 e cwallet.sso)
orapki wallet create -wallet "$outDir" -pwd "$pass" -auto_login

# 2) Importar a cadeia da CA (confiança no servidor)
orapki wallet add -wallet "$outDir" -trusted_cert -cert "$($outDir)\ca-chain.cert.pem" -pwd "$pass"

# 3) Importar a identidade do cliente (chave + cert) a partir do PKCS#12
#    Em versões recentes:
orapki wallet import_pkcs12 -wallet "$outDir" -pwd "$pass" -pkcs12file "$walletP12" -pkcs12pwd "<SENHA_DO_P12>"

# 4) Conferir o conteúdo
orapki wallet display -wallet "$outDir" -pwd "$pass"

# ------------------------------------------------------------
# No SERVIDOR Oracle, mapear o certificado a um usuário:
#   CREATE USER app_cliente IDENTIFIED EXTERNALLY
#     AS 'CN=$($ClientResult.CommonName),OU=$($null),O=$($null)';
#   GRANT CREATE SESSION TO app_cliente;
# E configurar o listener para TCPS na porta $DbPort.
# ------------------------------------------------------------

# Testar a conexão (após configurar TNS_ADMIN=$outDir):
#   sqlplus /@CERTFORGE_TCPS
"@
    Set-Content -Path (Join-Path $outDir 'build-wallet.orapki.txt') -Value $orapki

    Write-CfLog "Bundle Oracle gerado em: $outDir" 'OK'
    Write-CfLog "  Configure TNS_ADMIN=$outDir e rode os comandos em build-wallet.orapki.txt" 'INFO'

    return [pscustomobject]@{
        OutputDir  = $outDir
        SqlnetOra  = (Join-Path $outDir 'sqlnet.ora')
        TnsnamesOra = (Join-Path $outDir 'tnsnames.ora')
        OrapkiScript = (Join-Path $outDir 'build-wallet.orapki.txt')
    }
}
