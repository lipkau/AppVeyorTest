param()

Import-Module "$PSScriptRoot/Tools/build.psm1" -Force -ErrorAction Stop
Import-Module "$PSScriptRoot/Tools/AppVeyor.psm1" -Force -ErrorAction Stop
$project = Get-AppVeyorProject
if ($BuildTask -notin @("SetUp", "InstallDependencies")) {
    Import-Module BuildHelpers -Force -ErrorAction Stop
}

#region SetUp
# Synopsis: Create an initial environment for developing on the module
task SetUp InstallDependencies, Build

# Synopsis: Install all module used for the development of this module
task InstallDependencies {
    Install-PSDepend
    Import-Module PSDepend -Force
    $parameterPSDepend = @{
        Path        = "$PSScriptRoot/Tools/build.requirements.psd1"
        Install     = $true
        Import      = $true
        Force       = $true
        ErrorAction = "Stop"
    }
    $null = Invoke-PSDepend @parameterPSDepend
    Import-Module BuildHelpers -Force
}

# Synopsis: Ensure the build environment is all ready to go
task Init {
    Set-BuildEnvironment -BuildOutput '$ProjectPath/Release' -ErrorAction SilentlyContinue

    Add-ToModulePath -Path $env:BHBuildOutput
}, GetNextVersion

# Synopsis: Get the next version for the build
task GetNextVersion {
    $currentVersion = [Version](Get-Metadata -Path $env:BHPSModuleManifest)
    if ($env:BHBuildNumber) {
        $newRevision = $env:BHBuildNumber
    }
    else {
        $newRevision = 0
    }
    $env:NextBuildVersion = [Version]::New($currentVersion.Major, $currentVersion.Minor, $newRevision)
    $env:CurrentBuildVersion = $currentVersion
}
#endregion Setup

#region DebugInformation
task ShowInfo Init, {
    Write-Build Gray
    Write-Build Gray ('Running in:                 {0}' -f $env:BHBuildSystem)
    Write-Build Gray '-------------------------------------------------------'
    Write-Build Gray
    Write-Build Gray ('Project name:               {0}' -f $env:BHProjectName)
    Write-Build Gray ('Project root:               {0}' -f $env:BHProjectPath)
    Write-Build Gray ('Build Path:                 {0}' -f $env:BHBuildOutput)
    Write-Build Gray ('Current Version:            {0}' -f $env:CurrentBuildVersion)
    Write-Build Gray '-------------------------------------------------------'
    Write-Build Gray
    Write-Build Gray ('Branch:                     {0}' -f $env:BHBranchName)
    Write-Build Gray ('Commit:                     {0}' -f $env:BHCommitMessage)
    Write-Build Gray ('Build #:                    {0}' -f $env:BHBuildNumber)
    Write-Build Gray ('Next Version:               {0}' -f $env:NextBuildVersion)
    Write-Build Gray ('Will deploy new version?    {0}' -f (Test-ShouldDeploy))
    Write-Build Gray '-------------------------------------------------------'
    Write-Build Gray
    Write-Build Gray ('PowerShell version:         {0}' -f $PSVersionTable.PSVersion.ToString())
    Write-Build Gray ('OS:                         {0}' -f $OS)
    Write-Build Gray ('OS Version:                 {0}' -f $OSVersion)
    Write-Build Gray
}
#endregion DebugInformation

task Clean {
    Get-item $env:BHBuildOutput -ErrorAction Ignore | Remove-Item -Recurse -Force -ErrorAction Ignore

    Write-Host (Get-AppVeyorArtifact -Job $project.build.jobs[0])
}
task Build {
    # Setup
    if (-not (Test-Path "$env:BHBuildOutput/$env:BHProjectName")) {
        $null = New-Item -Path "$env:BHBuildOutput/$env:BHProjectName" -ItemType Directory
    }
    Copy-Item -Path "$env:BHModulePath/*" -Destination "$env:BHBuildOutput/$env:BHProjectName" -Recurse -Force

    $regionsToKeep = @('Dependencies', 'ModuleConfig')

    $targetFile = "$env:BHBuildOutput/$env:BHProjectName/$env:BHProjectName.psm1"
    $content = Get-Content -Encoding UTF8 -LiteralPath $targetFile
    $capture = $false
    $compiled = ""

    foreach ($line in $content) {
        if ($line -match "^#region ($($regionsToKeep -join "|"))$") {
            $capture = $true
        }
        if (($capture -eq $true) -and ($line -match "^#endregion")) {
            $capture = $false
        }

        if ($capture) {
            $compiled += "$line`r`n"
        }
    }

    $PublicFunctions = @( Get-ChildItem -Path "$env:BHBuildOutput/$env:BHProjectName/Public/*.ps1" -ErrorAction SilentlyContinue )
    $PrivateFunctions = @( Get-ChildItem -Path "$env:BHBuildOutput/$env:BHProjectName/Private/*.ps1" -ErrorAction SilentlyContinue )

    foreach ($function in @($PublicFunctions + $PrivateFunctions)) {
        $compiled += (Get-Content -Path $function.FullName -Raw)
        $compiled += "`r`n"
    }

    Set-Content -LiteralPath $targetFile -Value $compiled -Encoding UTF8 -Force
    Remove-Utf8Bom -Path $targetFile

    "Private", "Public" | Foreach-Object { Remove-Item -Path "$env:BHBuildOutput/$env:BHProjectName/$_" -Recurse -Force }

    Write-Host (Get-AppVeyorArtifact -Job $project.build.jobs[0])
}
task Package Build, {
    Get-ChildItem $env:BHBuildOutput/$env:BHProjectName | % { Push-AppveyorArtifact $_.FullName }
}
task Download {
    # Setup
    if (-not (Test-Path "$env:BHBuildOutput/$env:BHProjectName")) {
        $null = New-Item -Path "$env:BHBuildOutput/$env:BHProjectName" -ItemType Directory
    }

    Get-AppVeyorArtifact -Job $project.build.jobs[0] -Verbose |
        Get-AppVeyorArtifactFile -Job $project.build.jobs[0] -OutPath "$env:BHBuildOutput/$env:BHProjectName" -Verbose
}
task Test {
    Invoke-Pester

    Write-Host (Get-AppVeyorArtifact -Job $project.build.jobs[0])
}
task Deploy {
    Write-Host deploying

    Write-Host (Get-AppVeyorArtifact -Job $project.build.jobs[0])
}

if ((-not $env:APPVEYOR_JOB_ID) -or ($env:APPVEYOR_JOB_ID -eq $project.build.jobs[0].JobId)) {
    Write-Host "You are in the first job"
    task . ShowInfo, Clean, Build, Package, Test, Deploy
}
else {
    Write-Host "You are NOT in the first job"
    task . ShowInfo, Clean, Download, Test, Deploy
}
