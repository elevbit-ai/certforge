@{
    RootModule        = 'CertForge.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b8f4d2a1-6c3e-4a9f-9d21-7e5c0a1f3b6d'
    Author            = 'Joaquim Pedro de Morais Filho'
    CompanyName       = 'Elevbit'
    Copyright         = '(c) 2026 Joaquim Pedro de Morais Filho. Licenca MIT.'
    Description       = 'Autoridade Certificadora de dois niveis que emite certificados de cliente para autenticacao mutua em Oracle Database (TCPS) e Azure SQL (Microsoft Entra ID).'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Get-CfConfig',
        'New-CfAuthority',
        'New-CfClientCertificate',
        'Revoke-CfCertificate',
        'Publish-CfCrl',
        'New-CfOracleWalletBundle',
        'New-CfAzureSqlBundle',
        'Import-CfClientToWindowsStore',
        'Add-CfLedgerEntry',
        'Test-CfLedger',
        'Get-CfFingerprint',
        'Write-CfLog'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags       = @('PKI', 'Certificate', 'mTLS', 'Oracle', 'AzureSQL', 'Security', 'EntraID')
            LicenseUri = 'https://github.com/elevbit-ai/certforge/blob/main/LICENSE'
            ProjectUri = 'https://github.com/elevbit-ai/certforge'
        }
    }
}
