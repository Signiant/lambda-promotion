#!/bin/bash

# This script is called from jenkins to promote and deploy a Lambda function

BUILD_PATH=$1
ENVIRONMENT=$2
SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PULL_TYPES=( dynamodb kinesis )

TRUST_POLICY_SRC=${SCRIPT_PATH}/json/trust_policy.json
INLINE_POLICY_SRC=${BUILD_PATH}/deploy/policy.lam.json
LAM_DEPLOY_RULES=${BUILD_PATH}/deploy/${ENVIRONMENT}.lam.json


RETCODE=0

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

#Check if inline policy exists
if [ -e "$INLINE_POLICY_SRC" ]; then
  echo "*** Inline Policy found ($INLINE_POLICY_SRC)"
else
  echo "*** ERROR - Inline Policy not found ($INLINE_POLICY_SRC)"
  RETCODE=1
fi

if [ $RETCODE -eq 0 ]; then
  echo -e "*** Retrieving configuration values from $LAM_DEPLOY_RULES\n"

  REGION=$(jq -r '.["region"]' $LAM_DEPLOY_RULES)
  echo "REGION set to $REGION"
  FUNCTION_NAME=$(jq -r '.["name"]' $LAM_DEPLOY_RULES)
  echo "FUNCTION_NAME set to $FUNCTION_NAME"
  ARCHIVE_NAME=$(jq -r '.["archive"]' $LAM_DEPLOY_RULES)
  echo "ARCHIVE_NAME set to $ARCHIVE_NAME"
  DESCRIPTION=$(jq -r '.["description"]' $LAM_DEPLOY_RULES)
  echo "DESCRIPTION set to $DESCRIPTION"
  RUNTIME=$(jq -r '.["runtime"]' $LAM_DEPLOY_RULES)
  echo "RUNTIME set to $RUNTIME"
  MEMORY_SIZE=$(jq -r '.["memorySize"]' $LAM_DEPLOY_RULES)
  echo "MEMORY_SIZE set to $MEMORY_SIZE"
  TIMEOUT=$(jq -r '.["timeout"]' $LAM_DEPLOY_RULES)
  echo "TIMEOUT set to $TIMEOUT"
  HANDLER=$(jq -r '.["handler"]' $LAM_DEPLOY_RULES)
  echo "HANDLER set to $HANDLER"
fi

  ARTIFACT_PATH="${BUILD_PATH}/${ARCHIVE_NAME}"

if [ $RETCODE -eq 0 ]; then
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

  # Update for event permissions? depends.
  echo "*** Checking IAM for role $ROLE_NAME"
  ROLE_RESP=$(aws --region ${REGION} iam get-role --role-name ${ROLE_NAME})

  #******************* ROLE EXISTS - UPDATE
  if [ $? -eq 0 ]; then
    echo "$ROLE_NAME found"

    #******** UPDATE TRUST POLICY
    echo "*** Updating trust policy for role $ROLE_NAME to trust policy at $TRUST_POLICY_SRC"
    TRUST_RESPONSE=$(aws --region ${REGION} iam update-assume-role-policy --role-name $ROLE_NAME --policy-document file://${TRUST_POLICY_SRC})

    if [ $? -eq 0 ]; then
      echo "Successfully applied trust policy"
    else
      echo "ERROR - failed to apply trust policy at $TRUST_POLICY_SRC to role $ROLE_NAME"
      RETCODE=1
    fi
  #********************** ROLE DOESNT EXIST - CREATE
  else
    echo "$ROLE_NAME not found"
    echo "*** Creating role $ROLE_NAME with trust policy at $TRUST_POLICY_SRC"
    ROLE_RESP=$(aws --region ${REGION} iam create-role --role-name ${ROLE_NAME} --assume-role-policy-document file://${TRUST_POLICY_SRC})

    if [ $? -eq 0 ]; then
      echo -e "Successfully created role $ROLE_NAME\n"
      echo -e "***Sleeping for 10 seconds\n"
      sleep 10s
    else
      echo "ERROR - Failed to create role $ROLE_NAME using trust policy at $TRUST_POLICY_SRC"
      RETCODE=1
    fi
  fi
fi

#******** UPDATE INLINE POLICY
if [ $RETCODE -eq 0 ]; then
  echo "*** Applying inline policy $POLICY_NAME to role $ROLE_NAME"
  POLICY_RESPONSE=$(aws --region ${REGION} iam put-role-policy --role-name $ROLE_NAME --policy-name $POLICY_NAME --policy-document file://${INLINE_POLICY_SRC})

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
  echo "ROLE set to ${ROLE}"
fi


if [ $RETCODE -eq 0 ]; then
  echo
  echo "***********************************************************************"
  echo "*************************** FUNCTION **********************************"
  echo "***********************************************************************"
  echo

  echo "*** Checking lambda for function $FUNCTION_NAME"
  FUNCTION_CHECK=$(aws --region ${REGION} lambda get-'function' --function-name ${FUNCTION_NAME})

  if [ $? -eq 0 ]; then
    echo "Function found"
    echo "*** Updating code for function ${FUNCTION_NAME}"
    FUNCTION_RESPONSE=$(aws --region ${REGION} lambda update-function-code --function-name $FUNCTION_NAME --zip-file fileb://${ARTIFACT_PATH} )

    if [ $? -eq 0 ]; then
      echo "Successfully updated function code"
    else
      echo "ERROR - Unable to update function"
      RETCODE=1
    fi
    if [ $RETCODE -eq 0 ]; then
      echo "*** Updating configuration for function ${FUNCTION_NAME}"
      FUNCTION_CONFIG_RESPONSE=$(aws --region ${REGION} lambda update-function-configuration --function-name ${FUNCTION_NAME} --timeout ${TIMEOUT} --memory-size ${MEMORY_SIZE} --description "${DESCRIPTION}" --role ${ROLE} --handler ${HANDLER})
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
    FUNCTION_RESPONSE=$(aws --region ${REGION} lambda create-'function' --function-name ${FUNCTION_NAME} --description "${DESCRIPTION}" --runtime ${RUNTIME} --role ${ROLE} --handler ${HANDLER} --zip-file fileb://${ARTIFACT_PATH} --timeout ${TIMEOUT} --memory-size ${MEMORY_SIZE})
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
  PUBLISH_RESPONSE=$(aws --region ${REGION} lambda publish-version --function-name ${FUNCTION_NAME})
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
  ALIAS_CHECK=$(aws --region ${REGION} lambda get-alias --function-name ${FUNCTION_NAME} --name PROD)
  if [ $? -eq 0 ]; then
    echo "Alias found"
    echo "*** Updating alias PROD on function $FUNCTION_NAME to point to version $FUNCTION_VERSION"
    ALIAS_RESPONSE=$(aws --region ${REGION} lambda update-alias --function-name ${FUNCTION_NAME} --function-version ${FUNCTION_VERSION} --name PROD)
    if [ $? -eq 0 ]; then
      echo "Successfully updated alias PROD to point to version $FUNCTION_VERSION of function"
    else
      echo "Failed to update alias PROD to point to version $FUNCTION_VERSION of function $FUNCTION_NAME"
      RETCODE=1
    fi
  else
    echo "Alias not found"
    echo "*** Creating alias PROD and applying to function $FUNCTION_NAME version $FUNCTION_VERSION"
    ALIAS_RESPONSE=$(aws --region ${REGION} lambda create-alias --function-name ${FUNCTION_NAME} --name PROD --function-version ${FUNCTION_VERSION})
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
  echo -e "\n*** Retrieving function ARN "
  FUNCTION_ARN=$(echo ${FUNCTION_RESPONSE} | jq -r '.["FunctionArn"]')
  PROD_ARN="${FUNCTION_ARN}:PROD"
  FUNCTION_ARN_SPLIT=(${FUNCTION_ARN//:/ })
  ACCOUNT_NUMBER=${FUNCTION_ARN_SPLIT[4]}

  echo "Function ARN set to $FUNCTION_ARN"
  echo "Production ARN set to $PROD_ARN"
  echo "Account number set to $ACCOUNT_NUMBER"

  # ***** Permissions
  if [ $RETCODE -eq 0 ]; then
    echo "*** Retrieving event policy"
    PERMISSION_CHECK=$(aws --region ${REGION} lambda get-policy --function-name ${FUNCTION_NAME}:PROD)
    PERMISSION_RESULT=$?

    echo "*** Setting permissions for individual event types"
    EVENT_TYPES=($(jq -r '[.["events"][]["type"]] | unique | map("\(.) ") | add ' $LAM_DEPLOY_RULES))
    for TYPE in ${PULL_TYPES[@]}
    #remove pull events from list
    do
      EVENT_TYPES=( "${EVENT_TYPES[@]/$PULL_TYPE}" )
    done
    echo "Event types to process : ${EVENT_TYPES[@]}"
    for TYPE in ${EVENT_TYPES[@]}
    do
      if [ $PERMISSION_RESULT -ne 0 ] || [ "$(echo $PERMISSION_CHECK | jq  -r '.["Policy"]' | jq '.["Statement"]'| jq -e --arg name "${TYPE}_invoke" 'any(.["Sid"]==$name)')" = "false" ]; then
        echo "No invoke permissions found for event type $TYPE"
        echo "*** Applying invoke permissions"
        PERMISSION_ADD=$(aws --region ${REGION} lambda add-permission --function-name ${FUNCTION_NAME} --statement-id "${TYPE}_invoke" --source-arn arn:aws:${TYPE}:${REGION}:${ACCOUNT_NUMBER}:* --action "lambda:InvokeFunction" --principal "${TYPE}.amazonaws.com" --qualifier PROD)
        if [ $? -eq 0 ]; then
          echo "Succesffully added invoke permissions for $TYPE"
        else
          echo "ERROR - failed to add invoke permissions for event type $TYPE to $PROD_ARN"
          RETCODE=1
          break
        fi
      else
        echo "$TYPE permissions found, no action necessary"
      fi
    done
  fi

  if [ $RETCODE -eq 0 ]; then
    echo "*** Checking for event sources in configuration files"
    jq -e '. | has("events")' $LAM_DEPLOY_RULES
    HAS_EVENTS=$?
    if [ $HAS_EVENTS -eq 0 ]; then
      LENGTH=$(jq '.["events"] | length' ${LAM_DEPLOY_RULES})
      if [ $LENGTH -ne 0 ]; then
        echo "Event sources found"
        echo "*** Retrieving and processing event sources from ${LAM_DEPLOY_RULES}"
        for((i=0;i<$LENGTH;i++))
        do
          TYPE=$(jq -r --arg i $i '.["events"]['$i']["type"]' $LAM_DEPLOY_RULES)
          SRC=$(jq -r --arg i $i '.["events"]['$i']["src"]' $LAM_DEPLOY_RULES)
          PARAMETER=$(jq -r --arg i $i '.["events"]['$i']["parameter"]' $LAM_DEPLOY_RULES)

          if [ -e ${BUILD_PATH}/${SRC} ] || [ "$SRC" = "''" ]; then
            echo -e "\n*** Executing script for event source $TYPE (./event-scripts/${TYPE}_event_source.sh)"
            ${SCRIPT_PATH}/event-scripts/${TYPE}_event_source.sh "${BUILD_PATH}/${SRC}" "${PROD_ARN}" "${REGION}" "${PARAMETER}"
            if [ $? -ne 0 ]; then
              RETCODE=1
              break
            fi
          else
            echo "ERROR - $TYPE event source not found (${BUILD_PATH}/${SRC})"
            RETCODE=1
            break
          fi
        done

        if [ $RETCODE -eq 0 ]; then
          echo -e "\nSuccessfully created all event sources"
        fi
      fi
    fi

    if [ $HAS_EVENTS -eq 1 ] || [ $LENGTH -eq 0 ]; then
        echo "No event sources found"
    fi
  fi
fi


exit $RETCODE
