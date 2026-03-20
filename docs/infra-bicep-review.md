# Infrastructure Bicep Review

**Date:** 2026-03-20  
**Scope:** `infra/main.bicep`, `infra/main.bicepparam`, `infra/modules/*.bicep`  
**Reviewer:** GitHub Copilot

---

## Executive Summary

The Bicep templates deploy five Azure resources: Azure AI Search, Azure OpenAI (Cognitive Services), Azure Storage, an Azure AI Foundry Hub + Project, and an Azure Static Web App. The review identified **2 critical deployment-blocking bugs**, **9 outdated API versions**, **5 security issues**, and **5 design/logical issues**. A confirmed deployment failure recorded in `infra/jk.json` is consistent with the critical bug in `staticwebapp.bicep`.

---

## Severity Legend

| Severity | Description |
|---|---|
| 🔴 **Critical** | Will block deployment or cause runtime failures |
| 🟠 **High** | Security risk or significant misconfiguration |
| 🟡 **Medium** | Outdated API version — may miss new features or become unsupported |
| 🔵 **Low** | Design or maintainability issue |

---

## 🔴 Critical Issues

### 1. `foundry.bicep` — Connection `target` is a resource ID, not an endpoint URL

**Files:** `infra/modules/foundry.bicep` (lines ~50–80)

Azure AI Foundry workspace connections require the `target` property to be the **service endpoint URL**, not the ARM resource ID. Both connections are wrong:

```bicep
// ❌ WRONG — resource ID passed as target
resource openAIConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-04-01' = {
  properties: {
    category: 'AzureOpenAI'
    target: openAIResourceId        // ARM resource ID (e.g. /subscriptions/.../accounts/myopenai)
    ...
  }
}

resource searchConnection '...' = {
  properties: {
    category: 'CognitiveSearch'
    target: searchResourceId        // ARM resource ID (e.g. /subscriptions/.../searchServices/mysearch)
    ...
  }
}
```

**Fix:** Pass endpoint URLs instead of resource IDs. Update `foundry.bicep` parameters and the `main.bicep` module call:

```bicep
// ✅ CORRECT
target: 'https://<openai-name>.openai.azure.com/'   // OpenAI endpoint
target: 'https://<search-name>.search.windows.net'  // Search endpoint
```

In `main.bicep`, pass `openai.outputs.openAIEndpoint` and `search.outputs.searchEndpoint` to the foundry module rather than `openai.outputs.openAIId` and `search.outputs.searchServiceId`.

---

### 2. `foundry.bicep` — `aiProject.properties.workspaceId` may not resolve

**File:** `infra/modules/foundry.bicep` (output line)

```bicep
// ❌ Potentially invalid property reference
output projectEndpoint string = 'https://${aiProject.properties.workspaceId}.${location}.api.azureml.ms'
```

The `workspaceId` property is a GUID populated asynchronously after provisioning and is not reliably accessible as a compile-time Bicep output. If the property is absent or null, the endpoint string will be malformed (e.g., `https://.eastus.api.azureml.ms`).

**Fix:** Construct the endpoint using the resource name or use the `discoveryUrl` property:

```bicep
// ✅ Option A — use resource name (deterministic)
output projectEndpoint string = 'https://${aiProject.name}.${location}.api.azureml.ms'

// ✅ Option B — reference the discoveryUrl property if on API version 2024-10-01+
output projectEndpoint string = aiProject.properties.discoveryUrl
```

---

### 3. `infra/jk.json` — Confirmed deployment failure (Static Web App)

This file is a recorded ARM deployment failure response that was accidentally committed to the repository. It confirms a real failed deployment and exposes sensitive environment information (see Security Issues §2).

The failure message:
```
"Message": "SkuCode 'Free' is invalid."
```

This occurred against `Microsoft.Web/staticSites` using API version `2023-01-01`. The `Free` tier SKU name is valid in the spec, but this error has been observed when the `tier` prop in the SKU object does not match the expected casing or value for that API version + region combination. Updating to API version `2024-04-01` resolves this class of error.

**Immediate action:** Delete `infra/jk.json` and add `*.json` failure logs to `.gitignore` (see Security Issues §2).

---

## 🟠 High — Security Issues

### 1. Sensitive outputs expose secrets in deployment history

ARM deployment outputs are stored **in plain text in Azure deployment history** and are visible to anyone with `Microsoft.Resources/deployments/read` permission on the resource group. The following outputs should be removed from all modules and `main.bicep`:

| File | Output | Secret Exposed |
|---|---|---|
| `openai.bicep` | `openAIKey` | Azure OpenAI API key |
| `search.bicep` | `searchAdminKey` | Azure AI Search admin key |
| `storage.bicep` | `storageAccountKey` | Storage account key |
| `storage.bicep` | `storageConnectionString` | Full connection string with key embedded |
| `main.bicep` | `openAIKey`, `searchAdminKey`, `storageConnectionString` | All of the above, re-exported |

**Recommended fix:** Remove key outputs entirely and read secrets at configuration time using Key Vault references, the Azure portal, or `az` CLI post-deployment commands. If a deployment script needs the keys, use `@secure()` outputs and access them through `az deployment group show --query properties.outputs` with appropriate RBAC, rather than storing them as plain outputs.

---

### 2. `infra/jk.json` exposes subscription ID and resource group name

The committed failure log contains:
- Subscription ID: `84ea2871-4923-4a42-96a7-5b44d005cad6`
- Resource group: `rg-azure-cmh`

**Actions required:**
1. Delete `infra/jk.json` immediately.
2. Add to `.gitignore`:
   ```
   infra/*.json
   !infra/main.bicepparam
   ```
3. If this file was ever pushed to a public branch, rotate any credentials associated with this subscription/resource group.

---

## 🟡 Medium — Outdated API Versions

All resource types in the templates use API versions that are at minimum one major stable release behind as of March 2026. Outdated versions may lack support for newer SKUs, properties, and security features, and Microsoft deprecates old API versions on a rolling basis.

| File | Resource Type | Current Version | Recommended Stable |
|---|---|---|---|
| `openai.bicep` | `Microsoft.CognitiveServices/accounts` | `2023-05-01` | `2024-10-01` |
| `openai.bicep` | `Microsoft.CognitiveServices/accounts/deployments` | `2023-05-01` | `2024-10-01` |
| `foundry.bicep` | `Microsoft.MachineLearningServices/workspaces` | `2024-04-01` | `2024-10-01` |
| `foundry.bicep` | `Microsoft.MachineLearningServices/workspaces/connections` | `2024-04-01` | `2024-10-01` |
| `search.bicep` | `Microsoft.Search/searchServices` | `2023-11-01` | `2024-07-01` |
| `staticwebapp.bicep` | `Microsoft.Web/staticSites` | `2023-01-01` | `2024-04-01` |
| `storage.bicep` | `Microsoft.Storage/storageAccounts` | `2023-01-01` | `2024-01-01` |
| `storage.bicep` | `Microsoft.Storage/storageAccounts/blobServices` | `2023-01-01` | `2024-01-01` |
| `storage.bicep` | `Microsoft.Storage/storageAccounts/blobServices/containers` | `2023-01-01` | `2024-01-01` |

**Notes on specific upgrades:**

- **`Microsoft.CognitiveServices/accounts@2024-10-01`** — Adds `disableLocalAuth` property to enforce Entra ID-only access (aligns with managed-identity auth method already referenced in `main.bicep` outputs).
- **`Microsoft.MachineLearningServices/workspaces@2024-10-01`** — Exposes `discoveryUrl` on the project resource, which fixes critical issue §2 above, and adds support for `serverlessComputeSettings`.
- **`Microsoft.Search/searchServices@2024-07-01`** — Adds `disableLocalAuth` for Entra-only auth, and `encryptionWithCmk` for customer-managed keys.
- **`Microsoft.Web/staticSites@2024-04-01`** — Resolves the `SkuCode 'Free' is invalid` error seen in `jk.json` and adds `databaseConnections` support.
- **`Microsoft.Storage/storageAccounts@2024-01-01`** — Adds `allowCrossTenantReplication: false` (security hardening) and DNS endpoint type options.

---

## 🔵 Low — Design / Logic Issues

### 1. `deploySampleData` parameter is declared but never used

**File:** `infra/main.bicep`

```bicep
@description('Deploy sample data (hotels index and Responsible AI PDF)')
param deploySampleData bool = true  // declared here...
```

This parameter is passed in `main.bicepparam` (`deploySampleData = true`) but is never forwarded to any module. No conditional logic or module call references it.

**Fix:** Either wire it into a deployment script module/conditional block, or remove the parameter from both `main.bicep` and `main.bicepparam` to avoid confusion.

---

### 2. `gpt-4.1-mini` should use `GlobalStandard` SKU

**File:** `infra/main.bicep`

```bicep
'gpt-4.1-mini': {
  version: '2025-04-14'
  capacity: 30
  skuName: 'Standard'   // ← should be GlobalStandard for this model
}
```

GPT-4.1-mini is a global model. Using `Standard` routing limits it to a single Azure region's capacity and may result in lower quota ceilings. The sibling entry for `gpt-4.1-nano` correctly uses `GlobalStandard`.

**Fix:**
```bicep
'gpt-4.1-mini': {
  version: '2025-04-14'
  capacity: 30
  skuName: 'GlobalStandard'
}
```

---

### 3. `foundry.bicep` Hub missing `keyVault` reference

**File:** `infra/modules/foundry.bicep`

Azure AI Foundry Hubs typically require or strongly benefit from an associated Key Vault for secret management (connection strings, API keys). The Hub definition only specifies `storageAccount`:

```bicep
properties: {
  storageAccount: storageAccountId
  // keyVault: ???  ← missing
}
```

Without a Key Vault, the Hub cannot store workspace secrets and some connection auth types may be unavailable.

**Fix:** Add a `keyVault` parameter and pass a Key Vault resource ID, or add a Key Vault module to the template. At minimum, add a note in the parameter description that this is intentionally omitted.

---

### 4. `staticwebapp.bicep` — provider hardcoded to `'GitHub'` with optional token

**File:** `infra/modules/staticwebapp.bicep`

```bicep
properties: {
  provider: 'GitHub'            // hardcoded
  repositoryToken: repositoryToken  // but this can be empty string
}
```

If `repositoryToken` is empty (the default in `main.bicep`), the GitHub provider config is incomplete and Azure may reject the deployment or create the site without any CI/CD connection. The template should either:
- Conditionally omit provider/token properties when `repositoryToken` is empty, or  
- Default `provider` to `'None'` when no token is provided.

```bicep
// ✅ Safer approach
provider: empty(repositoryToken) ? 'None' : 'GitHub'
```

---

### 5. `main.bicep` capacity for `gpt-4o` may be too low for prod

**File:** `infra/main.bicep`

All chat models are capped at `capacity: 30` (30K TPM) regardless of environment. For `prod`, GPT-4o at 30K TPM is very constrained. Consider making capacity environment-dependent:

```bicep
// Example: scale capacity by environment
capacity: environment == 'prod' ? 100 : 30
```

---

## File-by-File Summary

| File | Issues |
|---|---|
| `main.bicep` | Unused `deploySampleData` param; `gpt-4.1-mini` SKU; sensitive key outputs; capacity not env-scaled |
| `main.bicepparam` | References unused `deploySampleData` |
| `foundry.bicep` | 🔴 Wrong connection `target` type; 🔴 invalid `workspaceId` endpoint; outdated API `2024-04-01`; missing keyVault |
| `openai.bicep` | Outdated API `2023-05-01`; sensitive key output |
| `search.bicep` | Outdated API `2023-11-01`; sensitive admin key output |
| `staticwebapp.bicep` | Outdated API `2023-01-01`; hardcoded `provider: 'GitHub'` + empty token issue |
| `storage.bicep` | Outdated API `2023-01-01`; sensitive key/connection string outputs |
| `jk.json` | 🟠 Should not be committed; exposes subscription ID + resource group; delete immediately |

---

## Recommended Action Order

1. **Delete `infra/jk.json`** and update `.gitignore` (security + cleanup)
2. **Fix `foundry.bicep` connection targets** — pass endpoint URLs instead of resource IDs (deployment-blocking)
3. **Fix `foundry.bicep` projectEndpoint output** — remove `workspaceId` reference (deployment-blocking)
4. **Remove sensitive key outputs** from all modules and `main.bicep`
5. **Update all API versions** to the recommended stable versions in the table above
6. **Fix `gpt-4.1-mini` SKU** to `GlobalStandard`
7. **Fix `staticwebapp.bicep` provider** conditional
8. **Remove or wire `deploySampleData`** parameter
9. **Add `keyVault`** reference to Foundry Hub (optional but recommended)
10. **Scale capacity** for prod deployments
