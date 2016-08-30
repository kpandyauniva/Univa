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

#Delete cluster nodes and deployment 

GCLOUD_CMD=gcloud

#to get around using cygwin
if [ $(uname | grep -i 'win') ] || [ $(uname | grep -i 'NT') ]; then
        GCLOUD_CMD=gcloud.cmd
else
        GCLOUD_CMD=gcloud
fi

DEPLOYMENT_NAME=${DEPLOYMENT_NAME:-univa-nextflow}
DEPLOYMENT_NAME="${DEPLOYMENT_NAME,,}"  #make it lowercase
INSTALLER_NAME=$DEPLOYMENT_NAME-installer

PROJECT=$($GCLOUD_CMD config list core/project 2>/dev/null | grep project | awk {'print $3'})
ZONE=$(cat nextflow.yaml | grep -i zone | awk {'print $2'}) 2>/dev/null

if [ -z "$DEPLOYMENT_NAME" ] || [ -z "$INSTALLER_NAME" ]; then
	echo "Usage:$0 --installer=installer-name --deployment=deployment-name" >&2
	exit 1
fi

if ! $GCLOUD_CMD deployment-manager deployments list 2> /dev/null | grep $DEPLOYMENT_NAME > /dev/null 2>&1; then
	echo "Error: Deployment $DEPLOYMENT_NAME does not exist" >&2
	exit 1
fi

echo "Deployment $DEPLOYMENT_NAME and all cluster nodes will be deleted.  "
echo -n "Do you wish to proceed [N/y]? "
read PROMPT
if [[ -z $PROMPT ]] || [[ $(echo $PROMPT | tr [YN] [yn] | cut -c1) != "y" ]]; then
    exit 1
fi
$GCLOUD_CMD compute ssh $INSTALLER_NAME  --zone $ZONE --project $PROJECT --command delete-k8s-cluster.sh
echo "Deleting deployment " $DEPLOYMENT_NAME


$GCLOUD_CMD deployment-manager deployments delete $DEPLOYMENT_NAME -q
