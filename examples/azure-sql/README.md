# Exemplo — Azure SQL Database (certificado no Microsoft Entra ID)

No Azure SQL, a autenticação por certificado acontece através de um
**Service Principal** (aplicativo) registrado no **Microsoft Entra ID**: você
sobe a parte **pública** do certificado no App Registration e o cliente
autentica com a **chave privada**. Sem a chave, não há token — e sem token,
não há conexão.

## 1. Emitir o certificado + gerar o bundle

```powershell
pwsh ./scripts/issue-client.ps1 `
    -CommonName "svc-bi" -Upn "svc-bi@empresa.com" `
    -Store ./minha-pki `
    -AzureSql -SqlServer "meusrv.database.windows.net" -Database "vendas" `
    -AppDisplayName "CertForge-BI" -TenantId "<SEU_TENANT_ID>"
```

Cria, em `minha-pki/issued/svc-bi/azure-sql/`:

- `CertForge-BI.cer` — chave pública para o App Registration
- `setup-azure.sh` — roteiro Azure CLI
- `ConnectExample.cs` — exemplo de conexão .NET
- `odbc-connection-string.txt` — string ODBC

## 2. Registrar o app e anexar o certificado

```bash
az login
az ad app create --display-name "CertForge-BI"
APP_ID=$(az ad app list --display-name "CertForge-BI" --query "[0].appId" -o tsv)
az ad app credential reset --id $APP_ID --cert "@CertForge-BI.cer" --append
az ad sp create --id $APP_ID
```

## 3. Dar acesso ao Service Principal no banco

Conecte-se ao Azure SQL como administrador Entra ID e rode:

```sql
CREATE USER [CertForge-BI] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [CertForge-BI];
ALTER ROLE db_datawriter ADD MEMBER [CertForge-BI];
```

## 4. Conectar com o certificado (.NET)

```csharp
var cert = new X509Certificate2("svc-bi.p12", "<SENHA_DO_P12>");
var cred = new ClientCertificateCredential(tenantId, appId, cert);
var token = cred.GetToken(new TokenRequestContext(
    new[] { "https://database.windows.net/.default" }));

var conn = new SqlConnection("Server=tcp:meusrv.database.windows.net,1433;Database=vendas;Encrypt=true");
conn.AccessToken = token.Token;
conn.Open();   // conectado — provado pela chave privada do certificado
```

Ou via ODBC:

```
Driver={ODBC Driver 18 for SQL Server};Server=tcp:meusrv.database.windows.net,1433;
Database=vendas;Authentication=ActiveDirectoryServicePrincipal;Encrypt=yes;UID=<APP_ID>;
```
