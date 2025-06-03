<#
.SYNOPSIS
☁️ Cortex Azure Onboarding Tool (PowerShell Version)

.DESCRIPTION
This script automates onboarding to Palo Alto Cortex Cloud by:
- Creating a user-assigned managed identity
- Assigning custom roles at the management group level
- Deploying an ARM template with policy definitions
- Triggering remediation if needed

.NOTES
Author: Your Friendly PowerShell Engineer ✨
#>

[CmdletBinding()]
param ()

# ================
# 📁 Setup Logging
# ================
$TimeStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile = "onboarding-$TimeStamp.log"
Start-Transcript -Path $LogFile -Append

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $emoji = switch ($Level) {
        "INFO" { "🟢" }
        "ERROR" { "🔴" }
        default { "✉️" }
    }
    Write-Host "[$ts] $emoji $Message"
}

# ======================
# 📄 Load Config from parameters.sh
# ======================
$paramFile = Join-Path $PSScriptRoot "parameters.sh"
if (-Not (Test-Path $paramFile)) {
    Write-Log "parameters.sh not found." "ERROR"
    exit 1
}

Get-Content $paramFile | ForEach-Object {
    if ($_ -match '^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*"?(.*?)"?\s*$') {
        Set-Variable -Name $matches[1] -Value $matches[2] -Scope Global
    }
}

# ===================
# ✨ Validate Az CLI
# ===================
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    Write-Log "Azure CLI is not installed." "ERROR"
    exit 1
}

try {
    az account show | Out-Null
    Write-Log "Azure CLI is authenticated."
} catch {
    Write-Log "Azure CLI is not authenticated. Run 'az login' first." "ERROR"
    exit 1
}

# ===========================
# ⚖️ Normalize Inputs
# ===========================
$Location = $location.ToLower().Trim()
$ResourceGroup = $resource_group.Trim()
$AssignedIdentityName = "cortex-uaid-$resource_suffix"

# =============================
# 🕵️ Create or Fetch Identity
# =============================
Write-Log "Checking for managed identity: $AssignedIdentityName"
$identity = az identity list --subscription $subscription_id --query "[?name=='$AssignedIdentityName']" -o json | ConvertFrom-Json

if (-not $identity) {
    Write-Log "Creating managed identity $AssignedIdentityName..."
    for ($i = 0; $i -lt 5; $i++) {
        try {
            az identity create --name $AssignedIdentityName --resource-group $ResourceGroup --subscription $subscription_id --location $Location | Out-Null
            break
        } catch {
            Write-Log "Retrying identity creation..."
            Start-Sleep -Seconds 5
        }
    }
    Start-Sleep -Seconds 10
    $identity = az identity list --subscription $subscription_id --query "[?name=='$AssignedIdentityName']" -o json | ConvertFrom-Json
}

if (-not $identity) {
    Write-Log "Failed to retrieve managed identity." "ERROR"
    exit 1
}

$uaid = $identity[0].id
$uaid_pid = $identity[0].principalId
Write-Log "Managed identity created: $uaid"

# ==============================
# 🔐 Assign Role to Identity
# ==============================
Start-Sleep -Seconds 10
az login --scope https://graph.microsoft.com/.default
Write-Log "Assigning Owner role to identity..."
az role assignment create --assignee $uaid_pid --role "Owner" --scope "/providers/Microsoft.Management/managementGroups/$management_group" --output none
Write-Log "Role assignment successful."

# ============================
# 🚀 Deploy ARM Template
# ============================
Write-Log "Deploying onboarding ARM template..."
$dep_output = az deployment mg create `
    --name "cortex-policy-$resource_suffix" `
    --management-group $management_group `
    --template-file "template.json" `
    --location $Location `
    --parameters uaid=$uaid subscriptionId=$subscription_id resourceGroup=$ResourceGroup `
    --query "[properties.outputs.policyAssignmentName.value]" `
    -o tsv

$PolicyAssignmentName = $dep_output.Trim()
Write-Log "Policy assignment created: $PolicyAssignmentName"

# ================================
# ♻️ Trigger Remediation
# ================================
Write-Log "Waiting for policy evaluation..."
$maxAttempts = 30
$attempt = 0

while ($attempt -lt $maxAttempts) {
    $nonCompliant = az policy state summarize -m $management_group `
        --query "policyAssignments[?contains(policyAssignmentId,'$PolicyAssignmentName')].results.nonCompliantResources" `
        -o tsv

    if ($nonCompliant -match '^\d+$' -and [int]$nonCompliant -gt 0) {
        $ts = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
        Write-Log "Found $nonCompliant non-compliant resources. Starting remediation..."
        $remediationStatus = az policy remediation create `
            --name "cortex-remediation-$resource_suffix-$ts" `
            --management-group $management_group `
            --policy-assignment $PolicyAssignmentName `
            --query "provisioningState" -o tsv
        Write-Log "Remediation task status: $remediationStatus"
        break
    }

    Start-Sleep -Seconds 10
    $attempt++
}

if ($attempt -eq $maxAttempts) {
    Write-Log "No non-compliant resources detected within timeout window."
}

Write-Log "🎉 Cortex onboarding complete. Compliance policy is in place."
Stop-Transcript
