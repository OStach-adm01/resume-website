resource "aws_cloudfront_response_headers_policy" "security" {
  name = "${local.name}-security"
  security_headers_config {
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = false
      preload                    = false
      override                   = true
    }
    content_security_policy {
      content_security_policy = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"
      override                = true
    }
  }
}
resource "aws_acm_certificate" "site" {
  provider                  = aws.edge
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
}
resource "cloudflare_dns_record" "validation" {
  for_each = toset([var.domain_name, "www.${var.domain_name}"])
  zone_id  = var.cloudflare_zone_id
  name     = one([for dvo in aws_acm_certificate.site.domain_validation_options : dvo.resource_record_name if dvo.domain_name == each.value])
  content  = one([for dvo in aws_acm_certificate.site.domain_validation_options : dvo.resource_record_value if dvo.domain_name == each.value])
  type     = "CNAME"
  ttl      = 60
  proxied  = false
}
resource "aws_acm_certificate_validation" "site" {
  provider                = aws.edge
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in cloudflare_dns_record.validation : record.name]
}
resource "cloudflare_dns_record" "origin" {
  zone_id = var.cloudflare_zone_id
  name    = local.origin_name
  type    = "A"
  content = aws_eip.node.public_ip
  ttl     = 60
  proxied = false
}
data "aws_cloudfront_cache_policy" "disabled" { name = "Managed-CachingDisabled" }
data "aws_cloudfront_cache_policy" "optimized" { name = "Managed-CachingOptimized" }
data "aws_cloudfront_origin_request_policy" "api" { name = "Managed-AllViewerExceptHostHeader" }
resource "aws_cloudfront_cache_policy" "html" {
  name        = "${local.name}-html"
  min_ttl     = 0
  default_ttl = 60
  max_ttl     = 300
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}
# WAF is deliberately excluded from this credit-budgeted lab; the API has request throttling.
#trivy:ignore:AWS-0011
resource "aws_cloudfront_distribution" "site" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = local.name
  aliases         = [var.domain_name, "www.${var.domain_name}"]
  price_class     = "PriceClass_100"
  http_version    = "http2and3"
  origin {
    domain_name              = aws_s3_bucket.artifacts.bucket_regional_domain_name
    origin_id                = "assets"
    origin_path              = "/assets"
    origin_access_control_id = aws_cloudfront_origin_access_control.assets.id
  }
  origin {
    domain_name = cloudflare_dns_record.origin.name
    origin_id   = "k3s"
    custom_header {
      name  = "X-Origin-Token"
      value = random_password.origin.result
    }
    custom_origin_config {
      http_port              = 30080
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  origin {
    domain_name = "${aws_api_gateway_rest_api.recruiter.id}.execute-api.${var.region}.amazonaws.com"
    origin_id   = "api"
    origin_path = "/prod"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  default_cache_behavior {
    target_origin_id           = "k3s"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.html.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }
  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = "api"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.api.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }
  ordered_cache_behavior {
    path_pattern               = "/_astro/*"
    target_origin_id           = "assets"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
resource "aws_cloudfront_origin_access_control" "assets" {
  name                              = "${local.name}-assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "cloudflare_dns_record" "site" {
  for_each = toset([var.domain_name, "www.${var.domain_name}"])
  zone_id  = var.cloudflare_zone_id
  name     = each.value
  type     = "CNAME"
  content  = aws_cloudfront_distribution.site.domain_name
  ttl      = 60
  proxied  = false
}
