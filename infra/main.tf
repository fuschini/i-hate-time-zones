# =============================================================================
# Data Sources
# =============================================================================

# The Route 53 hosted zone for ihatetimezones.com already exists
data "aws_route53_zone" "main" {
  name = var.domain_name
}

# =============================================================================
# S3 — Static site bucket (private, served via CloudFront OAC)
# =============================================================================

resource "aws_s3_bucket" "site" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Allow CloudFront OAC to read objects from this bucket
data "aws_iam_policy_document" "site_bucket_policy" {
  statement {
    sid     = "AllowCloudFrontOAC"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket_policy.json
}

# =============================================================================
# ACM — TLS certificate (must be in us-east-1 for CloudFront)
# =============================================================================

resource "aws_acm_certificate" "site" {
  provider = aws.us_east_1

  domain_name               = local.site_domain
  subject_alternative_names = local.acm_sans
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation records
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.site.domain_validation_options : dvo.domain_name => {
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

# Wait for the certificate to be fully validated before using it
resource "aws_acm_certificate_validation" "site" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# =============================================================================
# CloudFront — Origin Access Control
# =============================================================================

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${local.bucket_name}-oac"
  description                       = "OAC for ${local.site_domain}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# =============================================================================
# CloudFront Function — www-to-apex redirect (prod only)
# =============================================================================

resource "aws_cloudfront_function" "www_redirect" {
  count = local.is_prod ? 1 : 0

  name    = "ihatetimezones-www-redirect"
  runtime = "cloudfront-js-2.0"
  comment = "Redirect www.${var.domain_name} to ${var.domain_name}"
  publish = true

  code = <<-FUNCTION
    function handler(event) {
      var request = event.request;
      var host = request.headers.host.value;

      if (host.startsWith('www.')) {
        var newUrl = 'https://${var.domain_name}' + request.uri;
        return {
          statusCode: 301,
          statusDescription: 'Moved Permanently',
          headers: {
            'location': { value: newUrl },
            'cache-control': { value: 'max-age=3600' }
          }
        };
      }

      return request;
    }
  FUNCTION
}

# =============================================================================
# CloudFront — Distribution
# =============================================================================

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = local.cloudfront_aliases
  comment             = "${local.site_domain} static site"
  price_class         = "PriceClass_100" # US, Canada, Europe only (cheapest)

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "S3-${local.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${local.bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true # gzip + brotli

    # 24-hour cache
    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 86400

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    # Attach www redirect function in prod
    dynamic "function_association" {
      for_each = local.is_prod ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.www_redirect[0].arn
      }
    }
  }

  # S3 with OAC returns 403 for missing objects (not 404)
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_acm_certificate_validation.site]
}

# =============================================================================
# Route 53 — DNS records pointing to CloudFront
# =============================================================================

# A record (IPv4)
resource "aws_route53_record" "site_a" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.site_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

# AAAA record (IPv6)
resource "aws_route53_record" "site_aaaa" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.site_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

# www records (prod only) — point to the same CloudFront distribution
# so the CloudFront Function can handle the redirect
resource "aws_route53_record" "www_a" {
  count = local.is_prod ? 1 : 0

  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_aaaa" {
  count = local.is_prod ? 1 : 0

  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

# Google Search Console verification (prod only)
resource "aws_route53_record" "google_site_verification" {
  count = local.is_prod ? 1 : 0

  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = ["google-site-verification=UpikI6FXmpl9xdU9U7qnUzABawDuxxoWBvLdKS42tlk"]
}

# PostHog reverse proxy CNAME (prod only)
resource "aws_route53_record" "posthog_proxy" {
  count = local.is_prod ? 1 : 0

  zone_id = data.aws_route53_zone.main.zone_id
  name    = "m.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["3e4e068b1fd5fbc929cb.cf-prod-us-proxy.proxyhog.com"]
}
