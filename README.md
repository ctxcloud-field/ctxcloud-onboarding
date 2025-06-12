# ☁️ ctxcloud-onboarding

Scripts to streamline and validate onboarding for **Cortex Cloud** by **Palo Alto Networks**, supporting both **Azure** and **AWS** environments.

These tools help validate permissions, resource provider registrations, diagnostic settings, and deployment readiness for Cortex Cloud’s **Cloud Posture Security**, **Cloud Runtime Security**, and XSIAM's **S3 Bucket log collection** modules.

---

## 📁 Structure

```
ctxcloud-onboarding/
├── aws/
│   └── cortex-xsiam-s3-collector.yaml        # CloudFormation template for XSIAM S3 log ingestion
├── azure/
│   ├── az-runtime-perms-check.sh             # Bash-based Runtime permission checker
│   ├── Start-AzCortexOnboarding.ps1          # PowerShell deployment script using wizard template
│   ├── Test-AzCortexProviders.ps1            # Provider registration validation
│   └── Test-AzCortexRuntimePermissions.ps1   # RBAC + permission analysis
├── LICENSE
└── README.md
```

---

## 🧪 Azure Onboarding Scripts

### `az-runtime-perms-check.sh` (Bash)

Checks whether the current Azure CLI user:

* Is a **Global Administrator** in Entra ID
* Has role assignments at both **Subscription** and **Root Management Group**
* Has wildcard permissions across services required by **Cortex Runtime Security**
* Has all required **Azure Resource Providers** registered

**Usage:**

```bash
cd azure
bash az-runtime-perms-check.sh
```

> Designed for Bash 3.x (e.g., macOS default). No jq or external dependencies required.

---

### `Test-AzCortexRuntimePermissions.ps1`

PowerShell version of the runtime permissions checker. It:

* Validates wildcard access to critical Azure services
* Checks roles assigned at both subscription and management group level
* Can be extended to export results

**Usage:**

```powershell
cd azure
.\Test-AzCortexRuntimePermissions.ps1
```

---

### `Test-AzCortexProviders.ps1`

Checks if required Azure **Resource Providers** are registered (e.g., `Microsoft.Compute`, `Microsoft.Storage`, etc.). Optionally prompts to register missing providers.

**Usage:**

```powershell
cd azure
.\Test-AzCortexProviders.ps1
```

---

### `Start-AzCortexOnboarding.ps1`

This script is the **PowerShell equivalent** of the onboarding wizard’s default `main.sh`. It validates the environment and deploys the **ARM template** for Cortex Cloud onboarding.

**Requirements:**

* `template.json` – downloaded from the Cortex Cloud onboarding wizard
* `parameters.json` – also from the wizard

> ✅ **For convenience**, copy both `template.json` and `parameters.json` into the same directory as this script before running.

**Usage:**

```powershell
cd azure
.\Start-AzCortexOnboarding.ps1
```

---

## ☁️ AWS Onboarding: Cortex XSIAM Log Collector

### `cortex-xsiam-s3-collector.yaml`

CloudFormation template for setting up the **S3 + SQS + IAM role** integration needed to forward **CloudTrail logs to Cortex XSIAM**.

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

## 🔐 Requirements

* **Azure**: Must be logged in (`az login` or `Connect-AzAccount`), with permissions at both Subscription and Management Group scope
* **AWS**: Admin access to the account that owns the CloudTrail bucket

---

## 🙋‍♂️ Author & Support

These scripts were written by [@adilio](https://github.com/adilio) as part of testing and troubleshooting Cortex Cloud onboarding.

> These tools are **not officially affiliated with or supported by Palo Alto Networks**, and are provided **as-is, without warranty**. Use them as references or helpers, not production-certified solutions.

---

## 🤝 Contributing

Contributions are welcome!

* Open [issues](https://github.com/ctxcloud-field/ctxcloud-onboarding/issues) or submit [pull requests](https://github.com/ctxcloud-field/ctxcloud-onboarding/pulls)
* If you’re a **Palo Alto Networks** colleague, feel free to reach out to **@adilio internally** if you’d like to collaborate

---

## 📄 License

Licensed under the [MIT License](./LICENSE).
