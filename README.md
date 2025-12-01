# ctxcloud-onboarding

Scripts to streamline and validate onboarding for **Cortex Cloud** by **Palo Alto Networks**, supporting both **Azure** and **AWS** environments.

These tools help validate permissions, resource provider registrations, diagnostic settings, and deployment readiness for Cortex Cloud’s **Cloud Posture Security**, **Cloud Runtime Security**, and XSIAM's **S3 Bucket log collection** modules.

> ℹ️ **Azure onboarding has moved** to the consolidated `cc-permissions-preflight` script. The PowerShell/Bash scripts in `azure/` are now deprecated and kept only for reference.

---

## Structure

```
ctxcloud-onboarding/
├── aws/
│   └── cortex-xsiam-s3-collector.yaml        # CloudFormation template for XSIAM S3 log ingestion
├── azure/ (deprecated, archived for reference)
│   ├── deprecated-az-runtime-perms-check.sh
│   ├── deprecated-Start-AzCortexOnboarding.ps1
│   ├── deprecated-Test-AzCortexProviders.ps1
│   └── deprecated-Test-AzCortexRuntimePermissions.ps1
├── LICENSE
└── README.md
```

---

## Azure Onboarding: cc-permissions-preflight

Use the consolidated **cc-permissions-preflight** script from Palo Alto Networks for Azure onboarding and preflight checks.

* GitHub repo: https://github.com/PaloAltoNetworks/cc-permissions-preflight
* Latest script (raw): https://raw.githubusercontent.com/PaloAltoNetworks/cc-permissions-preflight/refs/heads/main/preflight_check.sh

**Usage:**

```bash
# run the latest preflight check
curl -fsSL https://raw.githubusercontent.com/PaloAltoNetworks/cc-permissions-preflight/refs/heads/main/preflight_check.sh -o preflight_check.sh
bash preflight_check.sh
```

The script validates Azure permissions (subscription + management group scopes), required resource providers, and other runtime prerequisites needed for Cortex Cloud onboarding.

### Deprecated Azure scripts (archived)

The PowerShell and Bash scripts in `azure/` remain checked in for historical reference but are not maintained. Filenames are prefixed with `deprecated-` to discourage use. Prefer the `cc-permissions-preflight` script above for all Azure onboarding and validation needs.

---

## AWS Onboarding: Cortex XSIAM Log Collector

### `cortex-xsiam-s3-collector.yaml`

CloudFormation template for setting up the **S3 + SQS + IAM role** integration needed to forward **CloudTrail logs to Cortex XSIAM**. This version presumes that you have an existing S3 bucket for CloudTrail logging already setup. As well, conditional logic has been updated for KMS Key ARN.

**Resources Deployed:**

* SQS queue for log delivery
* IAM Role with external ID support
* SQS policy for bucket-to-queue delivery

**Parameters:**

* `CortexAWSAccountId`
* `ExternalId`
* `CloudTrailBucketName`
* (Optional) `KMSKeyARN`

---

## Requirements

* **Azure**: Must be logged in (`az login` or `Connect-AzAccount`), with permissions at both Subscription and Management Group scope
* **AWS**: Admin access to the account that owns the CloudTrail bucket

---

## Author & Support

These scripts were written by [@adilio](https://github.com/adilio) as part of testing and troubleshooting Cortex Cloud onboarding.

> These tools are **not officially affiliated with or supported by Palo Alto Networks**, and are provided **as-is, without warranty**. Use them as references or helpers, not production-certified solutions.

---

## Contributing

Contributions are welcome!

* Open [issues](https://github.com/ctxcloud-field/ctxcloud-onboarding/issues) or submit [pull requests](https://github.com/ctxcloud-field/ctxcloud-onboarding/pulls)
* If you’re a **Palo Alto Networks** colleague, feel free to reach out to **Adil L internally** if you’d like to collaborate

---

## License

Licensed under the [MIT License](./LICENSE).
