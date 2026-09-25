# Política de Segurança — CertForge

## Modelo de ameaça

O CertForge foi desenhado para proteger contra três cenários distintos.
Entender qual é o seu caso define quais recursos ativar.

| Cenário | Ameaça | Defesa no CertForge |
|--------|--------|---------------------|
| **1. Arquivo copiado** | Backup vazado, disco perdido, malware que exfiltra arquivos | Chaves privadas cifradas em repouso (AES-256), PKCS#12 protegido por passphrase |
| **2. Acesso à máquina ligada** | Atacante com sessão do usuário | Chave **não-exportável** no Windows Certificate Store; validação por CRL |
| **3. Proteção de hardware** | Extração da chave mesmo com admin | Chave **selada ao TPM** (nunca deixa o chip); vínculo ao hardware |

## Princípios adotados

1. **Nunca reinventamos criptografia.** Usamos OpenSSL 3.x e primitivas
   padronizadas (RSA ≥ 3072, SHA-384, AES-256).
2. **Hierarquia de dois níveis.** A chave da CA Raiz é gerada e deve ser
   mantida **offline**; o dia a dia usa a CA Intermediária (emissora).
3. **Menor privilégio no certificado.** Todo certificado de cliente é
   emitido com `Extended Key Usage = clientAuth` apenas — não serve para
   servidor, código ou e-mail.
4. **Revogação real.** CRL assinada pela emissora, com motivo registrado.
5. **Auditoria à prova de adulteração.** Cada evento é encadeado por hash
   (SHA-256) ao evento anterior; qualquer alteração retroativa é detectada.

## Boas práticas operacionais

- Após criar a hierarquia, **mova `root-ca/private/root-ca.key.pem` para
  mídia offline** (pen drive cofre, HSM, cofre físico).
- Use passphrases distintas e fortes para a Raiz e para a Intermediária.
- Emita certificados de **curta duração** (padrão: 90 dias) e renove.
- Publique a CRL num endpoint acessível ao servidor (o URI vai dentro do
  certificado, no campo CRL Distribution Points).
- **Nunca** faça commit do diretório `.certforge-store/` (já está no
  `.gitignore`).

## Reporte de vulnerabilidades

Encontrou uma falha? Abra uma *issue* privada ou escreva para
**j360074@hotmail.com**. Descreva a classe do problema sem publicar um
exploit funcional.
