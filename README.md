# ☁️ ctxcloud-onboarding

Scripts to streamline and validate onboarding for **Palo Alto Networks Cortex Cloud**, covering **Azure** and **AWS** environments.

These tools help validate permissions, provider registrations, diagnostic settings, and deployment prerequisites across Cortex Cloud’s **Posture Management**, **Runtime Security**, and **XSIAM** log ingestion use cases.

---

## 📁 Structure

```
ctxcloud-onboarding/
├── aws/
│   └── cortex-xsiam-s3-collector.yaml        # CloudFormation template for XSIAM S3 log ingestion
├── azure/
│   ├── az-runtime-perms-check.sh             # Bash-based Runtime permission checker
│   ├── Start-AzCortexOnboarding.ps1          # Combined PowerShell runner
│   ├── Test-AzCortexProviders.ps1            # Provider registration validation
│   └── Test-AzCortexRuntimePermissions.ps1   # RBAC + permission analysis
├── LICENSE
└── README.md
```

---

## 🧪 Azure Onboarding Scripts

### `az-runtime-perms-check.sh` (Bash)

Checks whether the current Azure CLI user:

* Is a **Global Admin** in Entra ID
* Has role assignments at both **Subscription** and **Root Management Group**
* Has wildcard permissions for key services used by **Cortex Runtime Security**
* Has all required **Azure Resource Providers** registered

**Usage:**

```bash
cd azure
chmod +x az-runtime-perms-check.sh
./az-runtime-perms-check.sh
```

> Designed for Bash 3.x (e.g., macOS default). No `jq` or external dependencies required.

---

### `Test-AzCortexRuntimePermissions.ps1`

PowerShell version of the permission validator:

* Validates wildcard permissions per Azure service category
* Shows roles granted at root and subscription levels
* Can be extended to export reports or run in pipelines

```powershell
cd azure
.\Test-AzCortexRuntimePermissions.ps1
```

---

### `Test-AzCortexProviders.ps1`

Checks registration status for all Azure resource providers needed by Cortex Cloud and prompts for registration if needed.

```powershell
cd azure
.\Test-AzCortexProviders.ps1
```

---

### `Start-AzCortexOnboarding.ps1`

Convenience wrapper that runs both of the above PowerShell checks.

```powershell
cd azure
.\Start-AzCortexOnboarding.ps1
```

---

## ☁️ AWS Onboarding: Cortex XSIAM Log Collector

### `cortex-xsiam-s3-collector.yaml`

CloudFormation template for setting up the **S3 + SQS + IAM** integration needed to forward **CloudTrail logs to Cortex XSIAM**.

**Resources Deployed:**

* SQS queue for log delivery
* IAM Role (with external ID support) granting Cortex access
* SQS policy for S3 bucket to push events

**Parameters Required:**

* `CortexAWSAccountId`
* `ExternalId`
* `CloudTrailBucketName`
* (Optional) `KMSKeyARN`

Use this template when integrating AWS logs with **XSIAM Data Collector (S3 Source)**.

---

## 🔐 Requirements

* **Azure**: Logged in via `az login` or `Connect-AzAccount`; permissions at both Subscription + MG level
* **AWS**: Access to deploy CF templates in the logging account; existing CloudTrail bucket required

---

## 🙋‍♂️ Author & Support

These scripts were created by [@adilio](https://github.com/adilio) as part of field testing and Cortex Cloud onboarding troubleshooting.

> These tools are **not officially supported by Palo Alto Networks**, and come **as-is with no warranty or guarantees**. Use them as guidance or reference, not production-certified solutions.

---

## 🤝 Contributing

Contributions are welcome!

* Open [issues](https://github.com/ctxcloud-field/ctxcloud-onboarding/issues) or submit [pull requests](https://github.com/ctxcloud-field/ctxcloud-onboarding/pulls)
* If you’re a Palo Alto Networks employee, feel free to reach out to **@adilio internally** to collaborate or contribute

---

## 📄 License

Licensed under the [MIT License](./LICENSE).
