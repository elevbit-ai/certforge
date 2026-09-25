# =====================================================================
#  CertForge — WindowsStore.ps1
#  Importa a identidade do cliente no Windows Certificate Store com a
#  chave privada NÃO-EXPORTÁVEL e, opcionalmente, selada ao TPM (KSP).
#  Assim, mesmo um atacante com acesso ao PC não consegue COPIAR a chave.
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
# =====================================================================

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------
#  Import-CfClientToWindowsStore — importa o .p12 como não-exportável.
#  -BindToTpm move a chave para o provedor TPM (Microsoft Platform Crypto
#   Provider), amarrando-a ao hardware desta máquina.
# ---------------------------------------------------------------------
function Import-CfClientToWindowsStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Pkcs12File,
        [Parameter(Mandatory)][SecureString]$Pkcs12Passphrase,
        [ValidateSet('CurrentUser', 'LocalMachine')][string]$StoreLocation = 'CurrentUser',
        [switch]$BindToTpm
    )
    if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {
        throw "Import-CfClientToWindowsStore só funciona no Windows."
    }
    $storePath = "Cert:\$StoreLocation\My"

    Write-CfLog "Importando identidade no store $storePath (não-exportável)..." 'STEP'
    $imported = Import-PfxCertificate -FilePath $Pkcs12File -CertStoreLocation $storePath `
        -Password $Pkcs12Passphrase -Exportable:$false

    Write-CfLog "Importado. Thumbprint: $($imported.Thumbprint)" 'OK'

    if ($BindToTpm) {
        Write-CfLog "Selando a chave ao TPM (Microsoft Platform Crypto Provider)..." 'STEP'
        try {
            $tmp = Join-Path $env:TEMP ("cf-tpm-{0}.p12" -f ([guid]::NewGuid()))
            Export-PfxCertificate -Cert $imported -FilePath $tmp -Password $Pkcs12Passphrase -ErrorAction Stop | Out-Null
            & certutil -f -importpfx -csp "Microsoft Platform Crypto Provider" $tmp 2>&1 | Out-Null
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            Write-CfLog "Chave vinculada ao TPM desta máquina." 'OK'
        }
        catch {
            Write-CfLog "Não foi possível selar ao TPM (TPM 2.0 presente?): $_" 'WARN'
        }
    }
    return $imported
}
