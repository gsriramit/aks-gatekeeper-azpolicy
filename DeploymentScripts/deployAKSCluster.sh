#!/bin/bash

export SUBSCRIPTION_ID=""
RESOURCEGROUP_LOCATION="CentralIndia"
RESOURCEGROUP_NAME="rg-gatekeeperpolicy-dev-01"
CLUSTER_NAME="aks-dev-01"
PLUGIN=azure
PREVENT_PRIVILEGEDPODS_POLICYID='/providers/Microsoft.Authorization/policyDefinitions/1c6e92c9-99f0-4e55-9cf2-0c234dc48f99'
PREVENT_PRIVILEGEDPODS_POLICYNAME='1c6e92c9-99f0-4e55-9cf2-0c234dc48f99'

# login as a user and set the appropriate subscription ID
az login
az account set -s "${SUBSCRIPTION_ID}"

# install the needed features
az provider register --namespace Microsoft.OperationsManagement
az provider register --namespace Microsoft.OperationalInsights
az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.PolicyInsights

# Install the aks-preview extension
az extension add --name aks-preview

# create the base resource group
az group create --location $RESOURCEGROUP_LOCATION --name $RESOURCEGROUP_NAME --subscription $SUBSCRIPTION_ID 

# Create an AKS cluster with 3 nodes distributed across the availability zones (1 node per zone on the best efoort basis)
# Since we require the nodes to be available across zones, the fronting load balancer needs to be of the Standard SKU
az aks create -g $RESOURCEGROUP_NAME \
-n $CLUSTER_NAME --enable-aad --enable-azure-rbac \
--vm-set-type VirtualMachineScaleSets \
--load-balancer-sku standard \
--enable-addons monitoring,azure-policy \
--node-count 3 \
--network-plugin $PLUGIN \
--zones 1 2 3

# Get the credentials to the working cluster
az aks get-credentials --resource-group $RESOURCEGROUP_NAME --name $CLUSTER_NAME

# Verify the node placement. This is a mandatory requirement for the pod topology spread constraint to work with the "zone" key
kubectl describe nodes | grep -e "Name:" -e "topology.kubernetes.io/zone"
kubectl get nodes -o custom-columns=NAME:'{.metadata.name}',REGION:'{.metadata.labels.topology\.kubernetes\.io/region}',ZONE:'{metadata.labels.topology\.kubernetes\.io/zone}'

# The following test deployment is done to verify the pod placement mechanism
#Apply the test workload with a specific topologySpreadConstraints defined
kubectl apply -f testspreadconstraintDeployment.yaml
# check the placement of the pods across the zones
kubectl get pods -n default -o wide

# Get the definitionID of the Container Privilege Escalation prevention policy

# Apply the policy to the resource group that this cluster is created in
az policy assignment create --name 'do-not-allow-container-privilege-escalation' \
--display-name 'Kubernetes clusters should not allow container privilege escalation' \
--scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCEGROUP_NAME --policy $PREVENT_PRIVILEGEDPODS_POLICYNAME \
-p "{ \"Effect\": \
    { \"value\": \"deny\" } }"
# Create a test deployment that creates a pod/container with elevatedprivileges:true .This should fail


# Apply the Custom Policy that handles the reliability of the workload pods

# Create a test deployment that creates a pod spec without the "topologySpreadConstraints" property. This should ideally fail