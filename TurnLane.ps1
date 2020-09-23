<#
.SYNOPSIS
    The following script executes Sceptre
.DESCRIPTION
    Intended use as a deployment tool via a Bamboo agent for Cloudformation or Troposphere as an alternative.
    Sceptre is installed as a Python module in order to deploy the code as cloudformation.
#>
param (
    [Parameter(Mandatory=$false)][string]$version_number,    
    [Parameter(Mandatory=$true)][string]$environment_name,
    [Parameter(Mandatory=$true)][string]$app_name,
    [Parameter(Mandatory=$true)][string]$turnlane_dir,
    [Parameter(Mandatory=$true)][string]$source_dir,
    [Parameter(Mandatory=$true)][string]$aws_region,
    [string]$stage="build"
)

# TEMP SETTINGS for TESTING ONLY
#$source_dir = "C:\Users\T924639\git\ec2-automated-backups"
#$environment_name = "devchaos"

Write-Host "Running TurnLane in $environment_name for $app_name"
Write-Host "Debug Information:"
Write-Host "Source Directory: $source_dir"
Write-Host "TurnLane Directory: $turnlane_dir"
if(!($version_number)){
    Write-Host "Version Number NOT Supplied"
}
else {
    Write-Host "Build Version:" $version_number
}
$logDate = get-date -format yyyyMMdd
$eventSource = "TurnLane"
$myScript = "TurnLane"
$ProgressPreference = 'SilentlyContinue'

# This is where we download Python installer 
$PythonBinaryLocation = "https://www.python.org/ftp/python/2.7.13/python-2.7.13.msi"

# Setup a temporary working directory to dump it all.
#$workingDirectory = $env:TEMP
$workingDirectory = "C:\"
# Where do we install and find Python 
$pythonInstallPath = "C:\Python27"
$pythoncommand = $pythonInstallPath + "\python.exe"
$sceptrecommand = $pythonInstallPath + "\scripts\sceptre.exe"
$env:path="$env:Path;C:\Python27"

#
# Here we define the directories for sceptre which should be beneath $source_dir (generally checked out from repo
#   |
#   |-templates
#   |
#   |-config
#   |---dev 
#
$generatorprefix="generator"
$templatesprefix="templates"
$configprefix="config"

# 
# Now Build the Config file based on Parameters passed from CI tool (Bamboo)
# This enables a unique stack name to be generated for each stack (using build #)
#
# 
if(!($version_number)){
    $line = "project_code: " + $app_name
}
else {
    $line = "project_code: " + $app_name + "-" + $version_number
}
$line | Out-File -Encoding Ascii $source_dir\$configprefix\$environment_name\config.yaml
$line = "region: " + $aws_region
$line | Out-File -Encoding Ascii -append $source_dir\$configprefix\$environment_name\config.yaml 
Get-Content $source_dir\$configprefix\$environment_name\config.yaml | foreach {Write-Output $_}


Function Write-Log
{
	Param([string]$Message)
    try
    {
        $ErrorActionPreference = 'Stop'

    	$logFile = $workingDirectory + "\" + "$($myScript)-" + $logDate + ".log"
    	$logDate = Get-Date -Format u
    	$logDate = $logDate.Substring(0,$logDate.length-1)

    	$logStamp = $logDate + "`t" + $Message
        Write-Host $logStamp

        if ($Message -like "*FAIL*")
        {
            Write-EventLog -LogName Application -Source $eventSource -EventId 0 -EntryType Error -Message $Message
        }
        else
        {
            Write-EventLog -LogName Application -Source $eventSource -EventId 1 -EntryType Information -Message $Message
        }
    	Write-Output $logStamp | Out-File $logFile -Encoding ASCII -append
    }
    catch
    {
        Write-Host "ERROR - Could not configure logging. Exception: $_.Exception"
        exit(1)
    }
}

#FUNCTION Install-Python
#Installs Python and Pip
Function Install-Python
{
    $filename = $PythonBinaryLocation.Substring($PythonBinaryLocation.LastIndexOf("/") + 1)

    Write-Host "Downloading Python installer from $PythonBinaryLocation to $workingDirectory as $filename"
    Invoke-WebRequest $PythonBinaryLocation -OutFile $workingDirectory$filename
    
    Write-Host "Installing Python from $workingDirectory$filename"
    $pythoninstaller="$workingDirectory$filename"
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $pythoninstaller /qn TARGETDIR=$pythonInstallPath" -Wait -NoNewWindow
}

#FUNCTION Install-PythonModules
#Installs Sceptre Troposphere
Function Install-PythonModules
{
    Write-Host "Invoking Pip to install Sceptre"
    Start-Process -FilePath "$pythonInstallPath\Scripts\pip.exe" -ArgumentList "install sceptre" -Wait -NoNewWindow
    Write-Host "Invoking Pip to install Troposphere"
    Start-Process -FilePath "$pythonInstallPath\Scripts\pip.exe" -ArgumentList "install troposphere" -Wait -NoNewWindow
    Write-Host "Invoking Pip to install Awacs"
    Start-Process -FilePath "$pythonInstallPath\Scripts\pip.exe" -ArgumentList "install awacs" -Wait -NoNewWindow
}
#
#FUNCTION Run-TroposphereGenerator
#Here we loop through all of the files in the generator directory (these are assumed to be troposphere/python)
#Each file is processed individually with troposphere, and the resulting JSON CFN is dumped into the templates folder for
#later processing by Spectre
#
Function Run-TroposphereGenerator
{
    Write-Host "Create the templates directory in case it did not checkout of the repo (ie. it was empty)"
    New-Item -ItemType Directory -Force -Path $source_dir\$templatesprefix

    foreach($file in Get-ChildItem $source_dir\$generatorprefix)
    {
      # Get the filename - without any extension
      $justhefilename = [System.IO.Path]::GetFileNameWithoutExtension($file)
      $templatefilename = $justhefilename + ".json"
      # Would be nice to rename the stack but that breaks sceptre depends
      # $templatefilename = $justhefilename + "-version-" + $version_number + ".json"
      Write-Host "Invoking Python $pythoncommand to process $source_dir\$generatorprefix\$file to generate JSON Cloudformation Template in $source_dir\$templatesprefix\$templatefilename"
      Start-Process -FilePath "$pythoncommand" -ArgumentList "$source_dir\$generatorprefix\$file" -RedirectStandardOutput "$source_dir\$templatesprefix\$templatefilename" -Wait -NoNewWindow
      Get-Content $source_dir\$templatesprefix\$templatefilename | foreach {Write-Output $_}
    }
    Write-Host "Here is a list of the templates that will be used to create Cloudformation Stacks\n\n"
    Get-ChildItem $source_dir\$templatesprefix
}

#FUNCTION Run Template Validation
Function Run-template-validate
{
	trap
    {
    write-output $_
    exit 1
    }
	Write-host "Run Sceptre template validation using $sceptrecommand validate-template for all files in $source_dir\$configprefix\$environment_name"

	ForEach ($file in Get-ChildItem $source_dir\$configprefix\$environment_name\*.yaml -Exclude 'config.yaml') {
			$docname = [IO.Path]::GetFileNameWithoutExtension("$file")
			Start-Process -FilePath "$sceptrecommand" -ArgumentList "--debug --dir $source_dir validate-template $environment_name $docname"  -Wait -NoNewWindow
	}

}

#FUNCTION Run-Sceptre
Function Run-Sceptre
{
    Write-Host "Invoking Sceptre to Deploy Cloudformation using $sceptrecommand for all files in $configprefix\$environment_name"
    Start-Process -FilePath "$sceptrecommand" -ArgumentList "--version"  -Wait -NoNewWindow
    # Launch the Environment
    try { 
     $MyExitCode = (Start-Process -FilePath "$sceptrecommand" -ArgumentList "--debug --dir $source_dir launch-env $environment_name"  -Wait -NoNewWindow).ExitCode
     Write-Host "Sceptre Exit Code : " $MyExitCode
    }
    catch
    {
     exit 1
    }
 #   foreach($file in Get-ChildItem $source_dir\$configprefix\$environment_name)
 #   {
 #     Write-Host "Invoking Sceptre to process $file to deploy Cloudformation Stack"
 #     $filenamewithnoext = [System.IO.Path]::GetFileNameWithoutExtension($file)
 #     if ( $filenamewithnoext -ne "config" )
 #     {
 #       Start-Process -FilePath "$sceptrecommand" -ArgumentList "--debug --dir $source_dir create-stack $environment_name $filenamewithnoext"  -Wait -NoNewWindow
 #       Start-Process -FilePath "$sceptrecommand" -ArgumentList "--debug --dir $source_dir describe-stack-resources $environment_name $filenamewithnoext"  -Wait -NoNewWindow
 #     }
 #   }
}

#FUNCTION Run-Teardown
Function Run-Teardown
{
    Write-Host "Invoking Sceptre to Teardown Cloudformation using $sceptrecommand for all files in $templatesprefix"
    Start-Process -FilePath "$sceptrecommand" -ArgumentList "--version"  -Wait -NoNewWindow
    # Launch the Environment
    Start-Process -FilePath "$sceptrecommand" -ArgumentList "--debug --dir $source_dir delete-env $environment_name"  -Wait -NoNewWindow
}


#MAIN
#Main script logic. Each function is wrapped in an if statement to provide idempotency

$ErrorActionPreference = 'SilentlyContinue'

if ([System.Diagnostics.EventLog]::SourceExists($eventSource) -eq $False)
{
    New-EventLog -LogName Application -Source $eventSource
}

Write-Log "INFO - Starting $($myScript)"
$functions =
    @{ "name" = "Install-Python" },
    @{ "name" = "Install-PythonModules" },
	@{ "name" = "Run-template-validate"},
    @{ "name" = "Run-Sceptre"  };
$teardownfunctions =
    @{ "name" = "Run-Teardown"  };


  if ( $stage -eq "teardown" )
  {
       foreach($function in $teardownfunctions)
       {
           Invoke-Expression ($function.name + " " + $function.parameters)
       }

  } else {
       foreach($function in $functions)
       {
           Invoke-Expression ($function.name + " " + $function.parameters)
       }
  }

Write-Log "INFO - Completed $($myScript)"
