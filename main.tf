locals {
  // Get distinct list of domains and SANs
  domain_names = concat([var.domain_name], [for s in var.subject_alternative_names : s.name])
  domain_zones = concat([var.zone_name], [for s in var.subject_alternative_names : s.zone])

  distinct_domain_names = distinct(local.domain_names)
  distinct_domain_zones = distinct(local.domain_zones)

  # // Copy domain_validation_options for the distinct domain names
  domain_validation_options = var.create_certificate ? [for k, v in aws_acm_certificate.this[0].domain_validation_options : tomap(v)] : []

  map_zone_name_to_zone_id     = zipmap(local.distinct_domain_zones, data.aws_route53_zone.validation_zones[*].zone_id)
  map_domain_name_to_zone_name = zipmap(local.domain_names, local.domain_zones)

}

resource "aws_acm_certificate" "this" {
  count = var.create_certificate ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = local.distinct_domain_names
  validation_method         = var.validation_method

  options {
    certificate_transparency_logging_preference = var.certificate_transparency_logging_preference ? "ENABLED" : "DISABLED"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_route53_zone" "validation_zones" {
  count = length(local.distinct_domain_zones)

  name         = element(local.distinct_domain_zones, count.index)
  private_zone = false
}

resource "aws_route53_record" "validation" {
  count = var.create_certificate && var.validation_method == "DNS" && var.validate_certificate ? length(local.distinct_domain_names) : 0

  zone_id = lookup(local.map_zone_name_to_zone_id, lookup(local.map_domain_name_to_zone_name, element(local.domain_validation_options, count.index)["domain_name"]))
  name    = element(local.domain_validation_options, count.index)["resource_record_name"]
  type    = element(local.domain_validation_options, count.index)["resource_record_type"]
  ttl     = 60

  records = [
    element(local.domain_validation_options, count.index)["resource_record_value"]
  ]

  allow_overwrite = var.validation_allow_overwrite_records

  depends_on = [aws_acm_certificate.this]
}

resource "aws_acm_certificate_validation" "this" {
  count = var.create_certificate && var.validation_method == "DNS" && var.validate_certificate && var.wait_for_validation ? 1 : 0

  certificate_arn = aws_acm_certificate.this[0].arn

  validation_record_fqdns = aws_route53_record.validation.*.fqdn
}
