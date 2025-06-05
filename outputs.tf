output "bucket_name" {
  value = aws_s3_bucket.upload_bucket.bucket
}

output "sns_topic_arn" {
  value = aws_sns_topic.notify_email_topic.arn
}
