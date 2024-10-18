BeforeAll {
    try {
        $projectDirectory = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $testFileObject = Get-ChildItem -Path $PSCommandPath
    } catch {
        throw
    }
    $environment = [PSCustomObject]@{
        TestFilePath = $testFileObject.FullName
        TestFilename = $testFileObject.Name
        CodeFileName = $testFileObject.Name.Replace('.Tests.ps1','.ps1')
        TestsFunctionDirectory = $testFileObject.Directory.FullName
        ErrorFilename = 'PSImportClient-Tests-Error.log'
    }
    try {
        $environment | Add-Member -MemberType Noteproperty -Name "TestsDirectory" -Value (Split-Path -Path $environment.TestsFunctionDirectory -Parent)
        $environment | Add-Member -MemberType Noteproperty -Name "CommandName" -Value $environment.CodeFileName.Replace('.ps1', '')
        $environment | Add-Member -MemberType Noteproperty -Name "TestDataDirectory" -Value (Join-Path -Path $environment.TestsDirectory -ChildPath "data")
        $environment | Add-Member -MemberType Noteproperty -Name "ProjectDirectory" -Value $projectDirectory
        $environment | Add-Member -MemberType Noteproperty -Name "SourceDirectory" -Value (Join-Path -Path $environment.ProjectDirectory -ChildPath "source")
        $environment | Add-Member -MemberType Noteproperty -Name "SchemasDirectory" -Value (Join-Path -Path $environment.ProjectDirectory -ChildPath "schemas")
        $environment | Add-Member -MemberType Noteproperty -Name "CodeFilePath" -Value (Get-ChildItem -Path $environment.ProjectDirectory -Include $environment.CodeFileName -Recurse)
        $environment | Add-Member -MemberType Noteproperty -Name "ErrorFilePath" -Value (Join-Path -Path $environment.TestsDirectory -ChildPath $environment.ErrorFilename)
    } catch {
        throw
    }
    Set-Alias -Name 'RunScript' -Value "$($environment.CodeFilePath)"
    #region mock functions
    function Get-CurrentLineNumber {
        $MyInvocation.ScriptLineNumber
    }
    function Import-Module {
        param (

        )
    }
    function Remove-Module {
        param (

        )
    }
    function Write-CustomLog {
        param (
            [string]$Message,
            [object]$InputObject,
            [string]$Level = 'INFO',
            [string]$OutputLevel,
            [string]$LogName,
            [string]$LogDirectory,
            [int]$RotationInterval,
            [switch]$Rotate
        )
        if ($Message) {
            if ($Level -eq 'ERROR') {
                $Message | Out-File -FilePath $environment.ErrorFilePath -Force
                throw $Message
            }
        }
        if ($InputObject) {
            if ($Level -eq 'ERROR') {
                $InputObject | Out-File -FilePath $environment.ErrorFilePath -Force
                throw $InputObject
            }
        }
    }
    function Get-Configuration {
        param (
            [String]$PsImportClientDirectory,
            [String[]]$ConfigurationFile
        )
        if ($null -eq $PsImportClientDirectory -and [string]::IsNullOrEmpty($ConfigurationFile) -and $null -eq $ConfigurationFile -and $ConfigurationFile.Count -lt 1) {
            "All input to Get-Configuration is null" | Out-File -FilePath $environment.ErrorFilePath -Force
        }
        if (Test-Path -Path $ConfigurationFile) {

        } else {
            "$ConfigurationFile does not exist" | Out-File -FilePath $environment.ErrorFilePath -Force
        }
        if ($PsImportClientDirectory) {
            $configurationsDirectory = $environment.TestDataDirectory
            if (!(Test-Path -Path "$configurationsDirectory")) {
                "$confg does not exist" | Out-File -FilePath $environment.ErrorFilePath -Force
            }
            try {
                Get-ChildItem -Path "$configurationsDirectory\*" -Include 'configuration*.json' | ForEach-Object {
                    $ConfigurationFile += $_.FullName
                }
            } catch {
                $_ | Out-File -FilePath $environment.ErrorFilePath -Force
                throw
            }
        }
        if ($ConfigurationFile) {
            foreach ($file in $ConfigurationFile) {
                if (Test-Path -Path "$file") {
                    try {
                        $configContent = Get-Content -Path $file -Raw
                    } catch {
                        $_ | Out-File -FilePath $environment.ErrorFilePath -Force
                        throw
                    }
                    try {
                        Test-Configuration -Json $configContent
                    } catch {
                        throw
                    }
                    try {
                        $configObjects += $configContent | ConvertFrom-Json
                    } catch {
                        $_ | Out-File -FilePath $environment.ErrorFilePath -Force
                        throw
                    }
                }
            }
        }
        return $configObjects

    }
    function Test-Configuration {
        param (
            [string]$Json
        )
        try {
            Test-Json -Json $Json -SchemaFile (Join-Path -Path $environment.SchemasDirectory -ChildPath 'configuration.schema.json') -ErrorAction Stop
        } catch {
            $_ | Out-File -FilePath $environment.ErrorFilePath -Force
            throw
        }
    }
    function Invoke-DestinationAndSourceSync {
        param (
            [Parameter()]
            [PSCustomObject]$Destination,
            [Parameter()]
            [PSCustomObject]$Source
        )
        if ([String]::IsNullOrEmpty($source.url)) {
            try {
                $source | Add-Member -MemberType NoteProperty -Name 'url' -Value $destination.url -Force
            } catch {
                $_ | Out-File -FilePath $environment.ErrorFilePath -Force
                throw
            }
        }
        if ([String]::IsNullOrEmpty($source.apiKey)) {
            try {
                $source | Add-Member -MemberType NoteProperty -Name 'apiKey' -Value $destination.apiKey -Force
            } catch {
                $_ | Out-File -FilePath $environment.ErrorFilePath -Force
                throw
            }
        }
        if ([String]::IsNullOrEmpty("$($source.writeXML)")) {
            if ([String]::IsNullOrEmpty("$($destination.writeXML)")) {

            } else {
                try {
                    $source | Add-Member -MemberType NoteProperty -Name 'writeXML' -Value $destination.writeXML -Force
                } catch {
                    $_ | Out-File -FilePath $environment.ErrorFilePath -Force
                throw
                }
            }
        }
        if ([String]::IsNullOrEmpty("$($source.dryRun)")) {
            if ([String]::IsNullOrEmpty("$($destination.dryRun)")) {

            } else {
                try {
                    $source | Add-Member -MemberType NoteProperty -Name 'dryRun' -Value $destination.dryRun -Force
                } catch {
                    $_ | Out-File -FilePath $environment.ErrorFilePath -Force
                    throw
                }
            }
        }
        if ([String]::IsNullOrEmpty($source.batchSize)) {
            if ([String]::IsNullOrEmpty("$($destination.batchSize)")) {

            } else {
                try {
                    $source | Add-Member -MemberType NoteProperty -Name 'batchSize' -Value $destination.batchSize -Force
                } catch {
                    $_ | Out-File -FilePath $environment.ErrorFilePath -Force
                    throw
                }
            }
        }
        if ([String]::IsNullOrEmpty($source.batchDelay)) {
            if ([String]::IsNullOrEmpty("$($destination.batchDelay)")) {

            } else {
                try {
                    $source | Add-Member -MemberType NoteProperty -Name 'batchDelay' -Value $destination.batchDelay -Force
                } catch {
                    $_ | Out-File -FilePath $environment.ErrorFilePath -Force
                    throw
                }
            }
        }

    }
    function Get-EasitGOImportClientConfiguration {
        param (
            [String]$Url,
            [String]$Apikey,
            [String]$Identifier
        )
        try {
            [xml]$xmlConfig = Get-Content 'C:\Github\easitanth\PSImportClient\tests\data\icConfigurationIdentifier1.xml' -Raw
        } catch {
            $_ | Out-File -FilePath $environment.ErrorFilePath -Force
            throw
        }
        $returnObject = @{
            ItemsPerPosting = $null
            SleepBetweenPostings = $null
            Identifier = $null
            Disabled = $null
            SystemName = $null
            TransformationXSL = $null
            ConfigurationType = $null
            ConfigurationTags = $null
            UpdateArchive = $false
        }
        if ($Identifier -eq 'icConfigurationIdentifier1') {
            $returnObject.ItemsPerPosting = $xmlConfig.jdbcConfiguration.ItemsPerPosting
            $returnObject.SleepBetweenPostings = $xmlConfig.jdbcConfiguration.SleepBetweenPostings
            $returnObject.Identifier = $xmlConfig.jdbcConfiguration.Identifier
            $returnObject.Disabled = $xmlConfig.jdbcConfiguration.Disabled
            $returnObject.SystemName = $xmlConfig.jdbcConfiguration.SystemName
            $returnObject.TransformationXSL = $xmlConfig.jdbcConfiguration.TransformationXSL
            $returnObject.ConfigurationType = 'jdbcConfiguration'
            $returnObject.ConfigurationTags = $xmlConfig.jdbcConfiguration.ConfigurationTags
            $returnObject.Add('ConnectionString',$xmlConfig.jdbcConfiguration.ConnectionString)
            $returnObject.Add('Query',$xmlConfig.jdbcConfiguration.Query)
            $returnObject.Add('DriverClassName',$xmlConfig.jdbcConfiguration.DriverClassName)
        }
        return [PSCustomObject]$returnObject
    }
    function Invoke-JdbcHandler {
        param (
            
        )
        return [PSCustomObject]@{
            ItemsPerPosting = $null
            SleepBetweenPostings = $null
            Identifier = $null
            Disabled = $null
            SystemName = $null
            TransformationXSL = $null
            ConfigurationType = $null
            ConfigurationTags = $null
        }        
    }
    function Get-SendToEasitGOParameters {
        param (
            [Parameter(Mandatory)]
            [PSCustomObject]$SourceSettings,
            [Parameter(Mandatory)]
            [PSCustomObject]$DestinationSettings
        )
        $sendToEasitGOParams = @{
            Url = $DestinationSettings.url
            Apikey = $DestinationSettings.apiKey
        }
        if ($null = $SourceSettings.importHandlerIdentifier -or [String]::IsNullOrEmpty($SourceSettings.importHandlerIdentifier)) {
            $sendToEasitGOParams.Add('ImportHandlerIdentifier',$SourceSettings.icConfigurationIdentifier)
        } else {
            $sendToEasitGOParams.Add('ImportHandlerIdentifier',$SourceSettings.importHandlerIdentifier)
        }
        if (($SourceSettings.batchSize -ge 1 -and $SourceSettings.batchSize -lt 50) -or $SourceSettings.batchSize -gt 50) {
            $sendToEasitGOParams.Add('SendInBatchesOf',$SourceSettings.batchSize)
        }
        if ($SourceSettings.batchDelay -gt 0) {
            $sendToEasitGOParams.Add('DelayBetweenBatches',$SourceSettings.batchDelay)
        }
        if ($DestinationSettings.InvokeRestMethodParameters) {
            try {
                $tempHash = Convert-PsObjectToHashtable -InputObject $DestinationSettings.invokeRestMethodParameters
                $sendToEasitGOParams.Add('InvokeRestMethodParameters',$tempHash)
            } catch {
                $_ | Out-File -FilePath $environment.ErrorFilePath -Force
                throw
            }
        }
        if ($SourceSettings.writeXML) {
            $sendToEasitGOParams.Add('WriteBody',$true)
        }
        if ($SourceSettings.dryRun) {
            $sendToEasitGOParams.Add('DryRun',$true)
        }
        return $sendToEasitGOParams
    }
    function Send-ToEasitGO {
        param (
            
        )
    }
    function Update-Archive {
        param (
            
        )
        
    }
    #endregion
    #region mock data and configs
    
    #endregion
}
Describe 'PSImportClient.ps1' {
    BeforeEach {
        if (Test-Path $environment.ErrorFilePath) {
            Remove-Item $environment.ErrorFilePath -Force -Confirm:$false
        }
    }
    It 'should have a parameter named ConfigurationFile that accepts an array of strings' {
        Get-Command "$($environment.CodeFilePath)" | Should -HaveParameter ConfigurationFile -Type [System.String[]]
    }
    It 'should have a parameter named ClientSettingsFile that accepts an array of strings' {
        Get-Command "$($environment.CodeFilePath)" | Should -HaveParameter ClientSettingsFile -Type [System.String]
    }
    It 'help section should have a SYNOPSIS' {
        ((Get-Help "$($environment.CodeFilePath)" -Full).SYNOPSIS).Length | Should -BeGreaterThan 0
    }
    It 'help section should have a DESCRIPTION' {
        ((Get-Help "$($environment.CodeFilePath)" -Full).DESCRIPTION).Length | Should -BeGreaterThan 0
    }
    It 'help section should have EXAMPLES' {
        ((Get-Help "$($environment.CodeFilePath)" -Full).EXAMPLES).Length | Should -BeGreaterThan 0
    }
    It 'should not throw or write error file with configuration1' {
        {RunScript -ConfigurationFile "$($environment.TestDataDirectory)\configuration1.json"} | Should -Not -Throw
        $environment.ErrorFilePath | Should -Not -Exist
    }
    It 'should not throw but write error file with configuration2' {
        {RunScript -ConfigurationFile "$($environment.TestDataDirectory)\configuration2.json"} | Should -Not -Throw
        $environment.ErrorFilePath | Should -Exist
    }
    It 'should not throw but write error file if configuration does not exist' {
        {RunScript -ConfigurationFile "$($environment.TestDataDirectory)\nonexistingconfiguration.json"} | Should -Not -Throw
        $environment.ErrorFilePath | Should -Exist
    }
    It 'PSImportClient-init.log should not exist after completion' {
        RunScript -ConfigurationFile "$($environment.TestDataDirectory)\configuration1.json"
        Join-Path -Path $environment.ProjectDirectory -ChildPath 'PSImportClient-init.log' | Should -Not -Exist
    }
    AfterEach {
        if (Test-Path $environment.ErrorFilePath) {
            # Write-Host (Get-Content $environment.ErrorFilePath)
            Remove-Item $environment.ErrorFilePath -Force -Confirm:$false
        }
    }
}