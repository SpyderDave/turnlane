#!/bin/bash
#
# codedeploy-package.sh
#
# usage <-B|--BAMBOO> <-i|--iam_role> <-v|--version version_number> -e|--environment env_name -a|--app_name application_name <-t|--turnlane_dir turnlane_dir> \
#       <-s|--source_dir source_dir> <-r|--region AWS_Region> <-b|--build_stage <build|validate|exportvars|teardown> <-z|--sceptre_version version>
#       <-d|--delete_temp_bucket true|false>
#
# turnlane.sh 
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cat ${DIR}/turnlane_logo.txt
set -e
echo "Setting Defaults"
retVal=0
Role=""
AWS_Region="ca-central-1"
StackName=""
SCEPTRE_VERSION=1.4.2
SCEPTRE_VALIDATE="validate-template"
USE_BAMBOO_VARS="false"
DeleteTempBucket=true

# Import Bamboo Variables - these can be overridden by command line args
. ${DIR}/support/import_bamboo_vars.sh
ImportBambooVars

# Now check the rest of the command line which can override variables.
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -i|--iam_role)
    Role="$2"
    shift # past argument
    shift # past value
    ;;
    -e|--environment)
    Environment="$2"
    shift # past argument
    shift # past value
    ;;
    -a|--app_name)
    AppName="$2"
    shift # past argument
    shift # past value
    ;;
    -s|--source_dir)
    SourceDir="$2"
    shift # past argument
    shift # past value
    ;;
    -r|--region)
    AWS_Region="$2"
    shift # past argument
    shift # past value
    ;;
    -d|--delete_temp_bucket)
    DeleteTempBucket="$2"
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    echo "Unknown Option" $key
    exit 9
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

echo "Checking command line parameters."
if [[ -z $AppName ]] 
then
  echo "-a | --app_name must be specified."
  exit 3
else
  echo "AppName="$AppName
fi
if [[ -z $Environment ]] 
then
  echo "-e | --environment must be specified."
  exit 3
else
  echo "Environment="$Environment
fi
if [[ -z $TurnlaneDir ]] 
then
  echo "turnlane_dir not specified."
  TurnlaneDir="turnlane"
  echo "Using default: " $TurnlaneDir
fi
if [[ -z $SourceDir ]] 
then
  echo "source_dir not specified."
  SourceDir="source"
  echo "Using default: " $SourceDir
fi
if [[ -z $Stage ]] 
then
  echo "build_stage not specified."
  Stage="build"
  echo "Using default: " $Stage
fi
echo "Checking source and turnlane directories....."
if [ ! -d "$TurnlaneDir" ]; then
  echo "ERROR Turnlane Directory NOT FOUND"
  exit 4
fi
if [ ! -d "$SourceDir" ]; then
  echo "ERROR Source Directory ${SourceDir} NOT FOUND"
  exit 4
fi

echo "*******Turnlane running with the following settings:"
echo "."
echo "AppName:" $AppName
echo "Environment:" $Environment
echo "Turnlane:" $TurnlaneDir
echo "Source:" $SourceDir
echo "Stage:" $Stage
echo "."

echo "Verifying that we have Python installed with virtualenv."
pythoncmd=`which python`
if [[ -z $pythoncmd ]]
then
  echo "Cannot locate python command. EXITING"
  exit 6
fi
pipcmd=`which pip`
if [[ -z $pipcmd ]]
then
  echo "Cannot locate python pip command. EXITING"
  exit 6
fi
venvcmd=`which virtualenv`
if [[ -z $venvcmd ]]
then
  echo "Cannot locate python virtualenv command. EXITING"
  exit 6
fi

echo "Setting up Sceptre run."
generatorprefix="generator"
templatesprefix="templates"
configprefix="config"
echo "Checking source directory hierarchy."
if [ ! -d "${SourceDir}/${configprefix}/${Environment}" ]; then
  echo "ERROR Source Directory Hierarchy is incorrect for proper sceptre execution."
  echo "${SourceDir}/${configprefix}/${Environment} DOES NOT EXIST"
  exit 5
fi

#
# If Version is specified this respresents a build # which needs to be included in generated stack names. 
#
if [[ ! -z $Version ]] 
then
  line="project_code: ${AppName}-${Version}"
else
  line="project_code: ${AppName}"
  Version="0"
fi
# If BranchName is specified include it in generated stack names
if [[ ! -z $BranchName ]] 
then 
  line=${line}-${BranchName}
fi
outfile="${SourceDir}/${configprefix}/${Environment}/config.yaml"
echo $line > $outfile
line="region: ${AWS_Region}"
echo $line >> $outfile
if [[ ! -z $Role ]]
then
  line="iam_role: ${Role}"
  echo $line >> $outfile
  echo "-------------------------------------------------------------"
  echo " SWITCHING ROLES NOW"
  echo " Role: "${Role}
  echo "-------------------------------------------------------------"
  temp_role=$(aws sts assume-role --role-arn $Role --role-session-name bootstrapping)
  export AWS_ACCESS_KEY_ID=$(echo $temp_role | jq .Credentials.AccessKeyId | xargs)
  export AWS_SECRET_ACCESS_KEY=$(echo $temp_role | jq .Credentials.SecretAccessKey | xargs)
  export AWS_SESSION_TOKEN=$(echo $temp_role | jq .Credentials.SessionToken | xargs)
  echo "AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID
  echo "AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY
  echo "AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN
fi
# Set the AWS Account Number only after Assuming the Correct Role
echo "Obtaining the AWS Account Number"
AWS_ACCOUNT_ID=$(aws ec2 describe-security-groups \
    --group-names 'Default' \
    --query 'SecurityGroups[0].OwnerId' \
    --output text \
    --region ${AWS_Region})
# Use a temp bucket for templates in case the templates are too large.
line="template_bucket_name: thcp-${AppName}-${Environment}-turnlane-${AWS_ACCOUNT_ID}-${AWS_Region}"
echo $line >> $outfile
echo "Main sceptre config file looks like this:"
cat $outfile

# *************************************************************************
# Sync the pipeline directory with S3 bucket.
# *************************************************************************
echo "Syncing the pipeline folder if it exists."
. ./${TurnlaneDir}/support/create_temp_s3_function.sh
if [[ -d ${SourceDir}/pipeline ]]
then
  if [[ ! -z $Role ]]
  then 
    FunctionOpts="-i ${Role} -p ${AppName} -e ${Environment} -r ${AWS_Region} -b ${Version} -P ${SourceDir}/pipeline"
  else
    FunctionOpts="-p ${AppName} -e ${Environment} -r ${AWS_Region} -b ${Version} -P ${SourceDir}/pipeline"
  fi
  if [[ $Stage == "build" ]]
  then
    CreateandSyncTempBucket $FunctionOpts
    PipelineBucketName=$retval
    echo "***IMPORTANT Information*** your PipelineBucketName is stored in ${PipelineBucketName}"
  fi  
fi

# *************************************************************************
# Setup the Virtual Environment for Python
# *************************************************************************
echo "Setting up Virtual Environment"
virtualenv turnlane_virtenv
source turnlane_virtenv/bin/activate
pip install sceptre==${SCEPTRE_VERSION}
sceptrecommand="turnlane_virtenv/bin/sceptre"
pythoncommand="turnlane_virtenv/bin/python"
echo "Checking Sceptre Version"
if [[ $SCEPTRE_VERSION == 2* ]]
then 
  if [[ -d sceptre-ssm-resolver ]]
  then
    rm -rf sceptre-ssm-resolver
  fi
  echo "Detected Sceptre v2 - Install sceptre-ssm-resolver"
  git clone https://github.com/zaro0508/sceptre-ssm-resolver.git
  cd sceptre-ssm-resolver
  python setup.py install
  cd ..
else
  echo "Detected Sceptre v1"
  echo " - Install sceptre-ssm-resolver"
  wget -O turnlane_virtenv/lib/python2.7/site-packages/sceptre/resolvers/ssm.py https://raw.githubusercontent.com/cloudreach/sceptre/v1/contrib/ssm-resolver/ssm.py
  echo " - Install sceptre-s3-code plugin"
  rm -rf sceptre-zip-code-s3
  git clone https://github.com/cloudreach/sceptre-zip-code-s3.git
  cd sceptre-zip-code-s3
  #make deps
  cd ..
fi

if [ "$Stage" == "validate" ]; then
  echo "---------------------------------------------------"
  echo "Running Sceptre template validation"
  echo "---------------------------------------------------"
#  echo "Setting up Virtual Environment"
#  virtualenv turnlane_virtenv
#  source turnlane_virtenv/bin/activate
#  pip install sceptre==${SCEPTRE_VERSION}
#  sceptrecommand="turnlane_virtenv/bin/sceptre"
  $sceptrecommand --version
  for file in $(find ${SourceDir}/${configprefix}/${Environment}/* -type f -name '*.yaml' -not -name 'config.yaml') ; do
      stack=$(basename $file ".yaml")
      if [[ $SCEPTRE_VERSION == 2* ]]
      then 
         $sceptrecommand --debug --dir ${SourceDir} validate ${Environment}/$stack
      else
         $sceptrecommand --debug --dir $SourceDir validate-template $Environment $stack
      fi
      
      retVal=$?
      if [ $retVal -ne 0 ]; then
         echo "Error Code ${retVal}"
      fi
  done
fi

if [ "$Stage" == "teardown" ]; then
  echo "Run Sceptre delete-env"
  echo "---------------------------------------------------"
#  echo "Setting up Virtual Environment"
#  virtualenv turnlane_virtenv
#  source turnlane_virtenv/bin/activate
#  pip install sceptre==${SCEPTRE_VERSION}
#  sceptrecommand="turnlane_virtenv/bin/sceptre"
  $sceptrecommand --version
  $sceptrecommand --debug --dir $SourceDir delete-env $Environment
  retVal=$?
  if [ $retVal -ne 0 ]; then
     echo "Error Code ${retVal}"
  fi
fi

if [ "$Stage" == "build" ]; then
  echo "Running Sceptre Build"
  echo "---------------------------------------------------"
#  echo "Setting up Virtual Environment"
#  virtualenv turnlane_virtenv
#  source turnlane_virtenv/bin/activate
#  pip install sceptre==${SCEPTRE_VERSION}
#  sceptrecommand="turnlane_virtenv/bin/sceptre"
  $sceptrecommand --version
  pwd
  if [[ ! -z $StackName ]]
  then
    $sceptrecommand --debug --dir $SourceDir launch-stack $Environment $StackName
  else
    # Will need a better way of doing this
    if [[ $SCEPTRE_VERSION == "2.0.0" ]]
    then
      $sceptrecommand --debug --dir $SourceDir launch $Environment
    else
      $sceptrecommand --debug --dir $SourceDir launch-env $Environment
    fi
  fi
  retVal=$?
  if [ $retVal -ne 0 ]; then
     echo "Error Code ${retVal}"
  fi
fi

if [ "$Stage" == "exportvars" ]; then
  echo "Running Sceptre Export of Outputs to Env"
  echo "---------------------------------------------------"
#  echo "Setting up Virtual Environment"
#  set -a
#  virtualenv turnlane_virtenv
#  source turnlane_virtenv/bin/activate
#  pip install sceptre==${SCEPTRE_VERSION}
#  sceptrecommand="turnlane_virtenv/bin/sceptre"
  $sceptrecommand --version
  pwd
  if [[ ! -z $StackName ]]
  then
    $sceptrecommand --debug --dir $SourceDir describe-stack-outputs $Environment $StackName --export=envvar
    printenv
  else
    echo "--exportvars must also include --stack_name"
  fi
  retVal=$?
  if [ $retVal -ne 0 ]; then
     echo "Error Code ${retVal}"
  fi
  set +a
fi
# *************************************************************************
# Deactivate the Virtual Environment for Python
# *************************************************************************
echo "Deactivating the virtual environment."
deactivate
#rm -rf turnlane_virtenv

# *************************************************************************
# If requested, delete the temporary artifacts bucket
# Otherwise it is left
#*************************************************************************
if [[ $DeleteTempBucket == "true" && $Stage == "build" ]]
then
  echo "***Deleting the temporary bucket as requested. ***"
  . ${DIR}/support/delete_temp_s3_function.sh
  if [[ ! -z $Role ]]
  then 
    FunctionOpts="-i ${Role} -s ${PipelineBucketName}"
  else
    FunctionOpts="-s ${PipelineBucketName}"
  fi
  DeleteTempS3Bucket ${FunctionOpts}
fi
echo "Ending turnlane.sh script gracefully with code : ${retVal}"
exit $retVal
