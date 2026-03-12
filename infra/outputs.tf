output "s3_bucket_name" {
  description = "Name of the S3 bucket hosting the site"
  value       = aws_s3_bucket.site.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (used for cache invalidation)"
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_distribution_domain" {
  description = "CloudFront distribution domain name (*.cloudfront.net)"
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_url" {
  description = "URL of the deployed site"
  value       = "https://${local.site_domain}"
}

output "api_url" {
  description = "API URL (custom domain)"
  value       = "https://${local.api_domain}"
}

output "lambda_function_name" {
  description = "Lambda function name (used by deploy-api.sh)"
  value       = aws_lambda_function.sign_manifesto.function_name
}
