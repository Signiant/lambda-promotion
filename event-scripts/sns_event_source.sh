#!/bin/bash

EVENT_SRC=$1
FUNCTION_ARN=$2
REGION=$3
TOPIC_NAME=$4
RETCODE=0

FUNCTION_ARN_SPLIT=(${FUNCTION_ARN//:/ })
ACCOUNT_NUMBER=${FUNCTION_ARN_SPLIT[4]}
TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT_NUMBER}:${TOPIC_NAME}"

echo "*** Subscribing function $FUNCTION_ARN to topic $TOPIC_ARN "
SUBSCRIPTION_ADD=$(aws --region ${REGION} sns subscribe --topic-arn ${TOPIC_ARN} --protocol lambda --notification-endpoint ${FUNCTION_ARN})

if [ $? -eq 0 ]; then
  echo "Succesfully subscribed to topic"
else
  echo "ERROR - failed to subscibe to topic"
  RETCODE=1
fi



exit $RETCODE
