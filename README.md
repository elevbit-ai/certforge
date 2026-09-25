<div align="center">

# 🔐 CertForge

**Autoridade Certificadora que emite certificados de cliente para autenticar conexões com Oracle Database e Azure SQL.**

*Sem o certificado, a conexão não acontece.*

[![PowerShell](https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![OpenSSL](https://img.shields.io/badge/OpenSSL-3.x-721412?logo=openssl&logoColor=white)](https://www.openssl.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/status-1.0.0-brightgreen.svg)](CHANGELOG.md)

Autor: **Joaquim Pedro de Morais Filho** · `j360074@hotmail.com`

</div>

---

## 📖 O que é isto

O **CertForge** é uma **fábrica de certificados digitais** (uma Autoridade
Certificadora completa) escrita em PowerShell 7 sobre OpenSSL 3. Ele resolve
um problema clássico de segurança:

> *"Quero que só quem tem um certificado emitido por mim consiga se conectar
> ao meu banco de dados. Sem esse certificado, a conexão deve ser recusada."*

Isso é **autenticação mútua por certificado** (mTLS). O CertForge cuida do
lado que gera e governa os certificados, e prepara automaticamente os
artefatos para os dois alvos suportados:

- **Oracle Database** — via Oracle Wallet e protocolo **TCPS** (TLS mútuo).
- **Azure SQL Database** — via credencial de **certificado** de um Service
  Principal no **Microsoft Entra ID**.

---

## 🧠 Como funciona (o conceito antes do código)

Um ponto que confunde muita gente: **o certificado sozinho não autoriza
nada**. Ele é apenas a metade *pública* de um par de chaves, assinada por uma
autoridade em quem o servidor confia. Quem realmente prova sua identidade é a
**chave privada**, que fica só com o cliente.

O fluxo de uma conexão protegida por certificado é:

```
   CLIENTE                                   SERVIDOR (Oracle / Azure SQL)
   ───────                                   ─────────────────────────────
   1. "Quero conectar"      ───────────▶
                            ◀───────────     2. "Prove quem você é:
                                                 me mostre um certificado
                                                 assinado por uma CA que eu confio"
   3. Envia o certificado
      + prova que tem a
      chave privada         ───────────▶
                                             4. Verifica:
                                                • foi assinado pela minha CA?
                                                • não está revogado (CRL)?
                                                • a chave privada confere?
                            ◀───────────     5. ✅ aceita   ou   ❌ recusa
```

Se o cliente **não** apresenta um certificado válido — ou tem o certificado
mas não a chave privada — a conexão é **recusada no handshake TLS**, antes
mesmo de chegar em usuário e senha.

### A hierarquia de duas camadas

O CertForge cria uma PKI profissional de **dois níveis**:

```
                    ┌─────────────────────────┐
                    │      CA RAIZ            │   ← chave mantida OFFLINE
                    │   (auto-assinada)       │      assina só a intermediária
                    └───────────┬─────────────┘
                                │ assina
                    ┌───────────▼─────────────┐
                    │   CA INTERMEDIÁRIA      │   ← emissora do dia a dia
                    │   (emissora / issuing)  │      assina clientes + publica CRL
                    └───────────┬─────────────┘
                                │ assina
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
        ┌──────────┐      ┌──────────┐      ┌──────────┐
        │ cliente  │      │ cliente  │      │ cliente  │
        │  Oracle  │      │ AzureSQL │      │   ...    │
        └──────────┘      └──────────┘      └──────────┘
```

**Por que dois níveis?** Se a chave da raiz vaza, toda a confiança cai. Ao
manter a raiz **offline** e usar a intermediária no dia a dia, um
comprometimento da emissora pode ser contido revogando-a e reemitindo — sem
refazer a raiz e sem reconfigurar todos os servidores.

---

## ✅ Requisitos

| Requisito | Versão | Observação |
|-----------|--------|------------|
| **PowerShell** | 7.2+ | Windows, Linux ou macOS |
| **OpenSSL** | 3.x | Precisa estar no `PATH` |
| **Oracle Client** (`orapki`) | opcional | só para converter em Oracle Wallet |
| **Azure CLI** (`az`) | opcional | só para registrar o app no Entra ID |
| **TPM 2.0** | opcional | só para selagem de chave ao hardware (Windows) |

Instalando o OpenSSL:

```powershell
# Windows
winget install ShiningLight.OpenSSL.Light
# Linux (Debian/Ubuntu)
sudo apt install openssl
# macOS
brew install openssl@3
```

---

## 🚀 Instalação

```powershell
git clone https://github.com/elevbit-ai/certforge.git
cd certforge

# Verifica requisitos, importa o módulo e roda o self-test de ponta a ponta
pwsh ./scripts/install.ps1
```

O instalador confere PowerShell e OpenSSL, importa o módulo e executa um
**teste completo** (cria uma CA temporária, emite, revoga e valida o ledger)
para garantir que tudo funciona na sua máquina.

---

## ⚡ Uso rápido

### 1. Criar a Autoridade Certificadora

```powershell
pwsh ./scripts/new-ca.ps1 -Store ./minha-pki
```

Serão pedidas as passphrases da Raiz e da Intermediária. Ao final:

> ⚠️ **Mova `minha-pki/root-ca/private/root-ca.key.pem` para armazenamento
> offline.** Essa é a chave mais valiosa da sua PKI.

### 2. Emitir um certificado para Oracle

```powershell
pwsh ./scripts/issue-client.ps1 `
    -CommonName "svc-etl" -Upn "svc-etl@empresa.com" `
    -Store ./minha-pki `
    -Oracle -DbHost "db.empresa.com" -DbPort 2484 -ServiceName "ORCLPDB1"
```

Gera o certificado + `sqlnet.ora`, `tnsnames.ora` e o roteiro `orapki` para
montar a Oracle Wallet. Ver [`examples/oracle`](examples/oracle).

### 3. Emitir um certificado para Azure SQL

```powershell
pwsh ./scripts/issue-client.ps1 `
    -CommonName "svc-bi" -Upn "svc-bi@empresa.com" `
    -Store ./minha-pki `
    -AzureSql -SqlServer "meusrv.database.windows.net" -Database "vendas" `
    -AppDisplayName "CertForge-BI"
```

Gera o `.cer` para subir no App Registration + roteiro Azure CLI + exemplo de
conexão .NET/ODBC. Ver [`examples/azure-sql`](examples/azure-sql).

### 4. Guardar a chave de forma inviolável (Windows)

```powershell
pwsh ./scripts/issue-client.ps1 -CommonName "svc-seguro" -Store ./minha-pki `
    -ImportToWindows -BindToTpm
```

Importa a identidade no Windows Certificate Store como **não-exportável** e a
sela ao **TPM** — a chave nunca mais deixa o hardware desta máquina.

### 5. Revogar e verificar a auditoria

```powershell
pwsh ./scripts/revoke.ps1 -Store ./minha-pki -Serial 1001 -Reason keyCompromise
pwsh ./scripts/verify-ledger.ps1 -Store ./minha-pki
```

---

## 🛡️ Recursos de segurança diferenciados

Estes são os recursos que colocam o CertForge acima de um simples script de
`openssl`. Nenhum deles reinventa criptografia — eles **combinam boas
práticas comprovadas** num sistema coeso.

### 1. Ledger de auditoria à prova de adulteração (hash-chaining)

Cada evento (criação de CA, emissão, revogação, publicação de CRL) vira uma
linha num livro-razão onde **cada entrada carrega o hash SHA-256 da entrada
anterior**, no estilo de uma cadeia de blocos:

```
evento[n].hash = SHA256( conteúdo[n] + evento[n-1].hash )
```

Se alguém alterar retroativamente qualquer registro (mudar um nome, apagar
uma revogação), **todos os hashes seguintes deixam de fechar** e o
`verify-ledger` acusa exatamente a linha adulterada. Você tem uma prova
matemática do histórico da sua CA.

### 2. Chave não-exportável selada ao TPM

No Windows, a identidade pode ser importada com a chave privada marcada como
**não-exportável** e movida para o **Microsoft Platform Crypto Provider**
(TPM 2.0). A partir daí, a assinatura acontece *dentro* do chip: nem um
administrador consegue copiar a chave. Isso derrota o cenário "atacante copia
o `.pfx`".

### 3. Menor privilégio no próprio certificado

Todo certificado de cliente sai com `Extended Key Usage = clientAuth` **e
nada além disso**. Se vazar, não serve para forjar um servidor TLS, assinar
código ou e-mail — só autentica cliente, e só na sua PKI.

### 4. Raiz offline + emissora de curta duração

A raiz assina apenas a intermediária (`pathlen:0`, ou seja, a intermediária
não pode criar outras CAs). Certificados de cliente têm validade curta
(90 dias por padrão), reduzindo a janela de um certificado comprometido.

### 5. Revogação com CRL e ponto de distribuição embutido

Cada certificado carrega no campo *CRL Distribution Points* o endereço onde o
servidor busca a lista de revogados. Revogou? O servidor passa a recusar
aquele certificado assim que lê a CRL atualizada.

### 6. Passphrases fortes e chaves cifradas em repouso

As chaves das CAs são cifradas com **AES-256** e o sistema valida força
mínima da passphrase (comprimento + classes de caracteres) antes de criar a
hierarquia.

---

## 📚 Referência de comandos

| Função (módulo) | Script | O que faz |
|-----------------|--------|-----------|
| `New-CfAuthority` | `new-ca.ps1` | Cria a hierarquia PKI (raiz + intermediária) |
| `New-CfClientCertificate` | `issue-client.ps1` | Emite um certificado de cliente |
| `New-CfOracleWalletBundle` | `issue-client.ps1 -Oracle` | Artefatos da Oracle Wallet / TCPS |
| `New-CfAzureSqlBundle` | `issue-client.ps1 -AzureSql` | Artefatos do Azure SQL / Entra ID |
| `Import-CfClientToWindowsStore` | `issue-client.ps1 -ImportToWindows` | Importa com chave não-exportável / TPM |
| `Revoke-CfCertificate` | `revoke.ps1` | Revoga um certificado e regenera a CRL |
| `Publish-CfCrl` | — | (Re)gera a CRL |
| `Test-CfLedger` | `verify-ledger.ps1` | Verifica a integridade do ledger |

Configurações (algoritmos, validade, organização, segurança) ficam em
[`config/certforge.config.json`](config/certforge.config.json).

---

## 🗂️ Estrutura do projeto

```
certforge/
├── src/
│   ├── CertForge.psm1 / .psd1     # módulo PowerShell
│   └── lib/                       # motor: CA, emissão, revogação, ledger,
│                                  #        Oracle, Azure, Windows/TPM
├── scripts/                       # CLI: install, new-ca, issue-client,
│                                  #      revoke, verify-ledger
├── openssl/                       # perfis .cnf de CA raiz/intermediária/cliente
├── config/                        # configuração central (JSON)
├── examples/                      # exemplos Oracle e Azure SQL
├── tests/Run-SelfTest.ps1         # teste automatizado de ponta a ponta
└── docs/                          # site (GitHub Pages)
```

---

## ❓ Perguntas frequentes

**O CertForge substitui uma CA pública (DigiCert, Let's Encrypt)?**
Não para servidores voltados à internet. Ele é uma **CA privada**, ideal para
autenticação *interna* entre suas aplicações e seus bancos — exatamente o
caso de mTLS com Oracle/Azure SQL.

**Preciso de Oracle Client ou Azure CLI para gerar os certificados?**
Não. A **emissão** só usa OpenSSL. `orapki` e `az` entram apenas na etapa
final de montar a wallet / registrar o app — e o CertForge já entrega os
comandos prontos.

**Funciona no Linux/macOS?**
Sim, com PowerShell 7 + OpenSSL 3. A selagem ao TPM é um recurso específico
do Windows.

---

## 📄 Licença

[MIT](LICENSE) © 2026 **Joaquim Pedro de Morais Filho**.

<div align="center">
<sub>Desenvolvido por Joaquim Pedro de Morais Filho — <code>j360074@hotmail.com</code></sub>
</div>
