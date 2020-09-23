CreateandSyncTempBucket () {
#
# Creates a temporary S3 Bucket based on parameters passed to script.
#
# Optionally syncs a local path to the created bucket
#
# Basic usage: CreateandSyncTempBucket <-p|--project> <-e|--environment> <-i|--iam_role> <-r|--region> <-b|--buildnumber> <-P|projectpath>
#
# Constructs S3 Bucket Name Based on :
#
# thcp-pipeline-temp-<project>-<environent>-<build_number>-<region>
#
# Created bucket name is stored in Parameter Store :
#
# /thcp/pipeline/turnlane/<project>/<environment>/<build_number>
#
#
# Now check the rest of the command line which can override variables.
#

#echo "You start with $# positional parameters"
# Loop until all parameters are used up
#while [ "$1" != "" ]; do
#    echo "Parameter 1 equals $1"
#    echo "You now have $# positional parameters"
#    # Shift all the parameters down by one
#    shift
#done
#exit 0
local Role=''
local POSITIONAL=()
while [[ $# -gt 0 ]]
do
local key="$1"
case $key in
    -p|--project)
    local Project="$2"
    shift # past argument
    shift # past value
    ;;
    -i|--iam_role)
    local Role="$2"
    shift # past argument
    shift # past value
    ;;
    -e|--environment)
    local BuildBranch="$2"
    shift # past argument
    shift # past value
    ;;
    -r|--region)
    local AWS_Region="$2"
    shift # past argument
    shift # past value
    ;;
    -b|--buildnumber)
    local BuildNumber="$2"
    shift # past argument
    shift # past value
    ;;
    -P|--projectpath)
    local ProjectPath="$2"
    shift
    shift
    ;; 
    *)    # unknown option
    echo "Unknown Option "${key}
    exit 9
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [[ ! -z $Role ]]
then
  echo "-------------------------------------------------------------"
  echo " SWITCHING ROLES NOW"
  echo " Role: "${Role}
  echo "-------------------------------------------------------------"
  local temp_role=$(aws sts assume-role --role-arn $Role --role-session-name bootstrapping)
  export AWS_ACCESS_KEY_ID=$(echo $temp_role | jq .Credentials.AccessKeyId | xargs)
  export AWS_SECRET_ACCESS_KEY=$(echo $temp_role | jq .Credentials.SecretAccessKey | xargs)
  export AWS_SESSION_TOKEN=$(echo $temp_role | jq .Credentials.SessionToken | xargs)
  echo "AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID
  echo "AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY
  echo "AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN
fi

#AWS_ACCOUNT_ID=$(aws ec2 describe-security-groups \
#    --group-names 'Default' \
#    --query 'SecurityGroups[0].OwnerId' \
#    --output text \
#    --region ${AWS_Region})
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region ${AWS_Region})

#
# Create the S3 Bucket
#
echo "Bucket Name based on:"
echo "Project="${Project}
echo "BuildBranch="${BuildBranch}
echo "BuildNumber="${BuildNumber}
echo "AWSAccountId="${AWS_ACCOUNT_ID}
echo "Region="${AWS_Region}

FixedProject=`echo $Project | sed s:/:-:g`
FixedBuildBranch=`echo $BuildBranch | sed s:/:-:g`
BucketName="thcp-pipeline-temp-${FixedProject}-${FixedBuildBranch}-${BuildNumber}-${AWS_ACCOUNT_ID}"
SSMParamName="/thcp/pipeline/turnlane/${FixedProject}/${BuildBranch}/${BuildNumber}"
echo "Resulting BucketName: "${BucketName}

aws s3 mb s3://${BucketName} --region ${AWS_Region} || true
if aws s3 ls "s3://${BucketName}" --region ${AWS_Region} 2>&1 | grep -q 'An error occurred'
then
  echo "Bucket Creation Failed."
  exit 70
else
   SSMParamName="/thcp/pipeline/turnlane/${FixedProject}/${BuildBranch}/${BuildNumber}"
   echo "Storing the BucketName in AWS Parameter:"${SSMParamName} 
   aws ssm put-parameter --name ${SSMParamName} --value "${BucketName}" --type String --overwrite --region ${AWS_Region}
   if [[ ! -z ${ProjectPath} ]]
   then
     echo "Syncing ${ProjectPath} with ${BucketName}"
     aws s3 sync ${ProjectPath} s3://${BucketName} --region ${AWS_Region}
   fi
fi
retval=${SSMParamName}
} # End Function
