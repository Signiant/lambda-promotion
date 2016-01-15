#!/bin/bash

#Script for adding an s3 event source from a json document for a lambda function

#Questions / concerns
# - Permissions, updated in strust policy or at run time?
# - JSON file - filters or no filters
# - better failure

EVENT_SRC=$1
FUNCTION_ARN=$2
BUCKET=$3
RETCODE=0

#say whats happening
#Insert function arn in event json file
cat $EVENT_SRC | jq --arg ARN $FUNCTION_ARN '.["LambdaFunctionConfigurations"][]["LambdaFunctionArn"]=$ARN' > /tmp/s3_event.$$
if [ -s /tmp/s3_event.$$ ]; then
  echo "Success"
  mv /tmp/s3_event.$$ $EVENT_SRC
else
  echo "ERROR - failed to modify function ARN in json file $EVENT_SRC"
  RETCODE=1
  rm /tmp/s3_event.$$
fi

if [ $RETCODE -eq 0 ]; then
    #How to error check? Move to function creation?
    aws lambda add-permission --function-name $FUNCTION_ARN --region us-east-1 --statement-id s3_invoke --principal s3.amazonaws.com --action "lambda:InvokeFunction" --source-arn "arn:aws:s3:::${BUCKET}"
    NOTIFICATION_RESPONSE=$(aws s3api put-bucket-notification-configuration --bucket ${BUCKET} --notification-configuration file://$EVENT_SRC)
  if [ $? -eq 0 ]; then
    echo "Successfully created s3 bucket notification"
  else
    #Update message
    echo "ERROR - failed to create s3 bucket notification"
    RETCODE=1
  fi
fi
exit $RETCODE
