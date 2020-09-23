#!/bin/bash
export LOCALIP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
export INSTANCEID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null)
export SPLUNK_USER=splunk
export AWS_REGION=`curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`            
