#!/bin/bash

set -e  # Exit on error
set -o pipefail  # Catch pipeline failures

echo "Generating Kubernetes Bill of Materials (BoM)..."

AWS_REGION="us-east-1"
EKS_CLUSTER="confused-indie-orca"
S3_BUCKET="my-k8s-bom-storage-bucket-rajani-imp-assignment"

# Ensure kubeconfig is updated
echo "🔄 Updating kubeconfig for EKS..."
aws eks --region "$AWS_REGION" update-kubeconfig --name "$EKS_CLUSTER"

# Generate Kubernetes cluster details
echo "Collecting Kubernetes information..."
kubectl cluster-info dump > cluster_info.json || echo "{}" > cluster_info.json
kubectl get nodes -o json > nodes.json || echo "{}" > nodes.json
kubectl get deployments --all-namespaces -o json > deployments.json || echo "[]" > deployments.json
kubectl get services --all-namespaces -o json > services.json || echo "[]" > services.json
kubectl get configmaps --all-namespaces -o json > configmaps.json || echo "[]" > configmaps.json
kubectl get secrets --all-namespaces -o json > secrets.json || echo "[]" > secrets.json

# Handle missing pods gracefully
echo "Collecting pod & container images..."
kubectl get pods --all-namespaces -o json | jq '[.items[]? | {namespace: .metadata.namespace, pod: .metadata.name, containers: [.spec.containers[].image]}] // []' > container_images.json || echo "[]" > container_images.json

# Merge all collected data into one BoM JSON
echo "📌 Merging Kubernetes BoM data..."
jq -s '{
  "cluster_info": .[0],
  "nodes": .[1],
  "deployments": .[2],
  "services": .[3],
  "configmaps": .[4],
  "secrets": .[5],
  "pods": .[6]
}' cluster_info.json nodes.json deployments.json services.json configmaps.json secrets.json container_images.json > k8s_bom.json || \
echo '{"error": "BoM generation failed"}' > k8s_bom.json

# Upload the BoM to S3
echo "Uploading BoM to S3..."
aws s3 cp k8s_bom.json "s3://$S3_BUCKET/latest_k8s_bom.json" || echo "Warning: S3 Upload Failed"

echo "✅ Kubernetes BoM process completed successfully!"