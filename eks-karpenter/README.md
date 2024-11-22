# Automate EKS cluster setup with Karpenter and Graviton on AWS

## Description

You've joined a new and growing startup.

The company wants to build its initial Kubernetes infrastructure on AWS. The team wants to leverage the latest autoscaling capabilities by Karpenter, as well as utilize Graviton instances for better price/performance

They have asked you if you can help create the following:
1. Terraform code that deploys an EKS cluster (whatever latest version is currently available) into an existing VPC
2. The terraform code should also deploy Karpenter with node pool(s) that can deploy both x86 and arm64 instances
3. Include a short readme that explains how to use the Terraform repo and that also demonstrates how an end-user (a developer from the company) can run a pod/deployment on x86 or Graviton instance inside the cluster.

## Solution

This repository contains all the required Terraform code for provisioning an EKS cluster and setting up Karpenter for autoscaling. The code is organized into the following directories:

- `eks`: Contains the Terraform code for provisioning the EKS cluster and Karpenter autoscaler.
- `terraform_backend`: Deploys an S3 bucket and DynamoDB table for managing remote `tfstate` files.
- `vpc`: Deploys the network resources (VPC, subnets, etc.).

If you'd like to use an existing VPC, you can specify the IDs of the VPC and subnets directly in the locals block of `main.tf` file within the `eks` module.

### Prerequisites

Ensure the the following tools are installed:

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Terraform](https://developer.hashicorp.com/terraform/install)
- [Kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)

Additionally, ensure that the required environment variables are exported to grant access to the AWS account and specify the region to be used.

### Steps to Deploy

#### I. Deploy Terraform State Backend Resources

1. Navigate to the `./terraform_backend/` directory and update the `main.tf` file with the following details:
   ```terraform
   locals {
     bucket   = "terraform-states-opsfleet-assignment-495599757520-us-east-2"
     dynamodb = "terraform-state-lock"
     project  = "opsfleet-assignment"
   }

2. Initialize the Terraform module and deploy the state backend resources:
   ```sh
   terraform init
   terraform apply
   ```
   
#### II. Deploy VPC-related Resources (Optional)

1. Navigate to the `./vpc/` directory and update the backend.tf file with the terraform_backend configuration.
2. In the `main.tf` file, update the `locals` block with the appropriate values for your environment.
3. Initialize Terraform and deploy the VPC resources:
   ```sh
   terraform init
   terraform apply
   ```

#### III. Deploy EKS Cluster with Karpenter Autoscaler
1. Navigate to the `./eks/` directory and update the backend.tf file to reflect the terraform_backend configuration.
2. In the `main.tf` file, update the `locals` block with the appropriate values for your environment.
   If you're using an existing VPC (bypassing Step II), specify the VPC and subnet IDs in this block as shown in the example below:
   ```terraform
   locals {
     ...
     vpc_id          = "vpc-0123456789abcdef0"
     private_subnets = ["subnet-0123456789abcdef1", "subnet-0123456789abcdef2"]
     intra_subnets   = ["subnet-0123456789abcdef3", "subnet-0123456789abcdef4"]
     ...
   }
   ```
4. Initialize Terraform and deploy the resources:
   ```sh
   terraform init
   terraform apply
   ```

To modify the provisioning configuration (e.g., instance types), update the specification of the `kubectl_manifest.karpenter_node_pool` resource and re-apply the Terraform code.
For example, to extend the list of allowed instance types, adjust the `spec.requirements` section as shown below:
```yaml
  requirements:
    ...
  - key: "karpenter.k8s.aws/instance-family"
    operator: In
    values: ["t4g", "m6g", "m8g", "m8g", "r6g", "c6g", "c7g", "c8g", "t2", "t3", "m4", "m5"]
  - key: "karpenter.k8s.aws/instance-cpu"
    operator: In
    values: ["1", "2", "4", "8", "16"]
    ...

```

### Demo: Automatic Node Provisioning
When you just getting started with Karpenter, it's a good idea to check logs in case you get any **errors**.
```sh
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter
```
If you encounter the following error message:
```
AuthFailure.ServiceLinkedRoleCreationNotPermitted: The provided credentials do not have permission to create the service-linked role for EC2 Spot Instances.
```
This indicates that your credentials lack the necessary permissions to create the service-linked role for EC2 Spot Instances. To resolve this issue, follow the detailed steps in the [troubleshooting guide](https://karpenter.sh/docs/troubleshooting/#missing-service-linked-role).

Track the existing pods in the cluster by running:
```sh
watch -n 1 -t kubectl get pods
```

In another terminal, monitor the available nodes in the Kubernetes cluster:
```sh
watch -n 1 -t kubectl get nodes
```

Now, go to the `./k8s_demo` directory and create deployments:
```sh
kubectl apply -f deployment-arm.yaml
```

You can either use the AWS Management Console to explore EC2 instances, or you can retrieve and filter information about provisioned nodes directly using the following command:
```sh
kubectl get nodes --no-headers | while IFS= read -r node ; do kubectl describe node "$(echo "$node" | cut -d' ' -f1)" | grep -E 'node.kubernetes.io/instance-type=|kubernetes.io/hostname='; done
```

You should see that a `t4g` instance (with **Graviton** ARM CPU) is provisioned, as the deployment manifest specifies `arm64` as the platform.

Next, create a deployment with the `x86` (`amd64`) platform specified:
```sh
kubectl apply -f deployment-x86.yaml
```
This will trigger the provisioning of a `t2` instance with an Intel x86-64 CPU.

Now you can test auto-scaling by adjusting the replica count for these deployments:
```sh
kubectl scale deployment nginx-deployment-x86 --replicas=5
kubectl scale deployment nginx-deployment-arm --replicas=5
```
As you scale the deployments, `Karpenter` will provision or terminate nodes as needed.

Finally, delete the deployments and observe that Karpenter will terminate the provisioned nodes after the specified in
`karpenter_node_pool` manifest timeout (in this example 30 seconds):
```sh
kubectl delete deployments nginx-deployment-x86 nginx-deployment-arm
```

### References
- [Deploy Karpenter v0.32.1 in AWS EKS](https://medium.com/@takebsd/deploy-karpenter-v0-32-1-in-aws-eks-ba16dc550443)
- [terraform-aws-modules/terraform-aws-eks](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/examples/karpenter)
- [Karpenter API v1 migration](https://karpenter.sh/docs/upgrading/v1-migration/)
