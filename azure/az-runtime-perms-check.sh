#!/bin/bash
set -e

echo ""
echo "☁️  Cortex Cloud Azure Permission & Onboarding Checker"
echo "======================================================"
echo ""
echo "This script will:"
echo " • Confirm your Azure CLI is working and up to date"
echo " • Show your Azure login context"
echo " • Check for Entra (AAD) Global Admin (needed for CIEM)"
echo " • Validate your Azure role assignments at both Root Management Group & Subscription"
echo " • Ensure all required Azure Resource Providers are registered"
echo ""
echo "------------------------------------------------------"
echo ""

# ===== Simple helper for color (optional, works everywhere) =====
red() { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }

# ===== Check for Azure CLI and version =====
if ! command -v az >/dev/null 2>&1; then
  red "❌ Azure CLI (az) is not installed."
  echo "   Please install Azure CLI: https://aka.ms/installazurecli"
  exit 1
fi

AZ_VER=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0")
MIN_VER="2.14.0"
if [ "$(printf '%s\n' "$MIN_VER" "$AZ_VER" | sort -V | head -n1)" != "$MIN_VER" ]; then
  red "❌ Azure CLI version $MIN_VER or newer required. You have: $AZ_VER"
  echo "   Please upgrade: https://docs.microsoft.com/cli/azure/update-azure-cli"
  exit 1
fi

# ===== Check login =====
if ! az account show >/dev/null 2>&1; then
  red "❌ Not logged into Azure CLI."
  echo "   Please run: az login"
  exit 1
fi

# ===== Gather user info =====
user_id=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
user_upn=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || true)
sub_id=$(az account show --query id -o tsv 2>/dev/null || true)
tenant_id=$(az account show --query tenantId -o tsv 2>/dev/null || true)
sub_state=$(az account show --query "state" -o tsv 2>/dev/null || echo "Unknown")

if [ -z "$user_id" ] || [ -z "$user_upn" ]; then
  red "❌ Failed to get your user identity from Azure."
  echo "   Please make sure you are using a valid AAD user account."
  exit 1
fi

echo "👤 User:         $user_upn"
echo "🆔 User Object:  $user_id"
echo "🏢 Tenant ID:    $tenant_id"
echo "🧾 Subscription: $sub_id"
echo ""

readonly_or_disabled=0

if [ "$sub_state" = "Disabled" ]; then
  yellow "⚠️ Your subscription ($sub_id) is DISABLED."
  echo "No actions can be performed on a disabled subscription. Most checks will continue, but some results may be incomplete."
  readonly_or_disabled=1
elif [ "$sub_state" = "Warned" ]; then
  yellow "⚠️ Your subscription ($sub_id) is in a warned state."
  readonly_or_disabled=1
fi

# ===== Check Entra (AAD) Global Administrator role =====
echo "🔍 Checking Entra (AAD) Global Administrator role..."
if ! az rest --help >/dev/null 2>&1; then
  yellow "⚠️ Skipping Global Admin check: 'az rest' not available in this Azure CLI version."
else
  # Get Global Admin role object id
  role_id_output=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/directoryRoles" \
    --query "value[?displayName=='Global Administrator'].id" -o tsv 2>&1)
  if echo "$role_id_output" | grep -qi "Forbidden\|Insufficient privileges"; then
    red "❌ You do not have sufficient Entra (Azure AD) permissions to query Global Admin role membership."
    echo "At minimum, you need the 'Directory Readers' role to perform this check."
    echo "However, to enable full CIEM (identity and entitlement analytics) in Cortex Cloud, onboard at the TENANT (directory) level as a Global Administrator."
    echo "Please ask your Entra/Azure admin for the right permissions and scope."
  elif echo "$role_id_output" | grep -qiE "Unauthorized|Authentication"; then
    red "❌ Azure CLI authentication issue (token expired or revoked)."
    echo "Please run: az login"
  else
    role_id=$(echo "$role_id_output" | head -n1)
    if [ -z "$role_id" ]; then
      yellow "⚠️ No active Global Administrator role found (may be inactive or blocked)."
    else
      # Get members of the Global Admin role
      members_output=$(az rest --method GET \
        --url "https://graph.microsoft.com/v1.0/directoryRoles/$role_id/members" \
        --query "value[].id" -o tsv 2>&1)
      if echo "$members_output" | grep -qi "Forbidden\|Insufficient privileges"; then
        red "❌ You do not have permission to list Global Admin members."
        echo "You need at least the 'Directory Readers' role."
      elif echo "$members_output" | grep -q "$user_id"; then
        green "✅ You ARE a Global Administrator."
        echo ""
        echo "ℹ️ To enable full CIEM visibility into Entra (Azure AD) identities, onboarding must be done at the TENANT (directory) level."
        echo "Onboarding only at the Subscription or Management Group level will limit CIEM coverage for Azure identities."
      else
        red "❌ You are NOT a Global Administrator."
      fi
    fi
  fi
fi
echo ""

# ===== Management Group check (with provider error catch) =====
echo "🔍 Checking Root Management Group..."
root_mg_output=$(az account management-group list --query "[?properties.parent==null].name | [0]" -o tsv 2>&1 || true)
if echo "$root_mg_output" | grep -q "could not be found in the namespace 'Microsoft.Management'"; then
  red "❌ The Microsoft.Management resource provider is not registered."
  echo "Please register it in the Azure Portal or run:"
  echo "az provider register --namespace Microsoft.Management"
  echo "After registration, re-run this script."
  readonly_or_disabled=1
  root_mg=""
else
  root_mg="$root_mg_output"
fi
root_scope="/providers/Microsoft.Management/managementGroups/$root_mg"
sub_scope="/subscriptions/$sub_id"

# ===== Role assignments (with ReadOnlyDisabledSubscription error catch) =====
root_roles_output=$(az role assignment list --assignee "$user_id" --scope "$root_scope" --query "[].roleDefinitionName" -o tsv 2>&1 || true)
sub_roles_output=$(az role assignment list --assignee "$user_id" --scope "$sub_scope" --query "[].roleDefinitionName" -o tsv 2>&1 || true)

if echo "$root_roles_output$sub_roles_output" | grep -q "ReadOnlyDisabledSubscription"; then
  yellow "⚠️ Your subscription is disabled and marked as read-only."
  echo "You cannot perform any write actions or assign roles until it is re-enabled by your Azure admin."
  echo "Azure CLI error:"
  echo "$root_roles_output$sub_roles_output" | grep "ReadOnlyDisabledSubscription" | head -1
  readonly_or_disabled=1
fi

root_roles=$(echo "$root_roles_output" | grep -v "^ERROR:" || true)
sub_roles=$(echo "$sub_roles_output" | grep -v "^ERROR:" || true)

if [ -z "$root_roles" ] && [ -z "$sub_roles" ]; then
  yellow "⚠️ You do not have any roles at the Root Management Group or Subscription level, or your subscription is disabled/read-only."
  echo "Please have an Azure administrator assign you appropriate permissions, or enable your subscription."
else
  if [ -n "$root_roles" ]; then
    green "✅ Root MG roles:"
    echo "$root_roles" | sed 's/^/   🔒 /'
  fi
  if [ -n "$sub_roles" ]; then
    green "✅ Subscription roles:"
    echo "$sub_roles" | sed 's/^/   🔑 /'
  fi
fi
echo ""

# ===== Resource Provider Registration Check (Microsoft.Management included) =====
echo "🛠 Checking Azure Resource Providers and prompting for registration if needed..."

providers="
Microsoft.Management
Microsoft.Compute
Microsoft.Storage
Microsoft.Network
Microsoft.KeyVault
Microsoft.ContainerService
Microsoft.ContainerRegistry
Microsoft.Insights
Microsoft.Authorization
Microsoft.DocumentDB
Microsoft.Web
Microsoft.PolicyInsights
Microsoft.EventHub
Microsoft.Security
Microsoft.Aadiam
Microsoft.Communication
"

for p in $providers; do
  state=$(az provider show --namespace "$p" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
  if [ "$state" != "Registered" ]; then
    yellow "⚠️  $p → $state"
    printf "❓ Do you want to register %s? [y/N]: " "$p"
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo "🔧 Registering $p ..."
      if az provider register --namespace "$p" >/dev/null 2>&1; then
        green "✅ Registered $p successfully."
      else
        red "❌ Failed to register $p. You may need additional permissions."
      fi
    else
      yellow "⏭ Skipping registration for $p."
    fi
    echo "🧾 Check status later with: az provider show --namespace $p --query registrationState -o tsv"
    echo ""
  else
    green "✅ $p → Already Registered"
  fi
done

echo ""
if [ "$readonly_or_disabled" = "1" ]; then
  yellow "⚠️ Reminder: Your subscription is disabled or read-only. Some checks and onboarding steps may not be possible until it is re-enabled by your Azure admin."
  echo "Once your subscription is enabled, re-run this script for a full health check."
else
  green "🎉 All required permission checks complete. You can proceed with Cortex Cloud onboarding!"
fi
