#Create s3 bucket
resource "aws_s3_bucket" "upload_bucket" {
  bucket = "s3-lambda-bucket-${random_id.bucket_id.hex}"
  force_destroy = true

  tags = {
    Name = "Image files bucket"
    
  }
}

# Create bucket id to attach to bucket name
resource "random_id" "bucket_id" {
  byte_length = 4
}

# Create SNS topic
resource "aws_sns_topic" "notify_email_topic" {
  name = "s3-upload-notification-topic"
}

# Create SNS subscription to email
resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.notify_email_topic.arn
  protocol  = "email"
  endpoint  = var.email_address
}

# Create IAM role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lamda_s3_sns_exec_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# Attach default policies to allow basic lamda logging (to CloudWatch)
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create custom policy that allows Lambda function to publish messages to the SNS topic and read objects from the s3 bucket
resource "aws_iam_policy" "lambda_policy" {
  name = "LambdaSNSAndS3Policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["sns:Publish"],
        Resource = aws_sns_topic.notify_email_topic.arn
      },
      {
        Effect = "Allow",
        Action = ["s3:GetObject"],
        Resource = "${aws_s3_bucket.upload_bucket.arn}/*"
      }
    ]
  })
}

# attach the custom policy to Lambda execution role
resource "aws_iam_policy_attachment" "lambda_policy_attach_custom" {
  name       = "lambda-custom-policy-attach"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Package Lambda folder into a zip file to be deployed
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}
# Deploy lambda function from zip file
resource "aws_lambda_function" "notify_lambda" {
  function_name = "s3-upload-notify"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  filename      = data.archive_file.lambda_zip.output_path

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.notify_email_topic.arn
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_policy_attach]
}

# Grant s3 permissions to invoke the Lambda function when object is created
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notify_lambda.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.upload_bucket.arn
}

#Configure s3 bucket to send notifications to the lambda for ObjectCreated events like file uploads
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.upload_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.notify_lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
