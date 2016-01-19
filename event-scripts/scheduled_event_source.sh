#!/bin/bash

#TODO
# limits?

EVENT_SRC=$1
FUNCTION_ARN=$2

REGION=$4
RETCODE=0

ARRAY=(${FUNCTION_ARN//:/ })
COUNT=${#ARRAY[@]}
FUNCTION_NAME=${ARRAY[($COUNT - 2)]}


echo "*** Creating/updating cloudwatch event rule"
PUT_RULE=$(aws events put-rule --cli-input-json file://$EVENT_SRC)
if [ $? -eq 0 ]; then
  echo "Succesfully created/updated event"
else
  echo "ERROR - failed to create/update event rule ($EVENT_SRC)"
  RETCODE=1
fi

if [ $RETCODE -eq 0 ]; then
  echo "*** Retrieving rule name from event source file"
  RULE_NAME=$(cat $EVENT_SRC | jq -r '.["Name"]')
  echo "RULE_NAME set to $RULE_NAME"
  echo "*** Retrieving rule arn from response"
  RULE_ARN=$(echo $PUT_RULE | jq -r '.["RuleArn"]')
  echo "RULE_ARN set to $RULE_ARN"
fi

if [ $RETCODE -eq 0 ]; then
  echo "*** Creating/updating event target."
  TARGET_RESPONSE=$(aws events put-targets --rule ${RULE_NAME} --targets "Id=${FUNCTION_NAME}_target,Arn=$FUNCTION_ARN")
  if [ $? -eq 0 ]; then
    echo "Successfully created/updated event targets."
  else
    echo "ERROR - failed to set event target for rule $RULE_NAME to function $FUNCTION_ARN"
    RETCODE=1
  fi
fi


exit $RETCODE