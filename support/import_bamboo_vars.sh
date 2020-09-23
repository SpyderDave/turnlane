#
# Imports needed Bamboo Variables into script variables.
# These will be used initially and command line arguments can override
#
echo "--------------------------------------------------------------------------------------------------"
echo "Importing Bamboo Variables"
echo "--------------------------------------------------------------------------------------------------"
echo .
ImportBambooVars () {

if [[ ! -z "$bamboo_rolearn" ]]
then
  echo "Setting Role="$bamboo_rolearn
  export Role=$bamboo_rolearn
fi

if [[ ! -z "$bamboo_sceptre_version" ]]
then
  echo "Setting SCEPTRE_VERSION="$bamboo_sceptre_version
  export SCEPTRE_VERSION=$bamboo_sceptre_version
fi

if [[ ! -z "$bamboo_env_name" ]]
then
  echo "Setting Environment="$bamboo_env_name
  export Environment=$bamboo_env_name
fi

if [[ ! -z "$bamboo_application_name" ]]
then
  echo "Setting AppName="$bamboo_application_name
  export AppName=$bamboo_application_name
fi

if [[ ! -z "$bamboo_turnlane_directory" ]]
then
  echo "Setting TurnlaneDir="$bamboo_turnlane_directory
  export TurnlaneDir=$bamboo_turnlane_directory
fi

if [[ ! -z "$bamboo_source_directory" ]]
then
  echo "Setting SourceDir="$bamboo_source_directory
  export SourceDir=$bamboo_source_directory
fi

# Check 2 separate variables for Region
if [[ ! -z "$bamboo_AWS_DEFAULT_REGION" ]]
then
  echo "Setting AWS_Region="$bamboo_AWS_DEFAULT_REGION
  export AWS_Region=$bamboo_AWS_DEFAULT_REGION
fi
if [[ ! -z "$bamboo_region" ]]
then
  echo "Setting AWS_Region="$bamboo_region
  export AWS_Region=$bamboo_region
fi

if [[ ! -z "$bamboo_build_stage" ]]
then
  echo "Setting Stage="$bamboo_build_stage
  export Stage=$bamboo_build_stage
fi

if [[ ! -z "$bamboo_release_values" ]]
then
  echo "Setting RELEASE_VALUES="$bamboo_release_values
  export RELEASE_VALUES=$bamboo_release_values
fi

if [[ -z "$bamboo_delete_temp_bucket" ]] || [[ "$bamboo_delete_temp_bucket" == "false" ]]
then
  echo "Setting DeleteTempBucket="$bamboo_delete_temp_bucket
  export DeleteTempBucket="false"
fi

if [[ ! -z "$bamboo_use_branch" ]]
then
  export BranchName=""
  if [[ "$bamboo_use_branch" == "true" ]]
  then
    echo "Setting the BranchName:"$bamboo_planRepository_branch
    export BranchName=$bamboo_planRepository_branch
  fi
fi

if [[ ! -z "$bamboo_skip_sam_apps" ]]
then
  export SKIPSAM=$bamboo_skip_sam_apps
fi

} # End Function
