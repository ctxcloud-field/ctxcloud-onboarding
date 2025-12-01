<#
.SYNOPSIS
Checks if the current Azure CLI user has the necessary permissions for Cortex Cloud Runtime Security.

.DESCRIPTION
Performs validation across:
- Role assignments at Tenant Root Management Group and Subscription level
- Wildcard permissions for key service APIs
- Global Administrator role in Entra ID (if supported)

Author: Your Friendly PowerShell Platform Engineer
#>

function Test-CortexRuntimePermissions {
    [CmdletBinding()]
    param ()

    # ─────────────────────────────────────────────────────────────
    # 🔧 Constants & Setup
    # ─────────────────────────────────────────────────────────────
    $EmojiCheck = "✅"
    $EmojiCross = "❌"
    $EmojiSearch = "🔍"
    $EmojiWarn = "⚠️"
    $EmojiLock = "🔒"
    $EmojiKey = "🔑"

    Write-Host "$EmojiSearch Gathering Azure account and user details..." -ForegroundColor Cyan

    try {
        $user = az ad signed-in-user show | ConvertFrom-Json
        $account = az account show | ConvertFrom-Json
    }
    catch {
        Write-Error "$EmojiCross Failed to retrieve Azure CLI context. Ensure you're logged in via 'az login'."
        return
    }

    $userId = $user.id
    $userUPN = $user.userPrincipalName
    $subId = $account.id
    $tenantId = $account.tenantId

    Write-Host "`n🧾 Azure Context"
    Write-Host "👤 UPN:          $userUPN"
    Write-Host "🆔 Object ID:    $userId"
    Write-Host "🏢 Tenant ID:    $tenantId"
    Write-Host "🧾 Subscription: $subId"

    # ─────────────────────────────────────────────────────────────
    # 🔐 Check for Global Admin Role
    # ─────────────────────────────────────────────────────────────
    Write-Host "`n$EmojiSearch Checking Entra Global Administrator role..." -ForegroundColor Cyan

    $azRestAvailable = $false
    try {
        az rest --help > $null 2>&1
        $azRestAvailable = $true
    } catch {
        Write-Warning "$EmojiWarn 'az rest' is not available — skipping Global Admin check."
    }

    if ($azRestAvailable) {
        try {
            $roleId = az rest --method GET --url "https://graph.microsoft.com/v1.0/directoryRoles" `
                --query "value[?displayName=='Global Administrator'].id" -o tsv

            if (-not $roleId) {
                Write-Warning "$EmojiWarn Global Administrator role not found (may be inactive or hidden)."
            }
            else {
                $members = az rest --method GET `
                    --url "https://graph.microsoft.com/v1.0/directoryRoles/$roleId/members" `
                    --query "value[].id" -o tsv

                if ($members -contains $userId) {
                    Write-Host "$EmojiCheck You ARE a Global Administrator in Entra ID." -ForegroundColor Green
                }
                else {
                    Write-Host "$EmojiCross You are NOT a Global Administrator in Entra ID." -ForegroundColor Red
                }
            }
        }
        catch {
            Write-Warning "$EmojiWarn Failed to validate Global Admin status: $_"
        }
    }

    # ─────────────────────────────────────────────────────────────
    # 🔎 Role Assignments at Scope
    # ─────────────────────────────────────────────────────────────
    Write-Host "`n📍 Gathering roles at Root MG and Subscription level..." -ForegroundColor Cyan

    try {
        $rootMG = az account management-group list --query "[?properties.parent==null].name | [0]" -o tsv
        $rootScope = "/providers/Microsoft.Management/managementGroups/$rootMG"
        $subScope = "/subscriptions/$subId"

        $rootRoles = az role assignment list --assignee $userId --scope $rootScope --query "[].roleDefinitionName" -o tsv 2>$null
        $subRoles = az role assignment list --assignee $userId --scope $subScope --query "[].roleDefinitionName" -o tsv 2>$null

        $combinedRoles = ($rootRoles + $subRoles) | Sort-Object -Unique
    }
    catch {
        Write-Error "$EmojiCross Error while gathering role assignments: $_"
        return
    }

    if (-not $combinedRoles) {
        Write-Host "$EmojiCross No roles found for the user at root or subscription scope." -ForegroundColor Red
        return
    }

    Write-Host "`n📌 Root Management Group: $rootMG"
    $rootRoles | ForEach-Object { Write-Host "   $EmojiLock $_" }

    Write-Host "`n📌 Subscription: $subId"
    $subRoles | ForEach-Object { Write-Host "   $EmojiKey $_" }

    Write-Host "`n📜 Combined Role Definitions:"
    $combinedRoles | ForEach-Object { Write-Host " - $_" }

    # ─────────────────────────────────────────────────────────────
    # 🔍 Permission Wildcard Validation
    # ─────────────────────────────────────────────────────────────
    Write-Host "`n$EmojiSearch Checking wildcard permissions required for Cortex Cloud Runtime Security..." -ForegroundColor Cyan

    $categories = @(
        @{ Name = "Compute";             Wildcard = "Microsoft.Compute/*" },
        @{ Name = "Storage";             Wildcard = "Microsoft.Storage/*" },
        @{ Name = "Networking";          Wildcard = "Microsoft.Network/*" },
        @{ Name = "Key Vault";           Wildcard = "Microsoft.KeyVault/*" },
        @{ Name = "Container Services";  Wildcard = "Microsoft.ContainerService/*" },
        @{ Name = "Container Registry";  Wildcard = "Microsoft.ContainerRegistry/*" },
        @{ Name = "Monitoring & Logs";   Wildcard = "Microsoft.Insights/*" },
        @{ Name = "IAM / Role Assignments"; Wildcard = "Microsoft.Authorization/roleAssignments/*" },
        @{ Name = "Cosmos DB";           Wildcard = "Microsoft.DocumentDB/*" },
        @{ Name = "App Services";        Wildcard = "Microsoft.Web/*" },
        @{ Name = "Policy Insights";     Wildcard = "Microsoft.PolicyInsights/*" },
        @{ Name = "Event Hubs";          Wildcard = "Microsoft.EventHub/*" }
    )

    foreach ($cat in $categories) {
        $match = $false
        foreach ($role in $combinedRoles) {
            try {
                $actions = az role definition list --name $role --query "[].permissions[].actions[]" -o tsv 2>$null
                if ($actions -match "^$($cat.Wildcard)" -or $actions -contains "*") {
                    $match = $true
                    break
                }
            } catch {
                continue
            }
        }

        $status = if ($match) { "$EmojiCheck Yes" } else { "$EmojiCross No" }
        Write-Host ("🔐 {0,-25} → {1,-45}: {2}" -f $cat.Name, $cat.Wildcard, $status)
    }
}

Test-CortexRuntimePermissions