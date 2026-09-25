# =====================================================================
#  CertForge — Common.ps1
#  Funções de infraestrutura: configuração, log, execução do OpenSSL.
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
# =====================================================================

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------
#  Log estruturado e colorido (níveis INFO/OK/WARN/ERRO).
# ---------------------------------------------------------------------
function Write-CfLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERRO', 'STEP')][string]$Level = 'INFO'
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $color = switch ($Level) {
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'ERRO' { 'Red' }
        'STEP' { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host ("[{0}] " -f $ts) -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-4} " -f $Level) -ForegroundColor $color -NoNewline
    Write-Host $Message
}

# ---------------------------------------------------------------------
#  Localiza o binário do OpenSSL (>= 3.0 recomendado).
# ---------------------------------------------------------------------
function Get-OpenSslPath {
    [CmdletBinding()]
    param()
    $cmd = Get-Command openssl -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "OpenSSL não foi encontrado no PATH. Instale o OpenSSL 3.x e tente novamente."
    }
    return $cmd.Source
}

# ---------------------------------------------------------------------
#  Executa o OpenSSL de forma segura, capturando saída e código de erro.
#  Lança exceção clara em caso de falha — nada de erro silencioso.
# ---------------------------------------------------------------------
function Invoke-OpenSsl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$StdIn,
        [switch]$AllowFailure
    )
    $openssl = Get-OpenSslPath
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $openssl
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()

    # IMPORTANTE: ler stdout e stderr de forma CONCORRENTE (async) para evitar
    # deadlock quando o buffer de um dos canais enche (ex.: progresso de keygen
    # RSA-4096 em stderr enquanto liamos stdout sincronamente).
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    if ($PSBoundParameters.ContainsKey('StdIn') -and $StdIn) {
        $proc.StandardInput.Write($StdIn)
    }
    $proc.StandardInput.Close()

    $proc.WaitForExit()
    $stdout = $outTask.GetAwaiter().GetResult()
    $stderr = $errTask.GetAwaiter().GetResult()

    $result = [pscustomobject]@{
        ExitCode = $proc.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
    if ($proc.ExitCode -ne 0 -and -not $AllowFailure) {
        throw "OpenSSL falhou (código $($proc.ExitCode)):`n$stderr"
    }
    return $result
}

# ---------------------------------------------------------------------
#  Carrega e valida a configuração JSON.
# ---------------------------------------------------------------------
function Get-CfConfig {
    [CmdletBinding()]
    param([string]$Path)
    if (-not $Path) {
        $Path = Join-Path (Split-Path -Parent $PSScriptRoot) '..\config\certforge.config.json'
        $Path = [System.IO.Path]::GetFullPath($Path)
    }
    if (-not (Test-Path $Path)) {
        throw "Arquivo de configuração não encontrado: $Path"
    }
    $cfg = Get-Content -Raw -Path $Path | ConvertFrom-Json
    return $cfg
}

# ---------------------------------------------------------------------
#  Resolve o caminho absoluto do "store" (repositório da CA).
# ---------------------------------------------------------------------
function Resolve-CfStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [string]$Override
    )
    $store = if ($Override) { $Override } else { $Config.paths.storeRoot }
    return [System.IO.Path]::GetFullPath($store)
}

# ---------------------------------------------------------------------
#  Valida a força de uma passphrase de proteção de chave.
# ---------------------------------------------------------------------
function Test-CfPassphrase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][SecureString]$Passphrase,
        [int]$MinLength = 16
    )
    $plain = [System.Net.NetworkCredential]::new('', $Passphrase).Password
    if ($plain.Length -lt $MinLength) {
        throw "A passphrase precisa ter pelo menos $MinLength caracteres (recebido: $($plain.Length))."
    }
    $classes = 0
    if ($plain -cmatch '[a-z]') { $classes++ }
    if ($plain -cmatch '[A-Z]') { $classes++ }
    if ($plain -match '\d')      { $classes++ }
    if ($plain -match '[^\w]')   { $classes++ }
    if ($classes -lt 3) {
        Write-CfLog "Passphrase fraca: use pelo menos 3 classes de caracteres (maiúsc./minúsc./dígitos/símbolos)." 'WARN'
    }
    return $true
}

# ---------------------------------------------------------------------
#  Converte SecureString em texto plano (uso interno, curto período).
# ---------------------------------------------------------------------
function ConvertFrom-CfSecure {
    [CmdletBinding()]
    param([Parameter(Mandatory)][SecureString]$Secure)
    return [System.Net.NetworkCredential]::new('', $Secure).Password
}

# ---------------------------------------------------------------------
#  Gera uma chave privada conforme algoritmo/força configurados,
#  opcionalmente cifrada em repouso com AES-256.
# ---------------------------------------------------------------------
function New-CfPrivateKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutFile,
        [ValidateSet('RSA', 'EC')][string]$Algorithm = 'RSA',
        [int]$Bits = 3072,
        [string]$Curve = 'P-384',
        [SecureString]$Passphrase,
        [string]$Cipher = 'aes-256-cbc'
    )
    $args = @('genpkey', '-out', $OutFile)
    if ($Algorithm -eq 'RSA') {
        $args += @('-algorithm', 'RSA', '-pkeyopt', "rsa_keygen_bits:$Bits")
    }
    else {
        $args += @('-algorithm', 'EC', '-pkeyopt', "ec_paramgen_curve:$Curve")
    }
    if ($Passphrase) {
        $pass = ConvertFrom-CfSecure $Passphrase
        $args += @("-$Cipher", '-pass', "pass:$pass")
    }
    Invoke-OpenSsl -Arguments $args | Out-Null
    # Restringe permissões no arquivo de chave (Windows ACL / Unix chmod).
    Protect-CfKeyFile -Path $OutFile
    return $OutFile
}

# ---------------------------------------------------------------------
#  Endurece permissões do arquivo de chave privada.
# ---------------------------------------------------------------------
function Protect-CfKeyFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    try {
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            $acl = Get-Acl $Path
            $acl.SetAccessRuleProtection($true, $false)
            $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                $me, 'FullControl', 'Allow')
            $acl.SetAccessRule($rule)
            Set-Acl -Path $Path -AclObject $acl
        }
        else {
            & chmod 600 $Path
        }
    }
    catch {
        Write-CfLog "Não foi possível endurecer permissões de $Path : $_" 'WARN'
    }
}
