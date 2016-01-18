#!/bin/bash

#TODO
# gen custom Event target id?
EVENT_SRC=$1
FUNCTION_ARN=$2
RETCODE=0


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


  echo "*** Checking if policy exists"
  PERMISSION_CHECK=$(aws lambda get-policy --function-name ${FUNCTION_ARN})
  PERMISSION_EXISTS=$(echo "${PERMISSION_CHECK}" | jq -r '.["Policy"]' | jq -r '.["Statement"]' | jq --arg SID "${RULE_NAME}_invoke" 'any(.["Sid"]==$SID)')
  if [ "$PERMISSION_EXISTS" = "false" ]; then
    echo "Permission ${RULE_NAME}_invoke not found"
    echo "*** Adding permissions to lambda function $FUNCTION_ARN for rule $RULE_NAME"
    PERMISSION_ADD=$(aws lambda add-permission --function-name ${FUNCTION_ARN} --region us-east-1 --statement-id ${RULE_NAME}_invoke --principal events.amazonaws.com --action "lambda:InvokeFunction" --source-arn $RULE_ARN)
    if [ $? -eq 0 ]; then
      echo "Successfully added permissions to function $FUNCTION_ARN"
    else
      echo "ERROR - failed to add permissions to function $FUNCTION_ARN for rule $RULE_NAME"
      RETCODE=1
    fi
  else
    echo "Permission ${RULE_NAME}_invoke already exists, no actions needed"
  fi
fi

if [ $RETCODE -eq 0 ]; then
  echo "*** Creating/updating event target."
  TARGET_RESPONSE=$(aws events put-targets --rule ${RULE_NAME} --targets "Id=1,Arn=$FUNCTION_ARN")
  if [ $? -eq 0 ]; then
    echo "Successfully created/updated event targets."
  else
    echo "ERROR - failed to set event target for rule $RULE_NAME to function $FUNCTION_ARN"
    RETCODE=1
  fi
fi


exit $RETCODE
