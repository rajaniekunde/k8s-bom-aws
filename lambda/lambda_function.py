import json
import boto3
import os

# Initialize AWS S3 Client
s3_client = boto3.client('s3')
S3_BUCKET = os.environ['S3_BUCKET']  # Set this in Lambda environment variables

def lambda_handler(event, context):
    """
    Handles requests coming from Lambda Function URL.
    Extracts path and serves BOM data accordingly.
    """

    # Extract HTTP path from event for Function URL
    path = event.get("rawPath", "/")
    path_parts = path.strip("/").split("/")

    # Case 1: Full BOM (`GET /bom`)
    if path == "/" or path == "/bom":
        return fetch_s3_file("latest_k8s_bom.json")

    # Case 2: Specific Component (`GET /bom/pods`, `GET /bom/services`)
    elif len(path_parts) == 2 and path_parts[0] == "bom":
        component = path_parts[1]
        return fetch_s3_file(f"{component}.json")

    # Case 3: Fetch Specific Resource within a Component (`GET /bom/pods/mypod`)
    elif len(path_parts) == 3 and path_parts[0] == "bom":
        component = path_parts[1]
        resource_name = path_parts[2]
        return fetch_filtered_data(component, resource_name)

    # Case 4: Invalid Route
    return {
        "statusCode": 400,
        "body": json.dumps({"error": "Invalid request path"})
    }

def fetch_s3_file(file_name):
    """Fetch a JSON file from S3 and return response"""
    try:
        response = s3_client.get_object(Bucket=S3_BUCKET, Key=file_name)
        file_content = response['Body'].read().decode('utf-8')
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": file_content
        }
    except s3_client.exceptions.NoSuchKey:
        return {
            "statusCode": 404,
            "body": json.dumps({"error": f"File {file_name} not found"})
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }

def fetch_filtered_data(component, resource_name):
    """Fetch a specific component file from S3 and filter results based on a given resource name"""
    file_name = f"{component}.json"

    try:
        response = s3_client.get_object(Bucket=S3_BUCKET, Key=file_name)
        file_content = json.loads(response['Body'].read().decode('utf-8'))

        # Ensure JSON is a list or has 'items' key containing the list
        if isinstance(file_content, dict) and "items" in file_content:
            file_content = file_content["items"]
        elif not isinstance(file_content, list):
            return {
                "statusCode": 500,
                "body": json.dumps({"error": f"Invalid JSON structure in {file_name}"})
            }

        # Find correct filtering key per component
        resource_key_map = {
            "pods": "pod",
            "services": "metadata.name",
            "deployments": "metadata.name",
            "configmaps": "metadata.name",
            "secrets": "metadata.name",
            "nodes": "metadata.name"
        }

        resource_key = resource_key_map.get(component, "metadata.name")

        # Ensure resource_key exists in JSON objects before filtering
        filtered_data = [item for item in file_content if item.get("metadata", {}).get("name", "") == resource_name]

        if not filtered_data:
            return {
                "statusCode": 404,
                "body": json.dumps({"error": f"Resource '{resource_name}' not found in {component}"})
            }

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(filtered_data)
        }

    except json.JSONDecodeError:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": f"Invalid JSON detected in {file_name}"})
        }
    except s3_client.exceptions.NoSuchKey:
        return {
            "statusCode": 404,
            "body": json.dumps({"error": f"File {file_name} not found"})
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }