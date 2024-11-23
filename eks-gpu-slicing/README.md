# GPU Slicing on EKS

## Description

One of our clients has multiple GPU-intensive AI workloads that run on EKS.

Their CTO heard there is an option to cut GPU costs by enabling GPU Slicing.

We want to help them optimize their cost efficiency.

Research the topic, and describe how they can enable GPU Slicing on their EKS clusters.

Some of the EKS clusters have Karpenter Autoscaler, they'd like to leverage GPU Slicing on these
clusters as well. If this is feasible, please provide instructions on how to implement it.

## Solution

GPU slicing is a technique that allows multiple workloads to share the computational resources of a
single GPU, partitioning its memory and compute cores among several tasks. This method improves
resource utilization and reduces costs, particularly for AI/ML workloads where a single GPU may be
underutilized. Rather than dedicating an entire GPU to one task, time-slicing enables tasks to take
turns using the GPU, optimizing its usage and spreading the costs across multiple workloads.

### Time-Slicing in EKS

In Kubernetes environments like Amazon EKS, GPU time-slicing allows tasks to share a GPU by
allocating time slots for each workload. This is especially useful when the GPU is not fully
utilized by applications on EC2 instances. Instead of allocating a whole GPU to a pod, time-slicing
enables multiple pods to use the same GPU by creating virtual GPU units, improving overall resource
efficiency.

For example, a pod could request 10% of a GPU's resources, which translates to one virtual GPU
slice. This approach ensures that smaller workloads can still benefit from GPU acceleration without
wasting the full potential of the hardware.

### Benefits of GPU Time-Slicing

1. **Improved Resource Utilization**: Time-slicing enables multiple pods to share a GPU, reducing idle
time and improving overall resource usage.
2. **Cost Optimization**: By running more workloads on the same
number of GPUs, GPU slicing helps cut down on hardware costs.
3. **Increased Throughput**: Multiple
workloads can operate simultaneously, improving performance during high demand or load spikes.
4. **Flexibility**: Time-slicing supports a variety of workloads, from AI tasks to graphics rendering.
5. **Compatibility**: It provides a solution for older GPUs that don't support advanced sharing mechanisms
like NVIDIA's Multi-Instance GPU (MIG).

### Challenges and Drawbacks

1. **No Fault Isolation**: Unlike MIG, time-slicing lacks memory and fault isolation, so issues
   with one task can affect others.
2. **Potential Latency**: Task switching may introduce slight delays, impacting real-time
   applications.
3. **Complex Resource Management**: Ensuring fair distribution of GPU resources can be difficult,
   especially when multiple tasks have varying demands.
4. **Overhead**: Frequent switching between tasks could lead to computational overhead, potentially
   reducing overall performance.
5. **Resource Starvation**: Improper management could result in some tasks being prioritized,
   leading to resource starvation for others.

### Conclusion

GPU slicing on Amazon EKS, facilitated by NVIDIA's time-slicing technology, offers a way to
optimize GPU resource use, reduce costs, and improve system throughput. While there are some
challenges, such as the lack of fault isolation and the need for effective resource management, the
benefits of GPU sharing - especially for diverse workloads - make it an essential strategy for
modern Kubernetes environments. Stay tuned for our next blog post, where we'll explore
Multi-Instance GPU (MIG) for even more advanced GPU resource sharing techniques.

For more detailed information, including code examples and configuration steps, visit the
[official AWS blog post](https://aws.amazon.com/blogs/containers/gpu-sharing-on-amazon-eks-with-nvidia-time-slicing-and-accelerated-ec2-instances/).

## GPU slicing in clusters with Karpenter autoscaler

I couldn't find a comprehensive guide with all the necessary steps and code examples for using
NVIDIA GPU slicing in EKS clusters with Karpenter, either in the official Karpenter documentation
or other public sources. However, I came across several articles that suggest it is possible. These
articles, though, primarily reference a legacy API version for deployment resources like
`Provisioner` and `AWSNodeTemplate` (instead of the modern `NodePool` and `EC2NodeClass`). Despite
this, the general approach remains consistent, involving the following steps:

1. Deploy a NodePool (formerly Provisioner) to provision nodes with specific `labels` and `taints`.
2. Add a slicing-config ConfigMap with the corresponding `nodeSelector` to ensure the DaemonSet
   runs only on GPU-enabled instances.
3. Deploy the `k8s-device-plugin` using Helm, which creates a DaemonSet to facilitate automatic
   scheduling of GPU-enabled containers.
4. Deploy user applications requiring GPUs, ensuring the appropriate `nodeSelector` and
   `tolerations` are applied for proper scheduling on the GPU instances.

This approach could serve as a solid starting point for further hands-on experimentation with this
topic.

### References:
- [Time-Slicing GPUs with Karpenter](https://dev.to/aws/time-slicing-gpus-with-karpenter-43nn)
- [k8s-device-plugin](https://github.com/NVIDIA/k8s-device-plugin)
