import json
import boto3

s3 = boto3.client("s3")
BUCKET_NAME = "my-k8s-bom-storage"
BOM_FILE = "latest_k8s_bom.json"

def lambda_handler(event, context):
    try:
        response = s3.get_object(Bucket=BUCKET_NAME, Key=BOM_FILE)
        bom_data = json.loads(response['Body'].read().decode('utf-8'))
        return {"statusCode": 200, "body": json.dumps(bom_data)}
    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}