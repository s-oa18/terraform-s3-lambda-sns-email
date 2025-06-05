import json
import boto3
import os

sns = boto3.client('sns')
sns_topic_arn = os.environ['SNS_TOPIC_ARN']

def lambda_handler(event, context):
    try:
        bucket = event["Records"][0]["s3"]["bucket"]["name"]
        key = event["Records"][0]["s3"]["object"]["key"]

        message = f"A new object has been uploaded to S3:\n\nBucket: {bucket}\nKey: {key}"
        subject = "New S3 Upload Notification"

        response = sns.publish(
            TopicArn=sns_topic_arn,
            Message=message,
            Subject=subject
        )

        return {
            "statusCode": 200,
            "body": json.dumps("SNS notification sent successfully.")
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps(f"Error: {str(e)}")
        }
