# Unified Governance for AKS using Azure Policies and Gatekeeper
This repository contains deployment scripts and templates that help in setting up the AKS infrastructure and the **Pod Security and Reliability Policies** for the workloads that run in them. I gave a speech on this topic at the Global Azure Conference Chennai 2022. The presentation deck can be found in a later section in this documentation.

## Architecture
![Security Baseline Architecture - Admission Controller Working](https://user-images.githubusercontent.com/13979783/167291464-e5490bf0-6e75-4919-86ec-b59ac381a047.png)

### Key Areas that stitch the components together
1. A Constraint Template and a Constraint are defined for each of the policies to be defined to govern the workloads.
   - These resources are defined as CRDs (Custom Resource Definitions) thereby letting you extend the native kubernetes objects
   - The Constraint created from the template defines an object **kind** that forms a new object that will be used when defining the policy 
2. The template and the constraint object are embedded within an Azure Policy in the **PolicyRule** property
   - These rules can be applied to Arc-Enabled Kubernetes cluster and to AKS Engine deployments too
   - In a Vanilla K8s deployment, the constraint template and the constraint instance will have to be imported/applied manually. The same is not necessary in an Azure Managed K8s deployment that can be governed through Azure Policies
   - The constraints should be hosted at a CDN or an internal repository that is accessible by the Azure Control Plane
   - ```
       "policyRule": {
      "if": {
        "field": "type",
        "in": [
          "AKS Engine",
          "Microsoft.Kubernetes/connectedClusters",
          "Microsoft.ContainerService/managedClusters"
        ]
      },
      "then": {
        "effect": "[parameters('effect')]",
        "details": {
          "constraintTemplate": "https://raw.githubusercontent.com/gsriramit/aks-gatekeeper-azpolicy/main/Constraints/podTopologySpreadConstraintTemplate.yaml",
          "constraint": "https://raw.githubusercontent.com/gsriramit/aks-gatekeeper-azpolicy/main/Constraints/podTopologySpreadConstraint.yaml",
          ......
          }
        }
      }
    }
    ```
3. The Gatekeeper component contains the OPA policy engine and becomes the webhook endpoint of the Kubernetes' Admission-Validating Controller
4. The OPA engine requires **Policies** and additional **Data** to validate the incoming requests
   - The Incoming request to the Gatekeeper is the REST call termed as the **Admission Review**  request and is received from the API server
   - The Business rules (security, reliability and any other resource governance rules) are defined in the Rego language within the Constraint Template 
     - The OPA engine in the Gatekeeper watches for the creation or updates of these CRDs and then replicates them to make the REGO policies available locally
     - The OPA engine also watches and replicates the Kubernetes objects (Pods, Ingress, Deploy, Daemon Sets etc.,) locally. This is required if the policy rule requires checking or evaluation against the existing objects in the cluster
     - Validation happens at the Gatekeeper and the request is either accepted or rejected


## Deployment & Validation 
Follow the steps in the deployAKSCluster.sh file. The script file has additional comments included at each step to explain the working of the commands  

### Points to Note

#### Configuration of the AKS Cluster
1. The AKS cluster is configured to include the Azure Policy Add-on 
2. The Cluster will have 3 nodes which are distributed across availability zones 1,2 and 3
![image](https://user-images.githubusercontent.com/13979783/167292181-5654da73-595e-450e-9157-574331ca8eaf.png)

### Check the node placement across the availability zones
```
# Verify the node placement. This is a mandatory requirement for the pod topology spread constraint to work with the "zone" key
kubectl describe nodes | grep -e "Name:" -e "topology.kubernetes.io/zone"
kubectl get nodes -o custom-columns=NAME:'{.metadata.name}',REGION:'{.metadata.labels.topology\.kubernetes\.io/region}',ZONE:'{metadata.labels.topology\.kubernetes\.io/zone}'
```
![image](https://user-images.githubusercontent.com/13979783/167292509-dfef43ac-34ee-4638-807a-d5ba34e455e7.png)

#### Check for the presence of the Gatekeeper pods in the corresponding namespace
![image](https://user-images.githubusercontent.com/13979783/167292552-7156b848-0eda-4be1-9e88-2e5e0b9f06f6.png)

#### Policy Assignment 
The Azure Policies can be applied through the Azure portal or through PS or CLI commands. The script file has the corresponding commands required to apply 2 policies 
1. Kubernetes clusters should not allow container privilege escalation
2. Kubernetes clusters should not allow pods without PodTopologySpreadConstraint  
**Syntax**
```
########## Illustration of Pod Reliability Policies ################################
# Apply the Custom Policy that ensures the reliability of the workload pods by enforcing zone-redunandancy
az policy assignment create --name 'mandate-pod-spread-constraints' \
--display-name 'Kubernetes clusters should not allow pods without PodTopologySpreadConstraint' \
--scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCEGROUP_NAME --policy $PODSPREADCONSTRAINTMANDATEPOLICYNAME
```

#### Verify the presence of the newly created Constraint Templates & Constraint Types
The assignment of the 2 azure policies to this AKS cluster should have imported the constraint templates and the constraint objects 
![image](https://user-images.githubusercontent.com/13979783/167292715-1c283996-2064-4840-82aa-0fc64d18a624.png)

![image](https://user-images.githubusercontent.com/13979783/167292817-78759e6d-68bb-4dcc-ab52-ef8643a1361d.png)

#### Verify the creation of Privileged Containers and Pod without "topologySpreadConstraints"
Both these deployments would fail owing to the violation of the Policies that have been enforced w.r.t security and resiliency. **Note**: If the effect of the Azure Policies had been defined as **"Audit"** instead of **"Deny"** the these deployments would be completed. 
![image](https://user-images.githubusercontent.com/13979783/167292919-dbf10b51-f440-4b92-b54e-fbabd50d1aec.png)

#### Modify the Policy Effect to Audit and Check the Violations
```
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
```

## Presentation Deck
Find it in this [link](PresentationDeck/GAB_2022_Sriram_UnifiedGovernanceForAKS_v2.pptx)

