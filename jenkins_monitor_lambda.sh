#!/bin/bash

# This script is called from jenkins after the promotion of a lambda function to add monitoring
# It will only be called when deploying to the production environment and when the monitoring flag is set

BUILD_PATH=$1
ENVIRONMENT=$2
ENDPOINT_URL=$3
THRESHOLD_VALUE=$4


LAM_DEPLOY_RULES=${BUILD_PATH}/deploy/environments/${ENVIRONMENT}.lam.json

RETCODE=0

echo
echo "***********************************************************************"
echo "************************** MONITORING *********************************"
echo "***********************************************************************"
echo

if [ $RETCODE -eq 0 ]; then
  #Check if deployment rules exist
  if [ -e "$LAM_DEPLOY_RULES" ]; then
    echo "*** Lambda Deployment Rules found (${LAM_DEPLOY_RULES})"
  else
    echo "*** ERROR - Lambda Deployment Rules not found (${LAM_DEPLOY_RULES})"
    RETCODE=1
  fi
fi


if [ $RETCODE -eq 0 ]; then
  echo "*** Setting configuration values"
  REGION=$(jq -r '.["region"]' $LAM_DEPLOY_RULES)
  echo "REGION set to $REGION"
  FUNCTION_NAME=$(jq -r '.["name"]' $LAM_DEPLOY_RULES)
  ALIASED_NAME="${FUNCTION_NAME}:PROD"
  echo "FUNCTION_NAME set to $FUNCTION_NAME"
fi


if [ $RETCODE -eq 0 ]; then
  echo "*** Retrieving function arn and account number"
  FUNCTION_RESPONSE=$(aws --region ${REGION} lambda get-'function' --'function'-name ${ALIASED_NAME})
  if [ $? -eq 0 ]; then
    FUNCTION_ARN=$(echo $FUNCTION_RESPONSE | jq -r '.["Configuration"]["FunctionArn"]')
    echo "FUNCTION_ARN set to $FUNCTION_ARN"
    FUNCTION_ARN_SPLIT=(${FUNCTION_ARN//:/ })
    ACCOUNT_NUMBER=${FUNCTION_ARN_SPLIT[4]}
    echo "ACCOUNT_NUMBER SET TO $ACCOUNT_NUMBER"
  else
    echo "ERROR - unable to retrieve function from aws Lamdba"
    RETCODE=1
  fi
fi

# Change to use non-static topic name
if [ $RETCODE -eq 0 ]; then
  echo "*** Creating cloudwatch alarm for Error metric"
  ALARM_RESPONSE=$( \
    aws --region ${REGION} cloudwatch put-metric-alarm \
    --alarm-name Lambda_${FUNCTION_NAME}-${REGION}-errors \
    --actions-enabled \
    --alarm-actions arn:aws:sns:${REGION}:${ACCOUNT_NUMBER}:Lambda-Monitoring-Signiant \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --dimensions Name="FunctionName",Value="${FUNCTION_NAME}" Name="Resource",Value="${ALIASED_NAME}" \
    --period 300 \
    --evaluation-periods 1 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
  )
  if [ $? -eq 0 ]; then
    echo "Successfully created alarm"
  else
    echo "ERROR - Unable to create CloudWatch alarm for ${ALIASED_NAME}'s error metric"
    RETCODE=1
  fi
fi

if [ $RETCODE -eq 0 ]; then
  #Ensure Custom Metric exists
  METRIC_RESPONSE=$( \
    aws --region ${REGION} cloudwatch put-metric-data \
    --namespace 'Lambda' \
    --metric-name PercentFailure \
    --unit Percent \
    --value 0 \
    --dimensions FunctionName="${FUNCTION_NAME}",Resource="${ALIASED_NAME}" \
  )
  if [ $? -eq 0 ]; then
    echo "Successfully validated PercentFailure metric"
  else
    echo "ERROR - failed to post to PercentFailure metric for function ${ALIASED_NAME}"
    RETCODE=1
  fi
fi

if [ $RETCODE -eq 0 ]; then
  echo -e "\n*** Checking for SNS topic"
  #construct topic Arn
  TOPIC_NAME="Lambda-Notify-VictorOps_${FUNCTION_NAME}"
  TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT_NUMBER}:${TOPIC_NAME}"
  echo $TOPIC_ARN
  TOPIC_RESPONSE=$(aws --region ${REGION} sns get-topic-attributes --topic-arn ${TOPIC_ARN} 2> /dev/null)
  if [ $? -eq 0 ]; then
    echo "SNS topic found"
  else
    echo "No SNS topic found"
    echo "*** Creating SNS topic $TOPIC_NAME"
    TOPIC_CREATE=$(aws --region ${REGION} sns create-topic --name ${TOPIC_NAME})
    if [ $? -eq 0 ]; then
      echo "Successfully created SNS topic"
      echo "*** Creating topic subscription for endpoint ${ENDPOINT_URL}"
      TOPIC_SUBSCRIBE=$(aws --region ${REGION} sns subscribe --topic-arn ${TOPIC_ARN} --protocol https --notification-endpoint ${ENDPOINT_URL})
      if [ $? -eq 0 ]; then
        echo "Successfully subscribed to topic"
      else
        echo "ERROR - Unable to create subscription for endpoint ${ENDPOINT_URL} to topic ${TOPIC_ARN}"
        RETCODE=1
      fi
    else
      echo "ERROR - Unable to create SNS topic $TOPIC_NAME"
      RETCODE=1
    fi
  fi
fi


if [ $RETCODE -eq 0 ]; then
  echo "*** Creating cloudwatch alarm for PercentFailure metric"
  ALARM_RESPONSE=$( \
    aws --region ${REGION} cloudwatch put-metric-alarm \
    --alarm-name Lambda_${FUNCTION_NAME}-${REGION}-percentfailure \
    --alarm-actions ${TOPIC_ARN} \
    --metric-name PercentFailure \
    --namespace Lambda \
    --statistic Maximum \
    --dimensions Name="FunctionName",Value="${FUNCTION_NAME}" Name="Resource",Value="${ALIASED_NAME}" \
    --period 60 \
    --evaluation-periods 1 \
    --threshold ${THRESHOLD_VALUE} \
    --comparison-operator GreaterThanOrEqualToThreshold \
  )
  if [ $? -eq 0 ]; then
    echo "Successfully created alarm"
  else
    echo "ERROR - Unable to create CloudWatch alarm for ${ALIASED_NAME}'s PercentFailure metric"
    RETCODE=1
  fi
fi


exit $RETCODE
