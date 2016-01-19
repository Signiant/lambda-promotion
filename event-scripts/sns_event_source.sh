#!/bin/bash

EVENT_SRC=$1
FUNCTION_ARN=$2
REGION=$3
TOPIC_ARN=$4
RETCODE=0


if [ $RETCODE -eq 0 ]; then

  echo "*** Subscribing function $FUNCTION_ARN to topic $TOPIC_ARN "
  SUBSCRIPTION_ADD=$(aws sns subscribe --topic-arn ${TOPIC_ARN} --protocol lambda --notification-endpoint ${FUNCTION_ARN})

  if [ $? -eq 0 ]; then
    echo "Succesfully subscribed to topic"
  else
    echo "ERROR - failed to subscibe to topic"
    RETCODE=1
  fi
fi


exit $RETCODE
