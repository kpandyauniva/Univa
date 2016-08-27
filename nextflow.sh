#!/bin/bash
#___INFO__MARK_BEGIN__
#############################################################################
#
#  This code is the Property, a Trade Secret and the Confidential Information
#  of Univa Corporation.
#
#  Copyright Univa Corporation. All Rights Reserved. Access is Restricted.
#
#  It is provided to you under the terms of the
#  Univa Term Software License Agreement.
#
#  If you have any questions, please contact our Support Department.
#
#  www.univa.com
#
###########################################################################
#___INFO__MARK_END__

GCLOUD_CMD=gcloud

#to get around using cygwin
if [ $(uname | grep -i 'win') ] || [ $(uname | grep -i 'NT') ]; then
	GCLOUD_CMD=gcloud.cmd
	IAM_TEMP_FILE=`mktemp -p .` || exit 1
else
	GCLOUD_CMD=gcloud
	IAM_TEMP_FILE=`mktemp -t` || exit 1
fi

readonly SERVICE_ACCOUNT=nextflow-installer
readonly ACCOUNT_NAME="Generated-NextFlow-Account"
readonly JSON_KEY_NAME=ServiceAccount.json

PROJECTS_CMD="$GCLOUD_CMD beta"
IAM_CMD="$GCLOUD_CMD beta"

# The purpose of this function is to activate a service account, create one if necessary
function activate_service_account() {

    REVOKE=0
    if  [ -f  $JSON_KEY_NAME ] && 
        [ $GCLOUD_CMD auth activate-service-account $SERVICE_ACCOUNT_EMAIL --key-file $JSON_KEY_NAME 2> /dev/null ]; then
           # Already have an account... This means our project is valid
           echo "Found and activated existing $SERVICE_ACCOUNT_EMAIL account."
           return
    fi

    # Before we proceed make sure this is a valid project
    if ! $PROJECTS_CMD projects describe $PROJECT > /dev/null 2>&1; then
         echo "The project $PROJECT does not exist or you are not authorized to use it.  Exiting." >&2
	 rm $IAM_TEMP_FILE
         exit 2
    fi
    # Try getting the account again
    if $IAM_CMD iam service-accounts list 2> /dev/null | grep "$SERVICE_ACCOUNT_EMAIL" > /dev/null 2>&1; then
         # Already have an account... make a new key
         echo "Found existing $SERVICE_ACCOUNT_EMAIL account."
    else
         # Create a new account for our navops user
         echo "Creating new service account $SERVICE_ACCOUNT_EMAIL..."
         $IAM_CMD iam service-accounts create $SERVICE_ACCOUNT --display-name=$ACCOUNT_NAME > /dev/null

         # Now give the new account permissions
         echo "Adding $SERVICE_ACCOUNT_EMAIL as a project editor..."
         $PROJECTS_CMD projects get-iam-policy $PROJECT --format=json | (python update-iam-policy.py $SERVICE_ACCOUNT_EMAIL>$IAM_TEMP_FILE)
         $PROJECTS_CMD projects set-iam-policy $PROJECT $IAM_TEMP_FILE > /dev/null
	 #if we created account, then old key file is not valid
	 if [ -f  $JSON_KEY_NAME ]; then
	 	mv $JSON_KEY_NAME $JSON_KEY_NAME-$(date +%Y-%m-%d:%H:%M:%S) > /dev/null 2>/dev/null
	 fi
    fi

    # Check if we have a key in our path that we can activate
    if [ ! -f  $JSON_KEY_NAME ] ||  
       [ ! $GCLOUD_CMD auth activate-service-account $SERVICE_ACCOUNT_EMAIL --key-file $JSON_KEY_NAME 2>/dev/null ]; then
        echo "Creating json key for service account $SERVICE_ACCOUNT_EMAIL..."
        $IAM_CMD iam service-accounts keys create --iam-account $SERVICE_ACCOUNT_EMAIL --key-file-type=json $JSON_KEY_NAME
    fi

}

function getdata(){
	PROJECT=$($GCLOUD_CMD config list core/project 2>/dev/null | grep project | awk {'print $3'})
	ACCOUNT=$($GCLOUD_CMD config list core/account 2>/dev/null | grep account | awk {'print $3'})
	SERVICE_ACCOUNT_EMAIL=${SERVICE_ACCOUNT_EMAIL:-$SERVICE_ACCOUNT@$PROJECT.iam.gserviceaccount.com}
	ZONE=$(cat nextflow.yaml | grep -i zone | awk {'print $2'}) 2>/dev/null
}
function dologin(){
	getdata

	if [ -z $ZONE ]; then
		echo 'Error: Zone must be spcified in nextflow.yaml' >&2
		exit 1
	fi
	if [ -z $PROJECT ] || [ -z $ACCOUNT ]; then
		$GCLOUD_CMD auth login --brief
		getdata
	fi
}

dologin

echo "Checking if deployment exist"
if $GCLOUD_CMD deployment-manager deployments list 2> /dev/null | grep nextflow > /dev/null 2>&1; then
	echo "Error: Deployment already exist" >&2
	rm $IAM_TEMP_FILE
	exit 1
fi
echo "Creating service account and key.."
activate_service_account
rm $IAM_TEMP_FILE
echo "Creating deployment.."
$GCLOUD_CMD deployment-manager deployments create nextflow --config=nextflow.yaml

if [ $? -ne 0 ]; then
	echo " Deployment failed. ">&2
	exit 1
fi

echo "Uploading key "
ntries=0
maxtries=10
uploadok=1
while [ $ntries -lt $maxtries ]
do
	sleep 30
	$GCLOUD_CMD compute copy-files ./ServiceAccount.json unicloud-k8s-installer:/tmp  --quiet --zone=$ZONE
	uploadok=$?
	if [ $uploadok -ne 0 ]; then
		echo "Upload failed, trying again "
		((ntries++))
	else
		break
	fi
done 

if [ $uploadok -ne 0 ]; then
	echo "Attempts to upload service account key failed. Deleting deployment" >&2
	$GCLOUD_CMD deployment-manager deployments delete nextflow -q
	exit 1
fi

echo "Launching cluster.  Please check GCP console"
