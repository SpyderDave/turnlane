#!/bin/bash
#
# turnlane.sh
#
# usage <-B|--BAMBOO> <-i|--iam_role> <-v|--version version_number> -e|--environment env_name -a|--app_name application_name <-t|--turnlane_dir turnlane_dir> \
#       <-s|--source_dir source_dir> <-r|--region AWS_Region> <-b|--build_stage <build|validate|exportvars|teardown|codedeploy|reports> 
#        <-z|--sceptre_version version>
#       <-d|--delete_temp_bucket true|false> <-R|--release_values> <-m|--branch_name BranchName> <--skip_sam_apps true|false> <-W|--wait>
#
# turnlane.sh 
exists()
{
  command -v "$1" >/dev/null 2>&1
}
echo "**********************************************************************************"
echo "**********************************************************************************"
echo "**********************************************************************************"
echo "HERE IS THE ENVIRONMENT. USE THIS FOR TROUBLESHOOTING"
printenv
echo "**********************************************************************************"
echo "**********************************************************************************"
echo "**********************************************************************************"
MYID=$(id)
echo "Turnlane: Running as user: "$MYID
TURNLANEDIR="$( cd $(dirname $0) >/dev/null 2>&1 && pwd )"
echo "Turnlane Running Directory: "$TURNLANEDIR 
cat ${TURNLANEDIR}/logos/turnlane_logo.txt
#set -x
echo "Setting Defaults"
retVal=0
Role=""
AWS_Region="ca-central-1"
StackName=""
SCEPTRE_VERSION=1.4.2
SCEPTRE_VALIDATE="validate-template"
USE_BAMBOO_VARS="false"
DeleteTempBucket=false
SKIPSAM=false
WAITER=false 

# Import Bamboo Variables - these can be overridden by command line args
. ${TURNLANEDIR}/support/import_bamboo_vars.sh
ImportBambooVars

# Now check the rest of the command line which can override variables.
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -R|--release_values)
    RELEASE_VALUES="$2"
    shift # past argument
    shift # past value
    ;;
    -z|--sceptre_version)
    SCEPTRE_VERSION="$2"
    shift # past argument
    shift # past value
    ;;
    -i|--iam_role)
    Role="$2"
    shift # past argument
    shift # past value
    ;;
    -v|--version)
    Version="$2"
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
    -t|--turnlane_dir)
    TurnlaneDir="$2"
    shift # past argument
    shift # past value
    ;;
    -s|--source_dir)
    SourceDir="$2"
    shift # past argument
    shift # past value
    ;;
    -n|--stack_name)
    StackName="$2"
    shift # past argument
    shift # past value
    ;;
    -r|--region)
    AWS_Region="$2"
    shift # past argument
    shift # past value
    ;;
    -b|--build_stage)
    Stage="$2"
    shift # past argument
    shift # past value
    ;;
    -d|--delete_temp_bucket)
    DeleteTempBucket="$2"
    shift # past argument
    shift # past value
    ;;
    -m|--branch_name)
    BranchName="$2"
    shift # past argument
    shift # past value
    ;;
    -W|--wait)
    WAITER="$2"
    shift # past argument
    shift # past value
    ;;    
    --skip_sam_apps)
    SKIPSAM="$2"
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

#
# Check for Python 3 availability first.
#    if python3 exists use it by default
#    otherwise python(2)
#
echo "Verifying that we have Python Pip and Virtualenv installed."

#hash python 2>/dev/null || { echo >&2 "I require python but it's not installed.  Aborting."; exit 6; }
#hash virtualenv 2>/dev/null || { echo >&2 "I require virtualenv but it's not installed.  Aborting."; exit 7; }
#hash pip 2>/dev/null || { echo >&2 "I require pip but it's not installed.  Aborting."; exit 8; }

if which python3 2>>/dev/null; then 
  PYTHONCMD=python3
else   
  if which python 2>/dev/null; then
    PYTHONCMD=python
    if which virtualenv 2>/dev/null; then
      virtualenv --version
    else
      exit 7
    fi
  else 
    exit 6
  fi
fi
echo "*******************************************************************"
echo "Python Version: "
echo "*******************************************************************"
$PYTHONCMD --version  

if which pip3 2>/dev/null; then 
  PIPCMD="pip3" 
else 
  if which pip 2>/dev/null; then
    PIPCMD="pip"
  else
    exit 8
  fi
fi 

echo "*******************************************************************"
echo "Pip Version: "
echo "*******************************************************************"
$PIPCMD --version 

echo "***********************"
echo "Setting up Sceptre run."
echo "***********************"

generatorprefix="generator"
templatesprefix="templates"
configprefix="config"
echo "generatorprefix=${generatorprefix}"
echo "templateprefix=${templateprefix}"
echo "configprefix=${configprefix}"

echo "Checking source directory hierarchy."
if [[ $Stage != "codedeploy" && $Stage != "reports" ]]
then 
  echo "Stage = "$Stage 
  if [[ $Stage != "codedeploy" && ! -d "${SourceDir}/${configprefix}/${Environment}" ]]
  then
    echo "ERROR Source Directory Hierarchy is incorrect for proper sceptre execution."
    echo "${SourceDir}/${configprefix}/${Environment} DOES NOT EXIST"
    exit 5
  fi
fi
#
# If Version is specified this respresents a build # which needs to be included in generated stack names. 
#
# Update the sceptre config only if this is not a codedeploy run 
if [[ $Stage != "codedeploy " && $Stage != "reports" ]]
then 
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
fi

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
  if [[ ! $AWS_ACCESS_KEY_ID ]]
  then 
    echo "****************************************************************************************"
    echo "****************************************************************************************"
    echo "****************************************************************************************"
    echo "* FAILED TO ASSUME ROLE"
    echo "****************************************************************************************"
    echo "****************************************************************************************"
    echo "****************************************************************************************"
    exit 99
  fi
fi

# Set the AWS Account Number only after Assuming the Correct Role
echo "Obtaining the AWS Account Number"
#AWS_ACCOUNT_ID=$(aws ec2 describe-security-groups \
#    --group-names 'Default' \
#    --query 'SecurityGroups[0].OwnerId' \
#    --output text \
#    --region ${AWS_Region})
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region ${AWS_Region})

AWS_ACCOUNT_ALIAS=$(aws iam list-account-aliases \
    --region ${AWS_Region} \
    --query 'AccountAliases[0]' \
    --output text) 

if [[ $Stage != "codedeploy " && $Stage != "reports" ]]
then 
  # Use a temp bucket for templates in case the templates are too large.
  FixedEnvironment=`echo $Environment | sed s:/:-:g`
  line="template_bucket_name: thcp-${AppName}-${FixedEnvironment}-sceptretemplates-${AWS_ACCOUNT_ID}"
  echo $line >> $outfile
  echo "Main sceptre config file looks like this:"
  cat $outfile
fi 
# *************************************************************************
# Sync the pipeline directory with S3 bucket.
# *************************************************************************
echo "************************************************************************************"
echo "Turnlane: Syncing the pipeline folder if it exists."
echo "************************************************************************************"
if [[ -d ${SourceDir}/pipeline ]]
then
  echo "pipeline directory found."
  source ${TurnlaneDir}/support/create_temp_s3_function.sh
  if [[ ! -z $Role ]]
  then 
    FunctionOpts="-i ${Role} -p ${AppName} -e ${Environment} -r ${AWS_Region} -b ${Version} -P ${SourceDir}/pipeline"
  else
    FunctionOpts="-p ${AppName} -e ${Environment} -r ${AWS_Region} -b ${Version} -P ${SourceDir}/pipeline"
  fi
  if [[ $Stage == "build" ]] || [[ $Stage == "teardown" ]] || [[ $Stage == "codedeploy" ]]
  then
    CreateandSyncTempBucket $FunctionOpts
    PipelineBucketName=$retval
    echo "***IMPORTANT Information*** your PipelineBucketName is stored in ${PipelineBucketName}"
  fi
fi

echo "*************************************************************************"
echo " Setup the Virtual Environment for Python"
echo "*************************************************************************"
if [[ -d turnlane_virtenv ]]
then 
  rm -rf turnlane_virtenv
fi 
if [[ $PYTHONCMD == "python" ]] 
then 
  virtualenv --system-site-packages turnlane_virtenv 
else 
  $PYTHONCMD -m venv --system-site-packages turnlane_virtenv
fi 
echo "**** Activating ****"
source turnlane_virtenv/bin/activate
echo "Upgrading PIP in the virtual environment."
$PIPCMD install --upgrade $PIPCMD

if [[ $Stage != "codedeploy " && $Stage != "reports" ]]
then 
  $PIPCMD install sceptre==${SCEPTRE_VERSION} --quiet
  sceptrecommand="turnlane_virtenv/bin/sceptre"
  $PIPCMD install sceptre-ssm-resolver
  echo "Checking Sceptre Version"
  if [[ $SCEPTRE_VERSION == 2* ]]
  then 
    cat ${TURNLANEDIR}/logos/sceptrev2.txt
  else
    echo "Detected Sceptre v1"
    echo " - Install sceptre-ssm-resolver"
    # This is really a band aid because we dont know where the python lib folder is yet
    wget -O turnlane_virtenv/lib/python2.7/site-packages/sceptre/resolvers/ssm.py https://raw.githubusercontent.com/cloudreach/sceptre/v1/contrib/ssm-resolver/ssm.py
    wget -O turnlane_virtenv/lib/python3.6/site-packages/sceptre/resolvers/ssm.py https://raw.githubusercontent.com/cloudreach/sceptre/v1/contrib/ssm-resolver/ssm.py
    wget -O turnlane_virtenv/lib/python3.7/site-packages/sceptre/resolvers/ssm.py https://raw.githubusercontent.com/cloudreach/sceptre/v1/contrib/ssm-resolver/ssm.py
    echo " - Install sceptre-s3-code plugin"
    rm -rf sceptre-zip-code-s3
    git clone https://github.com/cloudreach/sceptre-zip-code-s3.git
    cd sceptre-zip-code-s3
    #make deps
    cd ..
  fi
fi 

# *************************************************************************
# Determine if this is Codedeploy Run
# *************************************************************************
if [[ $Stage == "codedeploy" && -d ${SourceDir}/pipeline/codedeploy ]]
then
  echo "************************************************************************************"
  echo "Turnlane: Processing Codedeploy"
  echo "************************************************************************************"
  cat ${TURNLANEDIR}/logos/codedeploy.txt  
  ${TurnlaneDir}/support/codedeploy.sh ${PipelineBucketName} ${WAITER}
fi

# *************************************************************************
# Determine if this is Reports Run
# *************************************************************************
if [[ $Stage == "reports" ]]
then
  if [[ ! -d artifacts ]]
  then
    mkdir artifacts
  else 
    rm -rf artifacts/*
  fi 
  echo "************************************************************************************"
  echo "Turnlane: PMapper maps the IAM Roles and Visualizes"
  echo "************************************************************************************"
  #$PIPCMD install principalmapper
  #pmapper graph --create
  #pmapper visualize --filetype png 
  #pmapper analysis --output-type text >artifacts/IAM_Analysis.txt 
  #mv *.png artifacts/
  echo "************************************************************************************"
  echo "Turnlane: Processing Scoutsuite"
  echo "************************************************************************************"
  update-alternatives --set gcc /usr/bin/gcc-48
  $PIPCMD install cryptography==2.8
  $PIPCMD install scoutsuite 
  $PIPCMD install humanfriendly==4.18 coloredlogs==10.0 setuptools==40.3.0
  echo "************************************************************************************"
  if [[ -d scoutsuite-report ]]
  then 
    rm -rf ./scoutsuite-report* 
  fi
  scout aws --force 
  if [[ -d scoutsuite-report ]]
  then
    zip artifacts/scoutsuite-report.zip -r ./scoutsuite-report 
    mv scoutsuite-report artifacts/
  fi 
  echo "************************************************************************************"
  echo "Turnlane: Processing Cloudmapper"
  echo "************************************************************************************"
  if [[ -d cloudmapper ]]
  then 
    echo "Removing existing cloudmapper directory."
    rm -rf cloudmapper 
  fi
  git clone https://github.com/duo-labs/cloudmapper.git 
  cd cloudmapper 
  $PIPCMD install -r requirements.txt
  #$PIPCMD install pipenv 
  #pipenv install --skip-lock
  #pipenv shell 
  echo "Adding "$AWS_ACCOUNT_ALIAS" with ID "$AWS_ACCOUNT_ID" to config.json"
  $PYTHONCMD cloudmapper.py configure add-account --config-file config.json --name ${AWS_ACCOUNT_ALIAS} --id ${AWS_ACCOUNT_ID}
  echo "Running Cloudmapper Data Collection"
  $PYTHONCMD cloudmapper.py collect --account ${AWS_ACCOUNT_ALIAS} 
  echo "Running Cloudmapper Network Visualization for "${AWS_Region}
  $PYTHONCMD cloudmapper.py prepare --account ${AWS_ACCOUNT_ALIAS} --regions ${AWS_Region}
  echo "Running Cloudmapper Report for "${AWS_Region}
  $PYTHONCMD cloudmapper.py report --config config.json --accounts ${AWS_ACCOUNT_ALIAS} 
  cd .. 
  if [[ -d cloudmapper ]]
  then
    zip artifacts/cloudmapper-reports.zip -r ./cloudmapper
  fi 
fi

if [ "$Stage" == "validate" ]; then
  echo "---------------------------------------------------"
  echo "Running Sceptre template validation"
  echo "---------------------------------------------------"
  CWD=$(pwd)
  echo "Current working directory: "$CWD
  $sceptrecommand --version
  for file in $(find ${SourceDir}/${configprefix}/${Environment}/* -type f -name '*.yaml' -not -name 'config.yaml') ; do
      stack=$(basename $file ".yaml")
      if [[ ${SCEPTRE_VERSION:0:1} == "2" ]]
      then 
         echo "Validating stack: "$file
         $sceptrecommand --debug --dir ${SourceDir} validate $Environment/$stack 
         #cat ${TURNLANEDIR}/logos/cost-estimate.txt 
         #$sceptrecommand --debug --dir ${SourceDir} estimate-cost ${Environment}/$stack
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
  $sceptrecommand --version
  echo "Run Sceptre delete"
  echo "---------------------------------------------------"
  if [[ ${SCEPTRE_VERSION:0:1} == "2" ]]
  then 
    $sceptrecommand --debug --dir $SourceDir delete --yes $Environment    
  else 
    $sceptrecommand --debug --dir $SourceDir delete-env $Environment
  fi
  retVal=$?
  if [ $retVal -ne 0 ]; then
     echo "Error Code ${retVal}"
  fi
fi

# Determine if there are any SAM Apps to build.
if [[ $SKIPSAM == "false" && -d ${SourceDir}/sam-apps ]] 
then 
  SAMDIR="${SourceDir}/sam-apps"
elif [[ $SKIPSAM == "false" && -d ${SourceDir}/$Environment/sam-apps ]] 
then
  SAMDIR="${SourceDir}/$Environment/sam-apps"
fi

if [ "$Stage" == "build" ]; then
  if [[ -d $SAMDIR ]] 
  then
    cat ${TURNLANEDIR}/logos/sam-builder.txt  
    echo "---------------------------------------------------"
    echo "Installing the AWS SAM CLI"
    echo "---------------------------------------------------"
    SAVED_VENV=$VIRTUAL_ENV
    if [[ ! -z $SAVED_VENV ]]
    then 
      echo "Deactivating VIRTUAL Environment $SAVED_VENV"
      deactivate
      if [[ $PYTHONCMD == "python" ]] 
      then 
        virtualenv --system-site-packages sam_cli_venv
      else 
        $PYTHONCMD -m venv --system-site-packages sam_cli_venv 
      fi 
      echo "**** Activating ****"
      source sam_cli_venv/bin/activate
    fi 
    $PIPCMD install aws-sam-cli
    echo "---------------------------------------------------"
    echo "SAM Builder will build the following applications:"
    echo "---------------------------------------------------"
    SAVEDIR=$(pwd)
    echo "SAVEDIR="$SAVEDIR
    echo "SAMDIR="$SAMDIR
    myBucketName=$(aws ssm get-parameters --region ${AWS_Region} --name ${PipelineBucketName} | awk '/Value/ {print $2}' | sed 's/[",]//g')
    cd $SAMDIR
    for d in */
    do 
      shopt -s extglob
      SAMAPPNAME=${d%%+(/)}
      echo "."
      echo "*"
      echo "Building application: "$SAMAPPNAME
      echo "*"      
      cd $SAMAPPNAME
      sam --version 
      ##if [[ -f requirements.txt || -f package.json ]]
      ##then 
      sam build 
      ##fi 
      sam package --output-template-file $SAMAPPNAME.packaged.yaml --s3-bucket $myBucketName
      PACKAGED_TEMPLATE_FULLFILENAME=${SAVEDIR}/${SAMDIR}/${SAMAPPNAME}/$SAMAPPNAME.packaged.yaml
      SAM_SCEPTRE_CONFIGFILE=${SAVEDIR}/${SourceDir}/${configprefix}/${Environment}/$SAMAPPNAME.yaml
      if [[ ! -f $SAM_SCEPTRE_CONFIGFILE ]]
      then 
         echo "****************************************************************************************"
         echo "***ERROR*** Turnlane: Could not find : "$SAM_SCEPTRE_CONFIGFILE
         echo "****************************************************************************************"         
      else 
        echo "Replacing Template Path in Sceptre Config: " $SAM_SCEPTRE_CONFIGFILE
        echo "Before:"
        cat $SAM_SCEPTRE_CONFIGFILE
        sed -i "/template_path:/c\template_path: $PACKAGED_TEMPLATE_FULLFILENAME" $SAM_SCEPTRE_CONFIGFILE
        echo "After:"
        cat $SAM_SCEPTRE_CONFIGFILE
      fi 
      cd ..
    done 
    cd $SAVEDIR
    echo "."
    echo "Re-Activating the saved virtual environment."
    deactivate
    source $SAVED_VENV/bin/activate
  fi
  echo .
  echo "*************************************************************************************"
  echo "Looking for Terraform stuff"
  echo "*************************************************************************************"
  SAVEDIR=$(pwd)
  if [[ -d ${SourceDir}/terraform ]] 
  then 
    cd ${SourceDir}/terraform
    for d in */
    do 
      shopt -s extglob
      TFAPPNAME=${d%%+(/)}
      echo "Found Terraform Application: ${TFAPPNAME}"
      cd $TFAPPNAME
      if [[ -f tfvars.sh ]]
      then 
        source ./tfvars.sh
      fi 
      terraform init 
      terraform apply -auto-approve
    done 
    cd $SAVEDIR
  fi

  echo "**** Activating the Virtual Environment ****"
  source turnlane_virtenv/bin/activate
  echo "."
  echo "---------------------------------------------------"
  echo "Turnlane: Running Sceptre Build"
  echo "---------------------------------------------------"
  $sceptrecommand --version
  
  if [[ ! -z $StackName ]]
  then
    $sceptrecommand --debug --dir $SourceDir launch-stack $Environment $StackName
  else
    if [[ ${SCEPTRE_VERSION:0:1} == "2" ]]
    then
      echo "Running ${sceptrecommand} with SourceDir=${SourceDir} and Environment=${Environment}"
      pwd
      $sceptrecommand --debug --dir $SourceDir launch --yes $Environment
      # $sceptrecommand --debug --dir $SourceDir launch --yes $SourceDir/$configprefix/$Environment
    else
      $sceptrecommand --debug --dir $SourceDir launch-env $Environment
    fi
  fi
  retVal=$?
  echo "Turnlane: Sceptre build run completed."
  if [ $retVal -ne 0 ]; then
     echo "Turnlane: Sceptre Error Code ${retVal}"
  else
     echo "Turnlane: Successful Sceptre execution."
  fi
fi

if [ "$Stage" == "exportvars" ]; then
  echo "Running Sceptre Export of Outputs to Env"
  echo "---------------------------------------------------"
  $sceptrecommand --version
  
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

if [ "$Stage" == "release" ]; then
  echo "---------------------------------------------------"
  echo "Running Release Stage"
  echo "---------------------------------------------------"
  
  if [[ -z $StackName ]]
  then
    echo "*** RELEASE ERROR *** Stackname needed."
    exit 3
  fi

  if [[ ${SCEPTRE_VERSION:0:1} == "2" ]]
  then
    echo "Environment = "$Environment
    echo "StackName = "$StackName
    $sceptrecommand --version
    eval $($sceptrecommand --dir $SourceDir --debug --ignore-dependencies list outputs "$Environment/${StackName}.yaml" --export=envvar)
    echo "***RELEASE PROCESS*** - done obtaining Sceptre env vars"
    printenv | grep SCEPTRE
    OIFS=$IFS 
    IFS=',' read ELBDNS ELBZONEID TARGETRECORD ZONEID <<< $RELEASE_VALUES
    IFS=$OIFS

    echo "Getting the sceptre variables."
    ELBDNS_VALUENAME="SCEPTRE_"$ELBDNS
    ELBDNS_VALUE=${!ELBDNS_VALUENAME}
    ELBZONEID_VALUENAME="SCEPTRE_"$ELBZONEID
    ELBZONEID_VALUE=${!ELBZONEID_VALUENAME}
    echo "Found release values:"
    echo "ELBDNS_VALUE="$ELBDNS_VALUE" from "$ELBDNS_VALUENAME
    echo "ELBZONEID_VALUE="$ELBZONEID_VALUE" from "$ELBZONEID_VALUENAME

    if [ ! -z $ELBDNS_VALUE ] && [ ! -z $ELBZONEID_VALUE ]
    then 
      echo "*** RELEASE PROCESS *** Creating json file for update."
      cat >/tmp/release-update-route53-alias.json<<EOF
{
"Comment": "Turnlane release creating Alias resource record sets in Route 53",
"Changes": [
{
    "Action": "UPSERT",
    "ResourceRecordSet": {
        "Name": "${TARGETRECORD}",
        "Type": "A",
        "AliasTarget":{
            "HostedZoneId": "${ELBZONEID_VALUE}",
            "DNSName": "${ELBDNS_VALUE}",
            "EvaluateTargetHealth": false
        }}
    }]
}
EOF
      echo "***RELEASE PROCESS*** Here's your R53 JSON file."
      cat /tmp/release-update-route53-alias.json
      echo "Executing Route53 Change Request"
      aws route53 change-resource-record-sets --hosted-zone-id $ZONEID --change-batch file:///tmp/release-update-route53-alias.json
    else
      echo "*** RELEASE ERROR *** Could not obtain values from stack."
      exit 4
    fi # End check values
  else 
    # Sceptre v1 code goes here.
    echo "***RELEASE PROCESS*** Not implemented for sceptre v1"
  fi # End check sceptre version
fi # end check build stage




# *************************************************************************
# Deactivate the Virtual Environment for Python
# *************************************************************************
echo "Deactivating the virtual environment."
deactivate

# *************************************************************************
# If requested, delete the temporary artifacts bucket
# Otherwise it is left
# *************************************************************************
if [[ $DeleteTempBucket == "true" && $Stage == "build" ]] || [[ $DeleteTempBucket == "true" && $Stage == "teardown" ]]
then
  echo "***Deleting the temporary bucket as requested. ***"
  echo "***The parameter contains bucket name is ${PipelineBucketName}. ***"
  . ${TURNLANEDIR}/support/delete_temp_s3_function.sh
  if [[ ! -z $Role ]]
  then 
    FunctionOpts="-i ${Role} -s ${PipelineBucketName}"
  else
    FunctionOpts="-s ${PipelineBucketName}"
  fi
DeleteTempS3Bucket ${FunctionOpts}
fi

# In some cases, when run as root (aka docker) we need to ensure that generated files 
# have the correct ownership.
echo "*************************************************************************"
echo "Checking File ownership"
echo "*************************************************************************"
MYUSER=$(stat -c '%u' $SourceDir)
MYGROUP=$(stat -c '%g' $SourceDir)
chown -R ${MYUSER} *
chgrp -R ${MYGROUP} *

# *************************************************************************
# Ending Turnlane.sh script
# *************************************************************************
echo "Ending turnlane.sh script gracefully with code : ${retVal}"
exit $retVal

