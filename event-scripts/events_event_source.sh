#!/bin/bash

#TODO
# limits?

EVENT_SRC=$1
FUNCTION_ARN=$2
REGION=$3
RETCODE=0

ARRAY=(${FUNCTION_ARN//:/ })
COUNT=${#ARRAY[@]}
FUNCTION_NAME=${ARRAY[($COUNT - 2)]}

echo "*** Retrieving rule name from event source file and prefixing with function name"
RULE_NAME=$(cat $EVENT_SRC | jq -r '.["Name"]')
RULE_NAME="${FUNCTION_NAME}_${RULE_NAME}"
if [ ${#RULE_NAME} -gt 64 ]; then
  RULE_NAME=${RULE_NAME:0:64}
  echo "RULE_NAME exceeds the maximum length of 64 characters and will be truncated"
fi
echo "*** Replacing rule name in json file"
cat $EVENT_SRC | jq --arg NAME $RULE_NAME '.["Name"]=$NAME' > /tmp/events_event.$$
if [ -s /tmp/events_event.$$ ]; then
  echo "RULE_NAME set to $RULE_NAME"
  TMP_PATH=/tmp/events_event.$$
else
  echo "ERROR - failed to modify function ARN in json file $EVENT_SRC"
  RETCODE=1
  rm /tmp/events_event.$$
fi

if [ $RETCODE -eq 0 ]; then
  echo "*** Creating/updating cloudwatch event rule"
  PUT_RULE=$(aws --region ${REGION} events put-rule --cli-input-json file://${TMP_PATH})
  if [ $? -eq 0 ]; then
    echo "Succesfully created/updated event"
    rm $TMP_PATH
  else
    echo "ERROR - failed to create/update event rule ($TMP_PATH)"
    rm $TMP_PATH
    RETCODE=1
  fi
fi

if [ $RETCODE -eq 0 ]; then
  echo "*** Retrieving rule arn from response"
  RULE_ARN=$(echo $PUT_RULE | jq -r '.["RuleArn"]')
  echo "RULE_ARN set to $RULE_ARN"
fi

if [ $RETCODE -eq 0 ]; then
  echo "*** Creating/updating event target."
  TARGET_RESPONSE=$(aws --region ${REGION} events put-targets --rule ${RULE_NAME} --targets "Id=${FUNCTION_NAME}_target,Arn=$FUNCTION_ARN")
  if [ $? -eq 0 ]; then
    echo "Successfully created/updated event targets."
  else
    echo "ERROR - failed to set event target for rule $RULE_NAME to function $FUNCTION_ARN"
    RETCODE=1
  fi
fi


exit $RETCODE
