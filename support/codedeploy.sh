#!/bin/bash
export LOCALIP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
export INSTANCEID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null)
export AWS_REGION=`curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`            

echo "Turnlane:codedeploy.sh:INFO Setting Defaults......"
WAIT="false"
if [[ ! -z $2 ]]; then 
  if [[ $2 == "true" ]]
  then 
    WAIT="true"
    echo "Turnlane:codedeploy.sh:WARN *** I WILL WAIT FOR CODEDEPLOY DEPLOYMENT TO COMPLETE ***"
  fi 
fi 

SAVEDIR=$(pwd)
if [[ ! -d $TurnlaneDir ]]
then
  echo "Turnlane:codedeploy.sh:ERROR Directory not found."
  exit 1
fi 
if [[ ! -d $SourceDir/pipeline ]]
then
  echo "Turnlane:codedeploy.sh:WARN Directory not found."
  exit 0
fi 

cd $SourceDir/pipeline/codedeploy
for d in */
do
  shopt -s extglob
  CD_APPNAME=${d%%+(/)}
  echo "Found Codedeploy Application : "$CD_APPNAME
  if [[ ! -f $CD_APPNAME/appspec.yml ]]
  then 
    echo "Turnlane:codedeploy.sh:ERROR No appspec.yml file found."
    exit 2
  fi
  # Copying the full repository
  tar cvf /tmp/repository.tar -C $SAVEDIR/$SourceDir .
  cp /tmp/repository.tar $CD_APPNAME
  cd $CD_APPNAME
  # The key file must contain JSON with Parameter Name in it.
  KEYFILE=thcp_spec.json
  if [[ ! -f $KEYFILE ]]
  then
    echo "KEYFILE: ${KEYFILE} does not exist."
    exit 1
  fi 

  AppNameParam=$(jq --raw-output '.AppNameSSMParameter' $KEYFILE)
  if [[ -z AppNameParam ]]
  then
    echo "Could not ret AppnameParam:$AppNameParam"
    cat $KEYFILE 
    exit 1
  fi 
  DeploymentGroupParam=$(jq --raw-output '.DeploymentGroupSSMParameter' $KEYFILE)
  if [[ -z DeploymentGroupParam ]]
  then
    echo "Could not ret DeploymentGroupParam: $DeploymentGroupParam"
    cat $KEYFILE 
    exit 1
  fi 
  
  ApplicationName=$(aws ssm get-parameter --name $AppNameParam --region $AWS_REGION | jq --raw-output '.Parameter .Value')
  if [[ -z ApplicationName ]]
  then
    exit 1
  else 
    echo "Retrieved ApplicationName:"$ApplicationName
  fi 
  DeploymentGroupName=$(aws ssm get-parameter --name $DeploymentGroupParam --region $AWS_REGION | jq --raw-output '.Parameter .Value')
  if [[ -z DeploymentGroupName ]]
  then
    exit 1
  else 
    echo "Retrieved DeploymentGroupName:"$DeploymentGroupName
  fi 

  AppNameRevision=$(jq --raw-output '.Description' $KEYFILE)
  if [[ -z AppNameRevision ]]
  then
    AppNameRevision="Revision Update"
  fi 

  BucketName=$(aws ssm get-parameter --name $1 --region $AWS_REGION | jq --raw-output '.Parameter .Value')
  S3Location="s3://${BucketName}/pipeline/codedeploy/${CD_APPNAME}/${CD_APPNAME}.zip"
  echo "Attempting to push the App Revision to S3: ${S3Location}"
  aws deploy push \
    --region ${AWS_REGION} \
    --application-name ${ApplicationName} \
    --description "${AppNameRevision}" \
    --ignore-hidden-files \
    --s3-location ${S3Location} \
    --source . 
  echo "Done push."

  echo "Attempting to create a Deployment for your revision."
  DEPLOYMENTJSON=$(aws deploy create-deployment \
    --region ${AWS_REGION} \
    --application-name $ApplicationName \
    --deployment-group-name $DeploymentGroupName \
    --s3-location bucket=${BucketName},key="pipeline/codedeploy/${CD_APPNAME}/${CD_APPNAME}.zip",bundleType=zip)
  echo $DEPLOYMENTJSON
  DEPLOYMENT=$(echo $DEPLOYMENTJSON | jq --raw-output '.deploymentId')
  
  if [[ $WAIT == "true" ]]
  then 
    # We wait up to 5 mins
    echo "Waiting for DeploymentId: "$DEPLOYMENT
    countdown=300
    MYSTATUS="default"
    while [[ "$MYSTATUS" != "Succeeded" && $countdown -ne 0 ]]
    do
      MYSTATUS=$(aws deploy get-deployment --region ${AWS_REGION} --deployment-id "$DEPLOYMENT" --output text --query 'deploymentInfo.status')
      echo "Current Status=${MYSTATUS} Waiting.....${countdown}"
      sleep 1
      ((countdown--))
    done
  fi 
  echo "*************************************************************************"
  echo "Deployment Final Status: "$MYSTATUS " for application: "$CD_APPNAME
  echo "*************************************************************************"
  cd .. 
done
cd $SAVEDIR