#!/bin/bash

EVENT_SRC=$1
FUNCTION_ARN=$2
REGION=$3
TABLE_NAME=$4
RETCODE=0

echo "*** Retrieving latest stream arn from table $TABLE_NAME"
TABLE_CHECK=$(aws --region ${REGION} dynamodb describe-table --table-name ${TABLE_NAME})

if [ $? -eq 0 ]; then
  STREAM_ARN=$(echo $TABLE_CHECK | jq -r '.["Table"]["LatestStreamArn"]')

  if [ "$STREAM_ARN" = "null" ]; then
    echo "ERROR - no stream found for dynamodb table $TABLE_NAME"
    RETCODE=1
  else
    echo "STREAM_ARN set to $STREAM_ARN"
  fi
else
  echo "ERROR - unable to find dynamodb table $TABLE_NAME"
  RETCODE=1
fi


if [ $RETCODE -eq 0 ]; then
  echo "*** Updating event json file ($EVENT_SRC) with function and stream arn"
  jq --arg FUNCTION $FUNCTION_ARN --arg STREAM $STREAM_ARN '.["FunctionName"]=$FUNCTION | .["EventSourceArn"]=$STREAM' $EVENT_SRC > /tmp/s3_event.$$

  if [ -s /tmp/s3_event.$$ ]; then
    echo "Successfully updated function arn and event source arn in event source json file"
    mv /tmp/s3_event.$$ $EVENT_SRC
  else
    echo "Failed to modify function arn and event source arn in event source json file ($EVENT_SRC)"
    RETCODE=1
    rm /tmp/s3_event.$$
  fi
fi

if [ $RETCODE -eq 0 ]; then
  echo "*** Checking for existing event source mapping"
  UUID=$(aws --region ${REGION} lambda list-event-source-mappings --function-name ${FUNCTION_ARN} | jq --arg FUNCTION $FUNCTION_ARN  --arg EVENT $STREAM_ARN -r '.["EventSourceMappings"][] | select((.["FunctionArn"]==$FUNCTION) and (.["EventSourceArn"]==$EVENT)) | .["UUID"]')

  if [ -n "$UUID" ]; then

    echo "Existing event source mapping found."
    echo "UUID set to $UUID"
    echo "*** Retrieving updated values from event source json file ($EVENT_SRC)"

    ENABLED=$(cat $EVENT_SRC | jq -r '.["Enabled"]')
    echo "ENABLED set to $ENABLED"
    BATCH_SIZE=$(cat $EVENT_SRC | jq -r '.["BatchSize"]')
    echo "BATCH_SIZE set to $BATCH_SIZE"

    echo "*** Updating event source mapping between function $FUNCTION_ARN and event source $STREAM_ARN"
    if [ "$ENABLED" = "true" ]; then
      ENABLED="--enabled"
    else
      ENABLED="--no-enabled"
    fi
    EVENT_UPDATE=$(aws --region ${REGION} lambda update-event-source-mapping --uuid $UUID $ENABLED --batch-size $BATCH_SIZE)
    if [ $? -eq 0 ]; then
      echo "Successfully updated event source mapping"
    else
      echo "ERROR - failed to updated event source mapping between function $FUNCTION_ARN and dynamodbtable ${TABLE_NAME}'s stream $STREAM_ARN"
      RETCODE=1
    fi
  else
    echo "No existing event source mapping found."
    echo "*** Creating new event source mapping between function $FUNCTION_ARN and event source $STREAM_ARN"
    EVENT_ADD=$(aws --region ${REGION} lambda create-event-source-mapping --cli-input-json file://$EVENT_SRC)
    if [ $? -eq 0 ]; then
      echo "Successfully added new event source mapping for dynamodb table $TABLE_NAME"
    else
      echo "Failed to create event source mapping for dynamodb table $TABLE_NAME stream $STREAM_ARN and function $FUNCTION_ARN"
      RETCODE=1
    fi
  fi
fi

exit $RETCODE
