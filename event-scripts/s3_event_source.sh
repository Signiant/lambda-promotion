#!/bin/bash

#Script for adding an s3 event source from a json document for a lambda function
EVENT_SRC=$1
FUNCTION_ARN=$2
REGION=$3
BUCKET=$4
RETCODE=0

#say whats happening
#Insert function arn in event json file
echo "*** Updating event json file ($EVENT_SRC) with function arn ($FUNCTION_ARN)"
cat $EVENT_SRC | jq --arg ARN $FUNCTION_ARN '.["LambdaFunctionConfigurations"][]["LambdaFunctionArn"]=$ARN' > /tmp/s3_event.$$
if [ -s /tmp/s3_event.$$ ]; then
  echo "Successfully set function arn in event source json file"
  mv /tmp/s3_event.$$ $EVENT_SRC
else
  echo "ERROR - failed to modify function ARN in json file $EVENT_SRC"
  RETCODE=1
  rm /tmp/s3_event.$$
fi

if [ $RETCODE -eq 0 ]; then
    NOTIFICATION_RESPONSE=$(aws --region ${REGION} s3api put-bucket-notification-configuration --bucket ${BUCKET} --notification-configuration file://$EVENT_SRC)
  if [ $? -eq 0 ]; then
    echo "Successfully created/update s3 bucket notification"
  else
    #Update message
    echo "ERROR - failed to create/update s3 bucket notification"
    RETCODE=1
  fi
fi
exit $RETCODE
