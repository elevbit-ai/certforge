# =====================================================================
#  CertForge — AzureSql.ps1
#  Prepara autenticação em Azure SQL Database via credencial de
#  CERTIFICADO de um Service Principal no Microsoft Entra ID.
#  Autor: Joaquim Pedro de Morais Filho <j360074@hotmail.com>
# =====================================================================

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------
#  New-CfAzureSqlBundle — gera os artefatos e comandos para registrar o
#  certificado como credencial de um app (service principal) e conectar
#  no Azure SQL usando esse certificado.
# ---------------------------------------------------------------------
function New-CfAzureSqlBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ClientResult,        # saída de New-CfClientCertificate
        [Parameter(Mandatory)][string]$SqlServer,   # ex: meuservidor.database.windows.net
        [Parameter(Mandatory)][string]$Database,
        [string]$AppDisplayName = 'CertForge-Client',
        [string]$TenantId = '<SEU_TENANT_ID>',
        [string]$OutputDir
    )
    $outDir = if ($OutputDir) { $OutputDir } else { Join-Path $ClientResult.OutputDir 'azure-sql' }
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    # O Azure aceita a chave pública em PEM/DER (.cer) para credencial de app.
    Copy-Item $ClientResult.DerFile (Join-Path $outDir "$($AppDisplayName).cer") -Force

    # Roteiro Azure CLI: cria o app, anexa o certificado e cria o SP.
    $azScript = @"
# ============================================================
# CertForge — Azure SQL via certificado (Service Principal)
# Requer Azure CLI (az) autenticado: az login
# ============================================================

# 1) Criar o registro de aplicativo (App Registration)
az ad app create --display-name "$AppDisplayName"

# 2) Capturar o appId gerado
APP_ID=`$(az ad app list --display-name "$AppDisplayName" --query "[0].appId" -o tsv)

# 3) Anexar o CERTIFICADO como credencial (chave pública)
az ad app credential reset --id `$APP_ID --cert "@$($outDir)\$($AppDisplayName).cer" --append

# 4) Criar o Service Principal para o app
az ad sp create --id `$APP_ID

# ------------------------------------------------------------
# 5) No Azure SQL, criar o usuário externo e conceder acesso.
#    Conecte-se ao banco como administrador Entra ID e rode:
#
#    CREATE USER [$AppDisplayName] FROM EXTERNAL PROVIDER;
#    ALTER ROLE db_datareader ADD MEMBER [$AppDisplayName];
#    ALTER ROLE db_datawriter ADD MEMBER [$AppDisplayName];
# ------------------------------------------------------------
"@
    Set-Content -Path (Join-Path $outDir 'setup-azure.sh') -Value $azScript

    # Exemplo de conexão .NET (ActiveDirectoryServicePrincipal + certificado).
    $conn = @"
// CertForge — conexão .NET no Azure SQL usando certificado do SP
// Requer: Microsoft.Data.SqlClient + Azure.Identity

using Azure.Identity;
using Microsoft.Data.SqlClient;
using System.Security.Cryptography.X509Certificates;

var cert = new X509Certificate2("$($ClientResult.Pkcs12File -replace '\\','\\\\')", "<SENHA_DO_P12>");
var cred = new ClientCertificateCredential(
    tenantId: "$TenantId",
    clientId: "<APP_ID>",
    clientCertificate: cert);

var token = cred.GetToken(
    new Azure.Core.TokenRequestContext(
        new[] { "https://database.windows.net/.default" }));

var csb = new SqlConnectionStringBuilder {
    DataSource = "$SqlServer",
    InitialCatalog = "$Database",
    Encrypt = true
};
using var conn = new SqlConnection(csb.ConnectionString) {
    AccessToken = token.Token
};
conn.Open();
Console.WriteLine("Conectado ao Azure SQL via certificado.");
"@
    Set-Content -Path (Join-Path $outDir 'ConnectExample.cs') -Value $conn

    # String de conexão ODBC (driver 18) para ferramentas.
    $odbc = "Driver={ODBC Driver 18 for SQL Server};Server=tcp:$SqlServer,1433;Database=$Database;Authentication=ActiveDirectoryServicePrincipal;Encrypt=yes;UID=<APP_ID>;"
    Set-Content -Path (Join-Path $outDir 'odbc-connection-string.txt') -Value $odbc

    Write-CfLog "Bundle Azure SQL gerado em: $outDir" 'OK'
    Write-CfLog "  Suba $($AppDisplayName).cer no App Registration (setup-azure.sh)." 'INFO'

    return [pscustomobject]@{
        OutputDir   = $outDir
        CerFile     = (Join-Path $outDir "$($AppDisplayName).cer")
        AzureScript = (Join-Path $outDir 'setup-azure.sh')
        DotNetExample = (Join-Path $outDir 'ConnectExample.cs')
    }
}
