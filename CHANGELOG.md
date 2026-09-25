# Changelog

Todas as mudanças notáveis deste projeto são documentadas aqui.
O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o versionamento segue [SemVer](https://semver.org/lang/pt-BR/).

## [1.0.0] — 2026-09-25

### Adicionado
- Hierarquia PKI de dois níveis (CA Raiz offline + CA Intermediária emissora).
- Emissão de certificados de cliente com `EKU = clientAuth` e SAN
  (e-mail/UPN) para mapeamento no Microsoft Entra ID.
- Empacotamento automático em PKCS#12 (.p12) e DER (.cer).
- Bundle **Oracle Database**: `sqlnet.ora`, `tnsnames.ora` e roteiro
  `orapki` para construir a Oracle Wallet (TCPS / TLS mútuo).
- Bundle **Azure SQL**: `.cer` para App Registration, roteiro Azure CLI e
  exemplo de conexão .NET/ODBC via Service Principal com certificado.
- Revogação de certificados e publicação de CRL com motivo.
- **Ledger de auditoria à prova de adulteração** (encadeamento por hash
  SHA-256) com verificação de integridade e detecção de fraude.
- Importação no Windows Certificate Store com chave **não-exportável** e
  opção de **selagem ao TPM** (Microsoft Platform Crypto Provider).
- Instalador com checagem de requisitos e self-test de ponta a ponta.

### Segurança
- Execução do OpenSSL com leitura concorrente de stdout/stderr para evitar
  deadlock em geração de chaves grandes (RSA-4096).
- Endurecimento de permissões (ACL/`chmod 600`) dos arquivos de chave.
- Normalização canônica de timestamps no ledger para hash determinístico.
