#!/bin/bash

set -e  # Exit on error
set -o pipefail  # Catch pipeline failures

echo "🚀 Generating Kubernetes Bill of Materials (BoM)..."

AWS_REGION="us-east-1"
EKS_CLUSTER="mynewk8scluster"
S3_BUCKET="my-k8s-bom-storage-bucket-rajani-imp-assignment"

# Ensure kubeconfig is updated
echo "🔄 Updating kubeconfig for EKS..."
aws eks --region "$AWS_REGION" update-kubeconfig --name "$EKS_CLUSTER"

# Generate Kubernetes cluster details (Fixed JSON Formatting)
echo "📌 Collecting Kubernetes information..."
{
  echo "{"
  echo "\"cluster_version\":"
  kubectl version -o json | jq '{clientVersion, serverVersion}'
  echo ","
  echo "\"cluster_info\":"
  kubectl config view -o json --minify | jq '.clusters[0] // {}'
  echo "}"
} > cluster_info.json

# Get node information with clean output
echo "🔍 Fetching Node details..."
kubectl get nodes -o json | jq 'del(.items[].metadata.managedFields) // {}' > nodes.json

# Get workload information with consistent array output
for resource in deployments services configmaps secrets; do
  echo "📦 Collecting $resource..."
  if kubectl get "$resource" --all-namespaces -o json | jq -e '.items | length > 0' > /dev/null 2>&1; then
    kubectl get "$resource" --all-namespaces -o json | \
    jq 'del(.items[].metadata.managedFields) | {items: .items}' > "${resource}.json"
  else
    echo "{}" > "${resource}.json"
  fi
done

# Get container images safely
echo "📸 Collecting pod & container images..."
if kubectl get pods --all-namespaces -o json | jq -e '.items? | length > 0' > /dev/null 2>&1; then
  kubectl get pods --all-namespaces -o json | \
  jq '[.items[]? | {
    namespace: .metadata.namespace,
    pod: .metadata.name,
    containers: (.spec.containers | map(.image)? // []),
    initContainers: (.spec.initContainers | map(.image)? // [])
  }]' > container_images.json
else
  echo "[]" > container_images.json
fi

# Merge all collected data into one BoM JSON
echo "🛠️ Merging Kubernetes BoM data..."
jq -n '{
  cluster_info: input,
  nodes: input,
  deployments: input,
  services: input,
  configmaps: input,
  secrets: input,
  pods: input
}' cluster_info.json nodes.json deployments.json services.json configmaps.json secrets.json container_images.json > k8s_bom.json

# Validate JSON before uploading
if jq empty k8s_bom.json; then
  echo "☁️ Uploading BoM to S3..."
  aws s3 cp k8s_bom.json "s3://$S3_BUCKET/latest_k8s_bom.json"
else
  echo "❌ Invalid JSON detected, skipping upload!"
  exit 1
fi

echo "✅ Kubernetes BoM process completed successfully!"