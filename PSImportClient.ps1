<#PSScriptInfo

.VERSION 1.0.0

.GUID 187e867b-5d4b-4ac8-b3b1-bdd8ddcbd53a

.AUTHOR anders.thyrsson@easit.com

.COMPANYNAME Easit AB

.COPYRIGHT 2024 Easit AB. All rights reserved.

.TAGS

.LICENSEURI https://github.com/easitab/PSImportClient/blob/main/LICENSE

.PROJECTURI https://github.com/easitab/PSImportClient

.ICONURI

.EXTERNALMODULEDEPENDENCIES Easit.GO.Webservice, Easit.PSImportClient.Commons

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
1.0.0 - Initial release of PSImportClient

.PRIVATEDATA

#>

#Requires -Version 7.4

<#
.Synopsis
    Script to retrieve object from a source and send to a destination.
.Description
    Script to retrieve object from a source and send to a destination supporting Easit GO formated XML and JSON.
    Script supports comparing objects from source and destination.
    Script supports creating custom properties from existing properties with the combine value of them.

    General script flow:
    * Script start
        * Initiation process
            * Directory validations
            * Setting file validation
            * Import dependency modules
            * Creating runtime variables
        * Import configuration file(s)
        * For each configuration file:
            * For each destination
                * For each source
                    * Read ImportClient configuration (either configured in Easit GO or a custom in *configuration.json*).
                    * Collect objects from a source as configured.
                    * Combine properties to new custom properties (if enabled and configured).
                    * Compare objects from source with objects from destination (if enabled and configured).
                    * Send objects to destination for update / create.
                    * Update archive, if needed.
                    * Run garbage collection.
        * Send notification with log file if error occurred and if enabled.
        * Run garbage collection.
        * Remove dependency modules
        * Remove runtime variables
    * Script end
    
    This script can also be executed "on demand" for one or more configuration files.

    Run as Windows Scheduled Task:
    * Command: pwsh
    * Arguments: -NonInteractive -NoLogo -NoProfile -File "D:\Easit\PSImportClient\PSImportClient.ps1"
    * WorkingDirectory: D:\Easit\PSImportClient
    
    Run as Windows Scheduled Task with specific configuration file:
    * Command: pwsh
    * Arguments: -NonInteractive -NoLogo -NoProfile -File "D:\Easit\PSImportClient\PSImportClient.ps1" -ConfigurationFiles "D:\Easit\PSImportClient\configurations\test.json"
    * WorkingDirectory: D:\Easit\PSImportClient

.Example
    PS D:\Easit\PSImportClient> .\PSImportClient.ps1

    In this example we let the script find all configuration files located in directory '.\configurations' and process them all.
    The script will run with the settings provided at '.\PSImportClientSettings.json'

.Example
    PS D:\Easit\PSImportClient> .\PSImportClient.ps1 -ClientSettingsFile 'D:\Easit\PSImportClient\myCustomSettings.json'

    In this example we let the script find all configuration files located in directory '.\configurations' and process them all.
    The script will run with the settings provided at 'D:\Easit\PSImportClient\myCustomSettings.json'

.Example
    PS D:\Easit\PSImportClient> .\PSImportClient.ps1 -ConfigurationFiles 'D:\Easit\PSImportClient\configurations\test.json'

    In this example we want to run the script with only one configuration file, *test.json*.
    The script will run with the settings provided at '.\PSImportClientSettings.json'

.Example
    PS D:\Easit\PSImportClient> .\PSImportClient.ps1 -ConfigurationFiles 'D:\Easit\PSImportClient\configurations\test.json', 'D:\Easit\PSImportClient\configurations\test2.json'

    In this example we want to run the script with multiple configuration files.
    The script will run with the settings provided at '.\PSImportClientSettings.json'

.PARAMETER ConfigurationFile
    Path to configuration file for what to import to destination.

.PARAMETER ClientSettingsFile
    Path to configuration file for how the PSImportClient script should behave.
#>
[CmdletBinding()]
param (
    [Parameter()]
    [string[]]$ConfigurationFile,
    [Parameter()]
    [string]$ClientSettingsFile
)
begin {
    function Get-CurrentLineNumber {
        $MyInvocation.ScriptLineNumber
    }
    $successInitLogMessages = [ordered]@{}
    $successInitLogMessages.Add((Get-CurrentLineNumber), "--- Initiating PSImportClient ---")
    $InformationPreference = 'Continue'
    $global:ProgressPreference = 'SilentlyContinue'
    $initlogName = "PSImportClient-init.log"
    $initLogPath = Join-Path -Path $PSScriptRoot -ChildPath $initlogName
    if (Test-Path -Path $initLogPath) {
        $isInitlogPresent = $true
    } else {
        $isInitlogPresent = $false
    }
    $initlogParams = @{
        FilePath = $initLogPath
        Encoding = 'utf8NoBOM'
        Append = $isInitlogPresent
        Force = $true
    }
    $srcDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'source'
    if (!(Test-Path -Path $srcDirectory)) {
        [string]::Format("{0} - Line: {1} - Line: {1} - Unable to find {2}",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber),$srcDirectory) | Out-File @initlogParams
        exit
    } else {
        $successInitLogMessages.Add((Get-CurrentLineNumber), "Found srcDirectory @ $srcDirectory")
    }
    $schemasDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'schemas'
    if (!(Test-Path -Path $schemasDirectory)) {
        [string]::Format("{0} - Line: {1} - Line: {1} - Unable to find {2}",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber),$schemasDirectory) | Out-File @initlogParams
        exit
    } else {
        $successInitLogMessages.Add((Get-CurrentLineNumber), "Found schemasDirectory @ $schemasDirectory")
    }
    # ClientSettingsFile can be provided via parameter
    if ([string]::IsNullOrEmpty($ClientSettingsFile)) {
        $ClientSettingsFile = Join-Path -Path $PSScriptRoot -ChildPath 'PSImportClientSettings.json'
    }
    if (!(Test-Path -Path "$ClientSettingsFile")) {
        [string]::Format("{0} - Line: {1} - Unable to find {2}",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber),$ClientSettingsFile) | Out-File @initlogParams
        exit
    } else {
        $successInitLogMessages.Add((Get-CurrentLineNumber), "Found ClientSettingsFile @ $ClientSettingsFile")
    }
    $clientSettingsSchemaFile = Join-Path -Path $schemasDirectory -ChildPath 'PSImportClientSettings.schema.json'
    if (!(Test-Path -Path "$clientSettingsSchemaFile")) {
        [string]::Format("{0} - Line: {1} - Unable to find {2}",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber),$clientSettingsSchemaFile) | Out-File @initlogParams
        exit
    } else {
        $successInitLogMessages.Add((Get-CurrentLineNumber), "Found clientSettingsSchemaFile @ $clientSettingsSchemaFile")
    }
    try {
        $clientSettingsContent = Get-Content -Path "$ClientSettingsFile" -Raw
        $successInitLogMessages.Add((Get-CurrentLineNumber), "Imported content from $ClientSettingsFile")
        $clientSettingsSchemaContent = Get-Content -Path "$clientSettingsSchemaFile" -Raw
        $successInitLogMessages.Add((Get-CurrentLineNumber), "Imported content from $clientSettingsSchemaFile")
    } catch {
        [string]::Format("{0} - Line: {1} - {2}",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber),$_) | Out-File @initlogParams
        exit
    }
    try {
        $successInitLogMessages.Add((Get-CurrentLineNumber),"Validating settings against schema")
        $null = Test-Json -Json $clientSettingsContent -Schema $clientSettingsSchemaContent -ErrorAction Stop
        $successInitLogMessages.Add((Get-CurrentLineNumber),"Settings have been validated")
    } catch {
        [string]::Format("{0} - Line: {1} - Failed to validate settings file agains schema due to {2}",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber),$_) | Out-File @initlogParams
        exit
    }
    try {
        New-Variable -Name "psImportClientSettings" -Value ($clientSettingsContent | ConvertFrom-Json) -Scope Global -Force -ErrorAction Stop
        $successInitLogMessages.Add((Get-CurrentLineNumber),"Converted client settings from JSON to object")
    } catch {
        [string]::Format("{0} - Line: {1} - Failed to convert client settings from JSON to object due to {2}",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber),$_) | Out-File @initlogParams
        exit
    }
    $successInitLogMessages.Add((Get-CurrentLineNumber),"Importing additional modules")
    foreach ($defaultModuleName in $psImportClientSettings.defaultModules) {
        $modulePath = Join-Path -Path $srcDirectory -ChildPath $defaultModuleName
        $highestModuleVersion = Get-ChildItem -Path $modulePath -Directory | Sort-Object -Property 'Name' -Descending -Top 1
        $moduleFile = Get-ChildItem -Path $highestModuleVersion -Recurse -Include '*.psm1'
        try {
            Import-Module $moduleFile.FullName -Force -Global -ErrorAction Stop
        } catch {
            [string]::Format("{0} - Line: {1} - Failed to import module from {2}",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber),$modulePath) | Out-File @initlogParams
            [string]::Format("{0} - Line: {1} - Errro: {2}",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber),$_) | Out-File @initlogParams
            exit
        }
    }
    try {
        $psImportClientSettings.notificationSettings | Add-Member -MemberType NoteProperty -Name 'sendNotification' -Value $false
        $psImportClientSettings.notificationSettings | Add-Member -MemberType NoteProperty -Name 'logFilepath' -Value $null
    } catch {
        [string]::Format("{0} - Line: {1} - Failed to set variables",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber)) | Out-File @initlogParams
        [string]::Format("{0} - Line: {1} - Errro: {2}",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber),$_) | Out-File @initlogParams
        exit
    }
    foreach ($setting in $psImportClientSettings.psobject.properties) {
        try {
            New-Variable -Name "psImportClient_$($setting.Name)" -Value $setting.Value -Scope Global -Force -ErrorAction Stop
        } catch {
            [string]::Format("{0} - Line: {1} - Failed to set variables",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber)) | Out-File @initlogParams
            [string]::Format("{0} - Line: {1} - Errro: {2}",(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),(Get-CurrentLineNumber),$_) | Out-File @initlogParams
            exit
        }
    }
    foreach ($message in $successInitLogMessages.GetEnumerator()) {
        Write-CustomLog -Message $message.Value -Level DEBUG
    }
    Get-Variable -Name 'psImportClient_*' -Scope Global | ForEach-Object {
        Write-CustomLog -Message "Created variable $($_.Name) in the global scope" -Level DEBUG
    }
}
process {
    Set-Location $PSScriptRoot
    Write-CustomLog -Message "--- Starting psImportClient in $PSScriptRoot ---"
    Write-CustomLog -Message "Rotating logs" -Rotate
    Write-CustomLog -Message "Using settings from $ClientSettingsFile" -Level VERBOSE
    $configurations = @()
    if (!($ConfigurationFile)) {
        Write-CustomLog -Message "No configuration files provided to parameter 'ConfigurationFile', attemtping to collect all configurations" -Level VERBOSE
        try {
            $configurations = Get-Configuration -PsImportClientDirectory $PSScriptRoot
        } catch {
            # Warn and errors are logged by Get-Configuration, catch block only to suppress output from throw
            return
        }
    } else {
        Write-CustomLog -Message "Configuration files provided to parameter 'ConfigurationFile', attempting to collect specified configurations" -Level VERBOSE
        try {
            $configurations = Get-Configuration -ConfigurationFile $ConfigurationFile
        } catch {
            # Warn and errors are logged by Get-Configuration, catch block only to suppress output from throw
            return
        }
    }
    if ($null -eq $configurations -or $configurations.Count -lt 1) {
        Write-CustomLog -Message "No configurations provided or found" -Level WARN
        return
    } else {
        Write-CustomLog -Message "Found $($configurations.Count) configuration(s)"
    }
    foreach ($configuration in $configurations) {
        Write-CustomLog -Message "-- Start for configuration: $($configuration.name)"
        foreach ($destination in $configuration.destinations) {
            if ($destination.disabled -eq 'true') {
                Write-CustomLog -Message "Destination $($destination.name) is disabled, skipping"
                continue
            } else {
                Write-CustomLog -Message "-- Start for destination: $($destination.name)"
                foreach ($source in $configuration.sources) {
                    $icConfig = $null
                    $objectsToSend = [System.Collections.ArrayList]@()
                    if ($source.disabled -eq 'true') {
                        Write-CustomLog -Message "Source $($source.name) is disabled, skipping"
                        continue
                    } else {
                        Write-CustomLog -Message "-- Start for source: $($source.name)"
                        if ($source.configurationType -eq 'external') {
                            try {
                                Invoke-DestinationAndSourceSync -Destination $destination -Source $source
                            } catch {
                                # Warn and errors are logged by Invoke-DestinationAndSourceSync, catch block only to suppress output from throw
                                continue
                            }
                            try {
                                Write-CustomLog -Message "Retrieving import client configuration from Easit GO"
                                $icConfig = Get-EasitGOImportClientConfiguration -Url $source.url -Apikey $source.apiKey -Identifier $source.icConfigurationIdentifier
                            } catch {
                                Write-CustomLog -Message "Failed to get Import Client configuration from $($source.url)" -Level WARN
                                Write-CustomLog -InputObject $_ -Level ERROR
                                continue
                            }
                        } elseif ($source.configurationType -eq 'custom') {
                            if ($null -eq $source.icConfig) {
                                Write-CustomLog -Message "icConfig is null" -Level WARN
                                continue
                            } else {
                                try {
                                    $icConfig = $source.icConfig
                                } catch {
                                    Write-CustomLog -Message "Failed to set Import Client configuration from configuration" -Level WARN
                                    Write-CustomLog -InputObject $_ -Level ERROR
                                    continue
                                }
                            }
                        } else {
                            Write-CustomLog -Message "Unknown source type" -Level WARN
                            continue
                        }
                        if ($null -eq $icConfig) {
                            Write-CustomLog -Message "Import client configuration for source is null" -Level WARN
                            continue
                        } else {
                            Write-CustomLog -InputObject $icConfig -Level DEBUG
                        }
                        if ($icConfig.ConfigurationType -eq 'jdbcConfiguration') {
                            try {
                                $sourceObjects = Invoke-JdbcHandler -SourceDirectory $srcDirectory -ImportClientConfiguration $icConfig -ConfigurationSourceSettings $source
                                $icConfig.UpdateArchive = $true
                            } catch {
                                # Warn and errors are logged by Invoke-JdbcHandler, catch block only to suppress output from throw
                                continue
                            }
                        } else {
                            Write-CustomLog -Message "Unknown configuration type" -Level WARN
                            continue
                        }
                        if ($source.compare.enabled) {
                            Write-CustomLog -Message "Compare is enabled, starting comparison flow"
                            $getReferenceObjectsParams = @{
                                Url = $source.url
                                Apikey = $source.apiKey
                                ImportViewIdentifier = $source.compare.systemViewIdentifier
                                GetAllPages = $true
                                ReturnAsSeparateObjects = $true
                                FlatReturnObject = $true
                            }
                            if ($destination.invokeRestMethodParameters) {
                                try {
                                    $tempHash = Convert-PsObjectToHashtable -InputObject $destination.invokeRestMethodParameters
                                    $getReferenceObjectsParams.Add('InvokeRestMethodParameters',$tempHash)
                                } catch {
                                    Write-CustomLog -Message "Failed to convert invokeRestMethodParameters to hashtable"
                                    Write-CustomLog -InputObject $_ -Level ERROR
                                    continue
                                }
                            }
                            try {
                                Write-CustomLog -Message "Collecting objects to compare with"
                                $referenceObjects = Get-EasitGOItem @getReferenceObjectsParams
                            } catch {
                                Write-CustomLog -Message "Failed to get objects to compare against" -Level WARN
                                Write-CustomLog -InputObject $_ -Level ERROR
                                continue
                            }
                            Write-CustomLog -Message "Collected number of objects to compare with: $($referenceObjects.Count)"
                            if ($referenceObjects.Count -gt 0) {
                                if ($source.combineDestinationAttributes.enabled -eq 'true') {
                                    Write-CustomLog -Message "Updating objects with combines" @psLoggerSettings
                                    foreach ($combine in $source.combineDestinationAttributes.combines) {
                                        foreach ($destObj in $referenceObjects) {
                                            if (Get-Member -InputObject $destObj -Name "$($combine.combineAttributeOutputName)" -ErrorAction SilentlyContinue) {
                                                Write-CustomLog -Message "Object already have a property named $($combine.combineAttributeOutputName)" -Level WARN
                                            } else {
                                                try {
                                                    Add-NewCombineProperty -InputObject $destObj -Combine $combine
                                                } catch {
                                                    # Warn and errors are logged by Add-NewCombineProperty, catch block only to suppress output from throw
                                                    continue
                                                }
                                            }
                                        }
                                    }
                                    Write-CustomLog -Message "All objects updated"
                                }
                                try {
                                    $compareResult = [System.Collections.ArrayList]@()
                                    [System.Collections.ArrayList]$compareResult += Invoke-ObjectComparison -ReferenceObject $referenceObjects -DifferenceObject $sourceObjects -CompareSettings $source.compare
                                } catch {
                                    # Warn and errors are logged by Invoke-ObjectComparison, catch block only to suppress output from throw
                                    continue
                                }
                                foreach ($compRes in $compareResult) {
                                    try {
                                        [void]$objectsToSend.Add($compRes)
                                    } catch {
                                        Write-CustomLog -InputObject $_ -Level ERROR
                                        continue
                                    }
                                }
                            }
                        } else {
                            Write-CustomLog -Message "Key 'compare.enabled' is set to $($source.compare.enabled)" -Level DEBUG
                            $objectsToSend = $sourceObjects
                        }
                        try {
                            $sendToEasitGOParams = Get-SendToEasitGOParameters -SourceSettings $source -DestinationSettings $destination
                        } catch {
                            Write-CustomLog -Message "Failed to get SendToEasitGO parameters" -Level WARN
                            Write-CustomLog -InputObject $_ -Level ERROR
                            continue
                        }
                        if ($sendToEasitGOParams.writeXML) {
                            Write-CustomLog -Message "writeXML is set to true, writing request(s) body to file"
                        }
                        if ($sendToEasitGOParams.dryRun) {
                            Write-CustomLog -Message "DryRun is set to true, will NOT send any data to Easit GO"
                        } else {
                            Write-CustomLog -Message "Sending $($objectsToSend.Count) objects to Easit GO"
                            $results = @()
                        }
                        try {
                            Write-CustomLog -InputObject $sendToEasitGOParams -Level VERBOSE
                            $allImportItemResults += Send-ToEasitGO @sendToEasitGOParams -Item $objectsToSend
                        } catch {
                            Write-CustomLog -Message "Failed to send objects to Easit GO" -Level WARN
                            Write-CustomLog -InputObject $_ -Level ERROR
                        }
                        $skippedObjects = @()
                        foreach ($importItemResult in $allImportItemResults) {
                            foreach ($result in $importItemResult.importItemResult) {
                                if ($result.result -ne 'OK') {
                                    $skippedObjects += $result
                                }
                            }
                        }
                        Write-CustomLog -Message "$($skippedObjects.Count) of $($objectsToSend.Count) objects was skipped"
                        if ($psImportClientSettings.loggerSettings.LogNonOkImportResults -and $skippedObjects.Count -gt 0) {
                            foreach ($skippedObject in $skippedObjects) {
                                Write-CustomLog -Message "Import object with uid $($skippedObject.uid) returned with the result: $($skippedObject.result)"
                            }
                        }
                        $objectsToSend = $null
                        if ($icConfig.UpdateArchive -and !($null -eq $psImportClientSettings.archiveSettings)) {
                            Write-CustomLog -Message "icConfig.UpdateArchive is $($icConfig.UpdateArchive), should run archive update"
                            try {
                                $archiveUpdate = @{
                                    AddToArchive = $true
                                    ArchiveSettings = $psImportClientSettings.archiveSettings
                                    ConfigurationName = "$($destination.Name)"
                                    FileToArchive = (Join-Path -Path $icConfig.sourceSettingsObject.path -ChildPath $icConfig.sourceSettingsObject.fileNameWithExtension -ErrorAction Stop)
                                    SourceName = $source.name
                                }
                                Update-Archive @archiveUpdate
                            } catch {
                                # Warn and errors are logged by Update-Archive, catch block only to suppress output from throw
                            }
                        } else {
                            Write-CustomLog -Message "icConfig.UpdateArchive is $($icConfig.UpdateArchive), should NOT run archive update"
                        }
                        try {
                            Write-CustomLog -Message "Running garbage collection" -Level VERBOSE
                            # https://learn.microsoft.com/en-us/dotnet/api/system.gc.collect
                            [System.GC]::Collect()
                            Write-CustomLog -Message "Garbage collection complete" -Level VERBOSE
                        } catch {
                            Write-CustomLog -Message "Failed to collect garbage" -Level WARN
                            Write-CustomLog -InputObject $_ -Level ERROR
                        }
                        Write-CustomLog -Message "-- End of source: $($source.name)"
                    }
                }
                Write-CustomLog -Message "-- End for destination: $($destination.name)"
            }
        }
    }
}
end {
    Write-CustomLog -Message "psImportClientSettings.notificationSettings.sendNotification = $($psImportClientSettings.notificationSettings.sendNotification)" -Level DEBUG
    Write-CustomLog -Message "psImportClientSettings.notificationSettings.enabled = $($psImportClientSettings.notificationSettings.enabled)" -Level DEBUG
    if ($psImportClientSettings.notificationSettings.sendNotification -and $psImportClientSettings.notificationSettings.enabled) {
        Write-CustomLog -Message "Sending log file"
        try {
            Send-Notification -Settings $psImportClientSettings.notificationSettings
        } catch {
            Write-CustomLog -Message "$($_.Exception.Message)" -Level WARN
        }
    }
    Write-CustomLog -Message "PSImportClient have completed, running clean up before ending"
    if (Test-Path -Path $initLogPath) {
        try {
            Remove-Item -Path $initLogPath -Force -Confirm:$false
        } catch {
            Write-CustomLog -Message "Failed to remove initlog file $initLogPath" -Level ERROR
        }
    }
    foreach ($defaultModuleName in $psImportClientSettings.defaultModules) {
        try {
            Remove-Module -Name $defaultModuleName
        } catch {
            Write-Warning "Failed to remove module $defaultModuleName"
        }
    }
    try {
        Get-Variable -Name 'psImportClient_*' -ErrorAction 'Stop' -Scope Global | Remove-Variable -Scope Global
    } catch {
        Write-Warning "Failed to remove psImportClient_* variables"
    }
    try {
        # https://learn.microsoft.com/en-us/dotnet/api/system.gc.collect
        [System.GC]::Collect()
        # https://learn.microsoft.com/en-us/dotnet/api/system.gc.waitforpendingfinalizers
        [System.GC]::WaitForPendingFinalizers()
    } catch {
        Write-Warning $_
    }
}