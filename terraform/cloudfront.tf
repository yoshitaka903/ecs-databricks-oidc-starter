# CloudFront Distribution for HTTPS access

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront for ${var.app_name}"
  price_class         = "PriceClass_200"
  
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "alb-${var.app_name}"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb-${var.app_name}"
    viewer_protocol_policy = "redirect-to-https"
    
    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization", "CloudFront-Forwarded-Proto"]
      
      cookies {
        forward = "all"
      }
    }
    
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  
  tags = merge(var.tags, {
    Name = "${var.app_name}-cloudfront"
  })
}

# Output for CloudFront domain
output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_https_url" {
  description = "HTTPS URL via CloudFront"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "oauth_redirect_uri_cloudfront" {
  description = "OAuth Redirect URI for CloudFront"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}/oauth/callback"
}
