#!/bin/bash

set -e  # Exit on error
set -o pipefail  # Catch pipeline failures

echo "Generating Kubernetes Bill of Materials (BoM)..."

AWS_REGION="us-east-1"
EKS_CLUSTER="mynewk8scluster"
S3_BUCKET="my-k8s-bom-storage-bucket-rajani-imp-assignment"

# Ensure kubeconfig is updated
echo "🔄 Updating kubeconfig for EKS..."
aws eks --region "$AWS_REGION" update-kubeconfig --name "$EKS_CLUSTER"

# Collect Kubernetes data
echo "Collecting Kubernetes information..."
kubectl get nodes -o json | jq 'del(.items[].metadata.managedFields)' > nodes.json
kubectl get deployments --all-namespaces -o json | jq 'del(.items[].metadata.managedFields)' > deployments.json
kubectl get services --all-namespaces -o json | jq 'del(.items[].metadata.managedFields)' > services.json
kubectl get configmaps --all-namespaces -o json | jq 'del(.items[].metadata.managedFields)' > configmaps.json
kubectl get secrets --all-namespaces -o json | jq 'del(.items[].metadata.managedFields)' > secrets.json

# Handle missing pods safely
echo "Collecting pod & container images..."
if kubectl get pods --all-namespaces -o json | jq -e '.items? | length > 0' > /dev/null 2>&1; then
  kubectl get pods --all-namespaces -o json | jq '[.items[]? | {
    namespace: .metadata.namespace,
    pod: .metadata.name,
    containers: (.spec.containers | map(.image)? // []),
    initContainers: (.spec.initContainers | map(.image)? // [])
  }]' > pods.json
else
  echo "[]" > pods.json
fi

# Merge all collected data into one BoM JSON
echo "📌 Merging Kubernetes BoM data..."
jq -n '{
  nodes: input,
  deployments: input,
  services: input,
  configmaps: input,
  secrets: input,
  pods: input
}' nodes.json deployments.json services.json configmaps.json secrets.json pods.json > k8s_bom.json

# Validate JSON before upload
if jq empty k8s_bom.json; then
  echo "Uploading BoM files to S3..."
  aws s3 cp k8s_bom.json "s3://$S3_BUCKET/latest_k8s_bom.json"
  aws s3 cp nodes.json "s3://$S3_BUCKET/nodes.json"
  aws s3 cp deployments.json "s3://$S3_BUCKET/deployments.json"
  aws s3 cp services.json "s3://$S3_BUCKET/services.json"
  aws s3 cp configmaps.json "s3://$S3_BUCKET/configmaps.json"
  aws s3 cp secrets.json "s3://$S3_BUCKET/secrets.json"
  aws s3 cp pods.json "s3://$S3_BUCKET/pods.json"
else
  echo "❌ Invalid JSON generated, skipping upload"
  exit 1
fi

echo "✅ Kubernetes BoM process completed successfully!"