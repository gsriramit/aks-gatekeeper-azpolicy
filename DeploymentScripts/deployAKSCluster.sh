#!/bin/bash

export SUBSCRIPTION_ID=""
RESOURCEGROUP_LOCATION="CentralIndia"
RESOURCEGROUP_NAME="rg-gatekeeperpolicy-dev-01"
CLUSTER_NAME="aks-dev-01"
PLUGIN=azure
PREVENT_PRIVILEGEDPODS_POLICYID='/providers/Microsoft.Authorization/policyDefinitions/1c6e92c9-99f0-4e55-9cf2-0c234dc48f99'
PREVENT_PRIVILEGEDPODS_POLICYNAME='1c6e92c9-99f0-4e55-9cf2-0c234dc48f99'
PODSPREADCONSTRAINTMANDATEPOLICYNAME='04fde83b-20b2-43cb-bdac-763577eb3730'

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

# Verify the presence and state of the gatekeeper pods
kubectl get pods -n gatekeeper-system

# Get the credentials to the working cluster
az aks get-credentials --resource-group $RESOURCEGROUP_NAME --name $CLUSTER_NAME --admin

# Verify the node placement. This is a mandatory requirement for the pod topology spread constraint to work with the "zone" key
kubectl describe nodes | grep -e "Name:" -e "topology.kubernetes.io/zone"
kubectl get nodes -o custom-columns=NAME:'{.metadata.name}',REGION:'{.metadata.labels.topology\.kubernetes\.io/region}',ZONE:'{metadata.labels.topology\.kubernetes\.io/zone}'

# The following test deployment is done to verify the pod placement mechanism
#Apply the test workload with a specific topologySpreadConstraints defined
kubectl apply -f testspreadconstraintDeployment.yaml
# check the placement of the pods across the zones
kubectl get pods -n default -o wide

########## Illustration of Pod Security Policies ################################
# Get the definitionID of the Container Privilege Escalation prevention policy
# Apply the policy to the resource group that this cluster is created in
az policy assignment create --name 'do-not-allow-container-privilege-escalation' \
--display-name 'Kubernetes clusters should not allow container privilege escalation' \
--scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCEGROUP_NAME --policy $PREVENT_PRIVILEGEDPODS_POLICYNAME \
-p "{ \"Effect\": \
    { \"value\": \"deny\" } }"
# Create a test deployment that creates a pod/container with elevatedprivileges:true .This should fail with the appropriate error message
#####  [azurepolicy-psp-container-no-privilege-esc-794edd6fbb66b2a39128] Privilege escalation container is not allowed: nginx-privileged #####
# Note: Run the following commands from within ClusterManifests/TestDeployment/
kubectl apply -f PrivilegedPod.yaml

# Get the pod information (replace the pod's name with the actual value)
# kubectl get -o json pod <podname>
##############################################################################


########## Illustration of Pod Reliability Policies ################################
# Apply the Custom Policy that ensures the reliability of the workload pods by enforcing zone-redunandancy
az policy assignment create --name 'mandate-pod-spread-constraints' \
--display-name 'Kubernetes clusters should not allow pods without PodTopologySpreadConstraint' \
--scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCEGROUP_NAME --policy $PODSPREADCONSTRAINTMANDATEPOLICYNAME

# Verify if the constraint template was applied to the cluster
# this should list the constraint applied through the new azure policy
# NAME
#k8sazurepodspreadconstraintsenforced
kubectl get constrainttemplates

# Create a test deployment that creates a pod spec without the "topologySpreadConstraints" property. This should ideally fail
kubectl apply -f testNoSpreadconstraint.yaml
# The deployment should get rejected with the appropriate violation error message
# Error from server ([azurepolicy-prp-pod-spreadconstraint-manda-45f6680c714279da4e5b] At least 1 spread constraint needs to be defined: %!v(MISSING)): error when creating "testNoSpreadconstraint.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [azurepolicy-prp-pod-spreadconstraint-manda-45f6680c714279da4e5b] At least 1 spread constraint needs to be defined: %!v(MISSING)

## Fetch the constraint kind created 
kubectl get K8sAzurePodSpreadConstraintsEnforced
## NAME                                                              AGE
# azurepolicy-prp-pod-spreadconstraint-manda-bce35ea75962704aa50c   26m

## describe the specific instance of the constraint created to read the policy violations
## Note: The violations array will be populated only if the Policy Action is set to "Audit" and not "Deny"
# Replace the name of the constraint instance (specified in < >) with the value that you obtain in the previous step
kubectl describe K8sAzurePodSpreadConstraintsEnforced <azurepolicy-prp-pod-spreadconstraint-manda-bce35ea75962704aa50c>

######################################################
#Total Violations:  1
# Violations:
#  Enforcement Action:  dryrun
#  Kind:                Pod
#  Message:             At least 1 spread constraint needs to be defined: mypod
#  Name:                mypod
#  Namespace:           default    

##############################################################################