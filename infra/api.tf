# =============================================================================
# DynamoDB — Signatures table
# =============================================================================

resource "aws_dynamodb_table" "signatures" {
  name         = "ihatetimezones-${var.environment}-signatures"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "pk"

  attribute {
    name = "pk"
    type = "S"
  }
}

# =============================================================================
# IAM — Lambda execution role
# =============================================================================

resource "aws_iam_role" "sign_manifesto" {
  name = "ihatetimezones-${var.environment}-sign-manifesto"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sign_manifesto_basic" {
  role       = aws_iam_role.sign_manifesto.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "sign_manifesto_dynamodb" {
  name = "dynamodb-access"
  role = aws_iam_role.sign_manifesto.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
      ]
      Resource = aws_dynamodb_table.signatures.arn
    }]
  })
}

resource "aws_iam_role_policy" "sign_manifesto_ses" {
  name = "ses-send"
  role = aws_iam_role.sign_manifesto.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ses:SendEmail"
      Resource = aws_ses_domain_identity.site.arn
    }]
  })
}

# =============================================================================
# Lambda — Sign manifesto handler
# =============================================================================

data "archive_file" "sign_manifesto" {
  type        = "zip"
  source_dir  = "${path.module}/../api/sign-manifesto/dist"
  output_path = "${path.module}/../api/sign-manifesto/dist/lambda.zip"
}

resource "aws_lambda_function" "sign_manifesto" {
  function_name = "ihatetimezones-${var.environment}-sign-manifesto"
  role          = aws_iam_role.sign_manifesto.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 10
  memory_size   = 256

  filename         = data.archive_file.sign_manifesto.output_path
  source_code_hash = data.archive_file.sign_manifesto.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.signatures.name
      FROM_EMAIL = local.from_email
      SITE_URL   = "https://${local.site_domain}"
    }
  }
}

# =============================================================================
# API Gateway v2 (HTTP API)
# =============================================================================

resource "aws_apigatewayv2_api" "sign_manifesto" {
  name          = local.api_name
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = local.cors_origins
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 86400
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.sign_manifesto.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }
}

resource "aws_apigatewayv2_integration" "sign_manifesto" {
  api_id                 = aws_apigatewayv2_api.sign_manifesto.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.sign_manifesto.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_sign" {
  api_id    = aws_apigatewayv2_api.sign_manifesto.id
  route_key = "POST /sign"
  target    = "integrations/${aws_apigatewayv2_integration.sign_manifesto.id}"
}

resource "aws_apigatewayv2_route" "get_count" {
  api_id    = aws_apigatewayv2_api.sign_manifesto.id
  route_key = "GET /count"
  target    = "integrations/${aws_apigatewayv2_integration.sign_manifesto.id}"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sign_manifesto.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.sign_manifesto.execution_arn}/*/*"
}

# =============================================================================
# Custom Domain — ACM certificate + API Gateway domain + Route 53
# =============================================================================

resource "aws_acm_certificate" "api" {
  domain_name       = local.api_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "api_acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in aws_route53_record.api_acm_validation : record.fqdn]
}

resource "aws_apigatewayv2_domain_name" "api" {
  domain_name = local.api_domain

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.api.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "api" {
  api_id      = aws_apigatewayv2_api.sign_manifesto.id
  domain_name = aws_apigatewayv2_domain_name.api.id
  stage       = aws_apigatewayv2_stage.default.id
}

resource "aws_route53_record" "api_a" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.api_domain
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api_aaaa" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.api_domain
  type    = "AAAA"

  alias {
    name                   = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# =============================================================================
# SES — Domain identity & DKIM
# =============================================================================

resource "aws_ses_domain_identity" "site" {
  domain = var.domain_name
}

resource "aws_ses_domain_dkim" "site" {
  domain = aws_ses_domain_identity.site.domain
}

# DKIM verification DNS records
resource "aws_route53_record" "ses_dkim" {
  count = 3

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = "${aws_ses_domain_dkim.site.dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type            = "CNAME"
  ttl             = 600
  records         = ["${aws_ses_domain_dkim.site.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# SES domain verification TXT record
resource "aws_route53_record" "ses_verification" {
  allow_overwrite = true
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = "_amazonses.${var.domain_name}"
  type            = "TXT"
  ttl             = 600
  records         = [aws_ses_domain_identity.site.verification_token]
}

# Custom MAIL FROM domain — aligns envelope sender with From header
resource "aws_ses_domain_mail_from" "site" {
  domain           = aws_ses_domain_identity.site.domain
  mail_from_domain = "mail.${var.domain_name}"
}

# MX record so SES can receive bounce notifications on the MAIL FROM subdomain
resource "aws_route53_record" "ses_mail_from_mx" {
  allow_overwrite = true
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = "mail.${var.domain_name}"
  type            = "MX"
  ttl             = 600
  records         = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

# SPF record for the MAIL FROM subdomain
resource "aws_route53_record" "ses_mail_from_spf" {
  allow_overwrite = true
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = "mail.${var.domain_name}"
  type            = "TXT"
  ttl             = 600
  records         = ["v=spf1 include:amazonses.com -all"]
}
