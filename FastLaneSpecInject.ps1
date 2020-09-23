# spec-inject.ps1
#
# Usage: spec-inject.ps1 
#
# Purpose:
# 

param (
    [Parameter(Mandatory=$true)][string]$version_number,
    [Parameter(Mandatory=$true)][string]$environment_name,
    [Parameter(Mandatory=$true)][string]$app_name,
    [Parameter(Mandatory=$true)][string]$aws_region,
	[Parameter(Mandatory=$true)][string]$source_dir
)
Write-Host "***********************************************************"
Write-Host "Parameters Listing:"
Write-Host "-------------------"
Write-Host "version_number: " $version_number
Write-Host "environment_name: " $environment_name
Write-Host "app_name: " $app_name
Write-Host "aws_region: " $aws_region
Write-Host "dns_zone: " $dns_zone
Write-Host "source_dir: " $source_dir
Write-Host "***********************************************************"

# First lets get the ALB TargetGroupName and SecurityGroupName name from the source stack

$SourceStack = $app_name + '-' + $version_number + '-' + $environment_name + '-' + 'webalb'
$stack = Get-CFNStack -StackName $SourceStack -Region $aws_region
$Outputs = $stack.Outputs
$TargetGroup = $Outputs | Select OutputKey, OutputValue | where OutputKey -eq "WebALBTargetGroup"
$SecurityGroup = $Outputs | Select OutputKey, OutputValue | where OutputKey -eq "WebALBAccessGroup"
$TargetGroupName = $TargetGroup.OutputValue
$SecurityGroupName = $SecurityGroup.OutputValue
Write-Host "***********************************************************"
Write-Host "I have extracted the following values from the " $SourceStack " stack:"
Write-Host "***********************************************************"
Write-Host "TargetGroupName: " $TargetGroupName
Write-Host "SecurityGroupName: " $SecurityGroupName

# 
# Now Build the Config file based on Parameters passed from CI tool (Bamboo)
#
$output_file = $source_dir + '\config\environments' + '\' + $environment_name + '.yaml'
Write-Host "Modifying Fastlane Spec File to inject parameters......: " $output_file
Write-Host "----------------------------"
# First remove any lines that have our 2 parameters
(Get-Content $output_file) | Where { $_ -notmatch "WebALBTargetGroup" } | Set-Content $output_file
(Get-Content $output_file) | Where { $_ -notmatch "WebALBSecurityGroup" } | Set-Content $output_file
# Now append to the end of the Spec file our parameters
$writeparameter = "WebALBTargetGroup: " + $TargetGroupName
Add-Content $output_file $writeparameter
$writeparameter = "WebALBSecurityGroup: " + $SecurityGroupName
Add-Content $output_file $writeparameter
Write-Host "----------------------------"
Write-Host "RESULTING Config File......: " $output_file
Write-Host "----------------------------"
Get-Content $output_file
