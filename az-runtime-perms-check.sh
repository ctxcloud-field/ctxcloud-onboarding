#!/bin/bash

# =============================================================================
# Cortex Cloud Runtime Security Permission Checker for Azure (Bash 3 Compatible)
# -----------------------------------------------------------------------------
# This script validates whether the current Azure CLI user has:
#   1. Role assignments at the Subscription and Tenant Root MG level
#   2. Wildcard permissions across all required services (e.g., Microsoft.Compute/*)
#   3. Entra Global Administrator role (if az rest is available)
#
# Works on macOS Bash 3.x — no jq, no zsh required.
# =============================================================================

set -e

# =============================
# User Context and Azure Info
# =============================
echo "🔍 Gathering current user details..."
user_id=$(az ad signed-in-user show --query id -o tsv)
user_upn=$(az ad signed-in-user show --query userPrincipalName -o tsv)
sub_id=$(az account show --query id -o tsv)
tenant_id=$(az account show --query tenantId -o tsv)

echo ""
echo "🧾 Azure Context:"
echo "👤 UPN:          $user_upn"
echo "🆔 Object ID:    $user_id"
echo "🏢 Tenant ID:    $tenant_id"
echo "🧾 Subscription: $sub_id"

# ======================================
# Check Entra Global Administrator Role
# ======================================
echo ""
echo "🔍 Checking Entra Global Administrator role membership..."

if ! az rest --help >/dev/null 2>&1; then
  echo "⚠️  Skipping Global Admin check: 'az rest' not available in this Azure CLI version."
else
  role_id=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/directoryRoles" \
    --query "value[?displayName=='Global Administrator'].id" -o tsv 2>/dev/null)

  if [ -z "$role_id" ]; then
    echo "⚠️  Global Administrator role not found. (May be inactive or access blocked)"
  else
    members=$(az rest --method GET \
      --url "https://graph.microsoft.com/v1.0/directoryRoles/$role_id/members" \
      --query "value[].id" -o tsv 2>/dev/null)

    if echo "$members" | grep -q "$user_id"; then
      echo "✅ You ARE a Global Administrator in Entra ID."
    else
      echo "❌ You are NOT a Global Administrator in Entra ID."
    fi
  fi
fi

# =======================================
# Role Assignments from Multiple Scopes
# =======================================
echo ""
echo "📍 Gathering roles from multiple scopes..."

root_mg=$(az account management-group list --query "[?properties.parent==null].name | [0]" -o tsv)
root_scope="/providers/Microsoft.Management/managementGroups/$root_mg"
root_roles=$(az role assignment list --assignee "$user_id" --scope "$root_scope" --query "[].roleDefinitionName" -o tsv 2>/dev/null || true)

sub_scope="/subscriptions/$sub_id"
sub_roles=$(az role assignment list --assignee "$user_id" --scope "$sub_scope" --query "[].roleDefinitionName" -o tsv 2>/dev/null || true)

user_roles=$(printf "%s\n%s\n" "$root_roles" "$sub_roles" | sort | uniq)

if [ -z "$user_roles" ]; then
  echo "❌ No roles assigned to user at root or subscription scope."
  exit 1
fi

echo ""
echo "📌 Root MG: $root_mg"
echo "$root_roles" | sed 's/^/   🔒 /'

echo ""
echo "📌 Subscription: $sub_id"
echo "$sub_roles" | sed 's/^/   🔑 /'

echo ""
echo "📜 Combined Roles:"
while IFS= read -r r; do echo " - $r"; done <<< "$user_roles"

# =========================================
# Permission Categories Required by Cortex
# =========================================
echo ""
echo "🔎 Checking permission categories required by Cortex Cloud Runtime Security..."

categories=(
  "Compute"
  "Storage"
  "Networking"
  "Key Vault"
  "Container Services"
  "Container Registry"
  "Monitoring & Logs"
  "IAM / Role Assignments"
  "Cosmos DB"
  "App Services"
  "Policy Insights"
  "Event Hubs"
)

wildcards=(
  "Microsoft.Compute/*"
  "Microsoft.Storage/*"
  "Microsoft.Network/*"
  "Microsoft.KeyVault/*"
  "Microsoft.ContainerService/*"
  "Microsoft.ContainerRegistry/*"
  "Microsoft.Insights/*"
  "Microsoft.Authorization/roleAssignments/*"
  "Microsoft.DocumentDB/*"
  "Microsoft.Web/*"
  "Microsoft.PolicyInsights/*"
  "Microsoft.EventHub/*"
)

# Loop through categories and check if any role has matching wildcard or '*'
for i in "${!categories[@]}"; do
  category="${categories[$i]}"
  wildcard="${wildcards[$i]}"
  perm_status="❌ No"

  while IFS= read -r role; do
    actions=$(az role definition list --name "$role" --query "[].permissions[].actions[]" -o tsv 2>/dev/null || true)
    if echo "$actions" | grep -q "^$wildcard\|^\*$"; then
      perm_status="✅ Yes"
      break
    fi
  done <<< "$user_roles"

  printf "🔐 %-25s → %-45s: %s\n" "$category" "$wildcard" "$perm_status"
done

# =====================================================
# Provider Registration Check & Prompted Auto-Register
# =====================================================
echo ""
echo "🛠 Checking Azure Resource Providers and prompting for registration..."

providers=(
  "Microsoft.Compute"
  "Microsoft.Storage"
  "Microsoft.Network"
  "Microsoft.KeyVault"
  "Microsoft.ContainerService"
  "Microsoft.ContainerRegistry"
  "Microsoft.Insights"
  "Microsoft.Authorization"
  "Microsoft.DocumentDB"
  "Microsoft.Web"
  "Microsoft.PolicyInsights"
  "Microsoft.EventHub"
  "Microsoft.Security"
  "Microsoft.Aadiam"
  "Microsoft.Communication"
  "Microsoft.Datadog"
)

for p in "${providers[@]}"; do
  state=$(az provider show --namespace "$p" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
  
  if [ "$state" != "Registered" ]; then
    echo "⚠️  $p → $state"
    
    read -r -p "❓ Do you want to register $p? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo "🔧 Registering $p ..."
      az provider register --namespace "$p" >/dev/null 2>&1 && \
        echo "✅ Registered $p successfully." || \
        echo "❌ Failed to register $p. You may need additional permissions."
    else
      echo "⏭ Skipping registration for $p."
    fi
    
    echo "🧾 Check status later with: az provider show --namespace $p --query registrationState -o tsv"
    echo ""
  else
    echo "✅ $p → Already Registered"
  fi
done
