@{
    Rules = @{
        PSProvideCommentHelp = @{
            Enable = $true
            ExportedOnly = $false
            BlockComment = $true
            VSCodeSnippetCorrection = $false
            Placement = 'begin'
        }
    }
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}
<#
    If a file fails on rule PSUseBOMForUnicodeEncodedFile, run the line below to find invalid characters.
    (Get-Content 'PathToFile.ps1') -match "[\x90-\xFF]"
#>