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
