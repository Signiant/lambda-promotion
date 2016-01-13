#!/bin/bash

# This script is called locally (later from jenkins) to promote and deploy a Lambda function

#TODO
# EVENTS
#   -Better yaml parsing
#   -Add parameters struct to array?


#CURRENT ISSUES / QUESTIONS
# ROLES - PATH

RETCODE=0
BUILD_PATH="/Users/jseed/Projects/LambdaFunction"
TRUST_POLICY_SRC="${BUILD_PATH}/deploy/trust_policy.lam.json"
echo "BUILD_PATH set to $BUILD_PATH"
LAM_DEPLOY_RULES=${BUILD_PATH}/deploy/lambda.yaml

BUCKET="jon-test-bucket"


# TEST BUILD
cd $BUILD_PATH
rm JonTestFunction.zip
zip JonTestFunction.zip JonTestFunction.js



#Check if deployment rules exist
if [ -e "$LAM_DEPLOY_RULES" ]; then
  echo "*** Lambda Deployment Rules found (${LAM_DEPLOY_RULES})"
else
  echo "*** ERROR - Lambda Deployment Rules not found (${LAM_DEPLOY_RULES})"
  RETCODE=1
fi

#Check if trust policy exists
if [ -e "$TRUST_POLICY_SRC" ]; then
  echo "*** Trust Policy found (${TRUST_POLICY_SRC})"
else
  echo "*** ERROR - Trust Policy not found (${TRUST_POLICY_SRC})"
  RETCODE=1
fi

if [ $RETCODE -eq 0 ]; then
  #Retrieve and set configuration values
  echo -e "*** Retrieving configuration values from $LAM_DEPLOY_RULES\n"

  REGION=$(cat $LAM_DEPLOY_RULES | shyaml get-value function_configuration.region)
  echo "REGION set to $REGION"
  FUNCTION_NAME=$(cat $LAM_DEPLOY_RULES | shyaml get-value function_configuration.name)
  echo "FUNCTION_NAME set to $FUNCTION_NAME"
  DESCRIPTION=$(cat $LAM_DEPLOY_RULES | shyaml get-value function_configuration.description)
  echo "DESCRIPTION set to $DESCRIPTION"
  RUNTIME=$(cat $LAM_DEPLOY_RULES | shyaml get-value function_configuration.runtime)
  echo "RUNTIME set to $RUNTIME"
  MEMORY_SIZE=$(cat $LAM_DEPLOY_RULES | shyaml get-value function_configuration.memory_size)
  echo "MEMORY_SIZE set to $MEMORY_SIZE"
  TIMEOUT=$(cat $LAM_DEPLOY_RULES | shyaml get-value function_configuration.timeout)
  echo "TIMEOUT set to $TIMEOUT"
  INLINE_POLICY_SRC=$(cat $LAM_DEPLOY_RULES | shyaml get-value role.inline_policy_src)
  echo "INLINE_POLICY_SRC set to $INLINE_POLICY_SRC"


fi
if [ $RETCODE -eq 0 ]; then

  # RUNTIME and ARTIFACT_PATH need to be fixed for proper building
  if [ "${RUNTIME}" == 'nodejs' ]; then
    HANDLER=${FUNCTION_NAME}.handler
  fi


  ARTIFACT_PATH=${BUILD_PATH}/${FUNCTION_NAME}.zip


  echo
  echo "***********************************************************************"
  echo "****************** ROLES AND POLICIES *********************************"
  echo "***********************************************************************"
  echo

  echo "*** Setting ROLE_NAME and POLICY_NAME"
  ROLE_NAME="${FUNCTION_NAME}_role"
  echo "ROLE_NAME set to $ROLE_NAME"
  POLICY_NAME="${FUNCTION_NAME}_policy"
  echo -e "POLICY_NAME set to $POLICY_NAME\n"

  echo "*** Verifying INLINE_POLICY_SRC path"
  if [ -e "$INLINE_POLICY_SRC" ]; then
    echo -e "Role $ROLE_NAME policy file found (${INLINE_POLICY_SRC})\n"
  else
    echo "ERROR - Role $ROLE_NAME policy file not found (${INLINE_POLICY_SRC})"
    RETCODE=1
  fi
fi

# Update for event permissions? depends.
if [ $RETCODE -eq 0 ]; then
  echo "*** Checking IAM for role $ROLE_NAME"
  ROLE_RESP=$(aws iam get-role --role-name ${ROLE_NAME})

  #******************* ROLE EXISTS - UPDATE
  if [ $? -eq 0 ]; then
    echo "$ROLE_NAME found"

    #******** UPDATE TRUST POLICY
    echo "*** Updating trust policy for role $ROLE_NAME to trust policy at $TRUST_POLICY_SRC"
    TRUST_RESPONSE=$(aws iam update-assume-role-policy --role-name $ROLE_NAME --policy-document file://${TRUST_POLICY_SRC})


    if [ $? -eq 0 ]; then
      echo "Successfully applied trust policy"
    else
      echo "ERROR - failed to apply trust policy at $TRUST_POLICY_SRC to role $ROLE_NAME"
      RETCODE=1
    fi


  #********************** ROLE DOESNT EXIST - CREATE
  else

    echo "$ROLE_NAME not found"
    echo "*** Creating role $ROLE_NAME with trust policy at ${TRUST_POLICY_SRC}"
    ROLE_RESP=$(aws iam create-role --role-name ${ROLE_NAME} --assume-role-policy-document file://${TRUST_POLICY_SRC})

    #If not successful, fail
    if [ $? -eq 0 ]; then
      echo -e "Successfully created role $ROLE_NAME\n"
      echo -e "***Sleeping for 5 seconds\n"
      sleep 5s
    else
      echo "ERROR - Failed to create role $ROLE_NAME using trust policy at ${TRUST_POLICY_SRC}"
      RETCODE=1
    fi
  fi
fi

#******** UPDATE INLINE POLICY
if [ $RETCODE -eq 0 ]; then
  echo "*** Applying inline policy $POLICY_NAME to role $ROLE_NAME"
  POLICY_RESPONSE=$(aws iam put-role-policy --role-name $ROLE_NAME --policy-name $POLICY_NAME --policy-document file://${INLINE_POLICY_SRC})

  if [ $? -eq 0 ]; then
    echo "Successfully applied inline policy"
  else
    echo "Failed to apply inline policy $POLICY_NAME ($INLINE_POLICY_SRC) for role $ROLE_NAME"
    RETCODE=1
  fi
fi

if [ $RETCODE -eq 0 ]; then
  echo "*** Setting ROLE to role arn"
  ROLE=$(echo ${ROLE_RESP} | jq -r '.["Role"]["Arn"]')
  echo "ROLE set to $ROLE"
fi


if [ $RETCODE -eq 0 ]; then
  echo
  echo "***********************************************************************"
  echo "*************************** FUNCTION **********************************"
  echo "***********************************************************************"
  echo

  echo "*** Checking lambda for function $FUNCTION_NAME"
  FUNCTION_CHECK=$(aws lambda get-'function' --function-name ${FUNCTION_NAME})

  if [ $? -eq 0 ]; then
    echo "Function found"
    echo "*** Updating code for function ${FUNCTION_NAME}"
    FUNCTION_RESPONSE=$(aws lambda update-function-code --function-name $FUNCTION_NAME --zip-file fileb://${ARTIFACT_PATH} )

    if [ $? -eq 0 ]; then
      echo "Successfully updated function code"
    else
      echo "ERROR - Unable to update function"
      RETCODE=1
    fi
    if [ $RETCODE -eq 0 ]; then
      echo "*** Updating configuration for function ${FUNCTION_NAME}"
      FUNCTION_CONFIG_RESPONSE=$(aws lambda update-function-configuration --function-name ${FUNCTION_NAME} --timeout ${TIMEOUT} --memory-size ${MEMORY_SIZE} --description "${DESCRIPTION}" --role ${ROLE} --handler ${HANDLER})
      if [ $? -eq 0 ]; then
        echo "Successfully updated function configuration"
      else
        echo "ERROR - Failed to update function configuration"
        RETCODE=1
      fi
    fi

  else
    echo "Function not found"
    echo "*** Creating function $FUNCTION_NAME"
    FUNCTION_RESPONSE=$(aws lambda create-'function' --function-name ${FUNCTION_NAME} --description "${DESCRIPTION}" --runtime ${RUNTIME} --role ${ROLE} --handler ${HANDLER} --zip-file fileb://${ARTIFACT_PATH} --timeout ${TIMEOUT} --memory-size ${MEMORY_SIZE})
    if [ $? -eq 0 ]; then
      echo "Successfully created function"
    else
      echo "ERROR - Failed to create function ${FUNCTION_NAME}"
      RETCODE=1
    fi
    #IF ON CREATE TESTING REQUIRED PUT HERE
  fi
fi


#*************************Version
if [ $RETCODE -eq 0 ]; then
  echo -e "\n*** Publishing new version of function $FUNCTION_NAME"
  PUBLISH_RESPONSE=$(aws lambda publish-version --function-name ${FUNCTION_NAME})
  if [ $? -eq 0 ]; then
    FUNCTION_VERSION=$(echo $PUBLISH_RESPONSE | jq -r '.["Version"]')
    echo "Successfully published function $FUNCTION_NAME version $FUNCTION_VERSION"
  else
    echo "ERROR - failed to publish new version of function $FUNCTION_VERSION"
    RETCODE=1
  fi
fi
#************************Aliasing
if [ $RETCODE -eq 0 ]; then
  echo -e "\n*** Checking for PROD alias on function $FUNCTION_NAME"
  ALIAS_CHECK=$(aws lambda get-alias --function-name ${FUNCTION_NAME} --name PROD)
  if [ $? -eq 0 ]; then
    echo "Alias found"
    echo "*** Updating alias PROD on function $FUNCTION_NAME to point to version $FUNCTION_VERSION"
    ALIAS_RESPONSE=$(aws lambda update-alias --function-name ${FUNCTION_NAME} --function-version ${FUNCTION_VERSION} --name PROD)
    if [ $? -eq 0 ]; then
      echo "Successfully updated alias PROD to point to version $FUNCTION_VERSION of function"
    else
      echo "Failed to update alias PROD to point to version $FUNCTION_VERSION of function $FUNCTION_NAME"
      RETCODE=1
    fi
  else
    echo "Alias not found"
    echo "*** Creating alias PROD and applying to function $FUNCTION_NAME version $FUNCTION_VERSION"
    ALIAS_RESPONSE=$(aws lambda create-alias --function-name ${FUNCTION_NAME} --name PROD --function-version ${FUNCTION_VERSION})
    if [ $? -eq 0 ]; then
      echo "Alias successfully created and applied"
    else
      echo "ERROR - Failed to create and apply alias PROD to function $FUNCTION_NAME version $FUNCTION_VERSION"
      RETCODE=1
    fi
  fi
fi

if [ $RETCODE -eq 0 ]; then
  echo
  echo "***********************************************************************"
  echo "************************* EVENTS SOURCES ******************************"
  echo "***********************************************************************"
  echo

  #**************************Events
  echo "*** Retrieving function ARN "
  FUNCTION_ARN=$(echo ${FUNCTION_RESPONSE} | jq -r '.["FunctionArn"]')
  echo "Function ARN set to $FUNCTION_ARN"

  #Process events from yaml file (NEEDS TO BE FIXED)
  echo -e "*** Retrieving and processing event sources from ${LAM_DEPLOY_RULES}\n"

  #This is messy, better way?
  while [ $RETCODE ] && read -r -d '' KEY SRC KEY TYPE; do
      echo "Calling executing script at ./event-scripts/${TYPE}_event_source.sh and passing json file $SRC"
      #Needs to be less specific
      /Users/jseed/Projects/lambda-promotion/event-scripts/${TYPE}_event_source.sh  "${SRC}" "$FUNCTION_ARN" "$BUCKET"
      RETCODE=$?
  done < <(cat ${LAM_DEPLOY_RULES} | shyaml get-values-0 events)


#Update/Remove
  if [ $RETCODE -eq 0 ]; then
    echo -e "\nSuccessfully created all event sources"
  fi
fi


exit $RETCODE
