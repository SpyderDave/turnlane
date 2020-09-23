DeleteTempS3Bucket () {
#
# Creates a temporary S3 Bucket based on parameters passed to script.
#
# Optionally syncs a local path to the created bucket
#
# Basic usage: CreateandSyncTempBucket <-p|--project> <-e|--environment> <-i|--iam_role> <-r|--region> <-b|--buildnumber> <-P|projectpath>
#
# Deletes the Temp S3 bucket whose name is in parameter store parameter passed as an argument here.
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
    -s|--SSMParamName)
    local SSMParamName="$2"
    shift # past argument
    shift # past value
    ;;
    -i|--rolearn)
    local Role="$2"
    shift # past argument
    shift # past value
    ;;
    -r|--region)
    local Region="$2"
    shift # past argument
    shift # past value
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

if [[ -z $SSMParamName ]]
then
  echo "Error : No SSMParamName passed"
  exit 1
fi
if [[ -z $Region ]]
then
  Region="ca-central-1"
fi

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
local myBucketName=$(aws ssm get-parameters --region ${Region} --name ${SSMParamName} | awk '/Value/ {print $2}' | sed 's/[",]//g')
echo "The bucket name is ${myBucketName}"
echo "**********************************************************************************************************"
echo "*           DELETING BUCKET" ${myBucketName} 
echo "**********************************************************************************************************"
aws s3 rb s3://${myBucketName} --force

echo "**********************************************************************************************************"
echo "*           DELETING SSM Parameter" ${SSMParamName} 
echo "**********************************************************************************************************"
aws ssm delete-parameter --region ${Region} --name ${SSMParamName}
} # End Function
