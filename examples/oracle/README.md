# Exemplo — Oracle Database (TCPS / TLS mútuo)

Este guia mostra como usar um certificado emitido pelo CertForge para
autenticar num Oracle Database via **TCPS** (Oracle Net sobre TLS), com
autenticação **mútua** (o servidor exige o certificado do cliente).

## 1. Emitir o certificado + gerar o bundle

```powershell
pwsh ./scripts/issue-client.ps1 `
    -CommonName "svc-etl" -Upn "svc-etl@empresa.com" `
    -Store ./minha-pki `
    -Oracle -DbHost "db.empresa.com" -DbPort 2484 -ServiceName "ORCLPDB1"
```

Isso cria, dentro de `minha-pki/issued/svc-etl/oracle/`:

- `sqlnet.ora` — exige TLS e aponta para a wallet
- `tnsnames.ora` — descritor de conexão TCPS
- `build-wallet.orapki.txt` — comandos `orapki` prontos
- `ca-chain.cert.pem` — cadeia de confiança (para o servidor confiar em você)

## 2. Montar a Oracle Wallet (máquina com Oracle Client)

Siga o roteiro `build-wallet.orapki.txt`. Em resumo:

```bash
orapki wallet create -wallet <dir> -pwd "<senha>" -auto_login
orapki wallet add     -wallet <dir> -trusted_cert -cert ca-chain.cert.pem -pwd "<senha>"
orapki wallet import_pkcs12 -wallet <dir> -pwd "<senha>" -pkcs12file <cliente>.p12 -pkcs12pwd "<senha_p12>"
orapki wallet display -wallet <dir> -pwd "<senha>"
```

## 3. Configurar o lado SERVIDOR

No banco, mapeie o certificado a um usuário autenticado externamente:

```sql
CREATE USER app_cliente IDENTIFIED EXTERNALLY
  AS 'CN=svc-etl,OU=CertForge PKI,O=Elevbit';
GRANT CREATE SESSION TO app_cliente;
```

E configure o listener para TCPS (porta 2484) com a wallet do servidor
confiando na `ca-chain.cert.pem` da sua PKI.

## 4. Conectar

```bash
export TNS_ADMIN=<dir_do_bundle>
sqlplus /@CERTFORGE_TCPS
```

Sem a wallet correta (com a chave privada), o handshake TCPS falha e a
conexão é recusada — que é exatamente o objetivo.
