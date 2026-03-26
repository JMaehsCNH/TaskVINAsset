# Fail fast on errors so we see the first real issue
$ErrorActionPreference = 'Stop'

# ---------- Unified HTTP error renderer (works in PS7) ----------
function Show-HttpError {
  param($err, [string]$context = "")
  try {
    if ($context) { Write-Host "❌ $context" }

    # PS7: HttpResponseMessage
    if ($err.Exception.Response -is [System.Net.Http.HttpResponseMessage]) {
      $resp   = $err.Exception.Response
      $code   = [int]$resp.StatusCode
      $reason = $resp.ReasonPhrase
      $body   = $err.ErrorDetails.Message
      Write-Host "HTTP $code $reason"
      if ($body) { Write-Host $body } else {
        $raw = $resp.Content.ReadAsStringAsync().Result
        if ($raw) { Write-Host $raw }
      }
      return
    }

    # Windows PowerShell / WebException fallback
    if ($err.Exception.Response -and $err.Exception.Response.GetResponseStream) {
      $sr = New-Object IO.StreamReader($err.Exception.Response.GetResponseStream())
      $txt = $sr.ReadToEnd()
      Write-Host $txt
      return
    }

    # Last resort
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) {
      Write-Host $err.ErrorDetails.Message
    } else {
      Write-Host $err.Exception.Message
    }
  } catch {
    Write-Host "⚠️ Failed to render error details: $($_.Exception.Message)"
  }
}

# === CONFIGURATION ===
$jiraBaseUrl = "https://cnhpd.atlassian.net"
$jiraEmail   = "john.maehs@cnh.com"
$jiraToken   = $env:jiraToken          # GitHub secret
$projectKey  = "PREC"
$issueTypeClause = '("Customer Task", "PV Task")'

# GSS External API Keys
$subsKeyGSSProd = $env:subsKeyGSSProd
$subsKeyGSSMkt  = $env:subsKeyGSSMkt

# === HEADERS ===
$headers = @{
  Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$jiraEmail`:$jiraToken"))
  Accept        = "application/json"
  "Content-Type"= "application/json"
}
$headerExtProd = @{ 'Ocp-Apim-Subscription-Key' = $subsKeyGSSProd }
$headerExtMkt  = @{ 'Ocp-Apim-Subscription-Key' = $subsKeyGSSMkt }

Write-Host "🪪 RAVEN_S2S_CALLER: $($env:RAVEN_S2S_CALLER)"
Write-Host "🪪 RAVEN_PROD_SECRET length: $($env:RAVEN_PROD_SECRET.Length)"
Write-Host "🪪 RAVEN_DEV_SECRET length: $($env:RAVEN_DEV_SECRET.Length)"

if ([string]::IsNullOrWhiteSpace($env:RAVEN_S2S_CALLER)) {
  throw "RAVEN_S2S_CALLER is empty"
}
if ([string]::IsNullOrWhiteSpace($env:RAVEN_PROD_SECRET)) {
  throw "RAVEN_PROD_SECRET is empty"
}
if ([string]::IsNullOrWhiteSpace($env:RAVEN_DEV_SECRET)) {
  Write-Host "⚠️ RAVEN_DEV_SECRET is empty"
}

# === RAVEN CONFIG ===
$ravenBaseUrlDev = "https://connectivity.raven.engineering"
$ravenBaseUrlProd  = "https://connectivity.ravenslingshot.com"   

$ravenHeadersProd = @{
  "x-s2s-caller" = $env:RAVEN_S2S_CALLER
  "x-s2s-secret" = $env:RAVEN_PROD_SECRET
  "Accept"       = "application/json"
}

$ravenHeadersDev = @{
  "x-s2s-caller" = $env:RAVEN_S2S_CALLER
  "x-s2s-secret" = $env:RAVEN_DEV_SECRET
  "Accept"       = "application/json"
}

function Get-RavenDevice {
  param([Parameter(Mandatory=$true)][string]$DeviceId)

  $urlProd = "$ravenBaseUrlProd/v1/device/$DeviceId"
  $urlDev  = "$ravenBaseUrlDev/v1/device/$DeviceId"

  Write-Host "🌐 Raven PROD GET: $urlProd"
  try {
    Write-Host "🔐 Trying PROD headers..."
    $resp = Invoke-WebRequest -Uri $urlProd -Headers $ravenHeadersProd -Method Get -ErrorAction Stop
    Write-Host "✅ PROD succeeded"
    Write-Host "📡 PROD status: $($resp.StatusCode)"
    Write-Host "📦 PROD raw body:"
    Write-Host $resp.Content
    return ($resp.Content | ConvertFrom-Json)
  }
  catch {
    Write-Host "❌ PROD failed for device '$DeviceId'"
    if ($_.Exception.Response) {
      try { Write-Host "📡 PROD status code: $([int]$_.Exception.Response.StatusCode)" } catch {}
      try { Write-Host "📡 PROD reason: $($_.Exception.Response.ReasonPhrase)" } catch {}
    }
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
      Write-Host "📦 PROD error body:"
      Write-Host $_.ErrorDetails.Message
    } else {
      Write-Host "📝 PROD exception:"
      Write-Host $_.Exception.Message
    }
  }

  Write-Host "🌐 Raven DEV GET: $urlDev"
  try {
    Write-Host "🔐 Trying DEV headers..."
    $resp = Invoke-WebRequest -Uri $urlDev -Headers $ravenHeadersDev -Method Get -ErrorAction Stop
    Write-Host "✅ DEV succeeded"
    Write-Host "📡 DEV status: $($resp.StatusCode)"
    Write-Host "📦 DEV raw body:"
    Write-Host $resp.Content
    return ($resp.Content | ConvertFrom-Json)
  }
  catch {
    Write-Host "❌ DEV failed for device '$DeviceId'"
    if ($_.Exception.Response) {
      try { Write-Host "📡 DEV status code: $([int]$_.Exception.Response.StatusCode)" } catch {}
      try { Write-Host "📡 DEV reason: $($_.Exception.Response.ReasonPhrase)" } catch {}
    }
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
      Write-Host "📦 DEV error body:"
      Write-Host $_.ErrorDetails.Message
    } else {
      Write-Host "📝 DEV exception:"
      Write-Host $_.Exception.Message
    }
    return $null
  }
}

function Get-RavenSystem {
  param([Parameter(Mandatory=$true)][string]$SystemId)

  $urlProd = "$ravenBaseUrlProd/v1/system/$SystemId"
  $urlDev  = "$ravenBaseUrlDev/v1/system/$SystemId"

  Write-Host "🌐 Raven PROD SYSTEM GET: $urlProd"
  try {
    Write-Host "🔐 Trying PROD headers for system..."
    $resp = Invoke-WebRequest -Uri $urlProd -Headers $ravenHeadersProd -Method Get -ErrorAction Stop
    Write-Host "✅ PROD system succeeded"
    Write-Host "📡 PROD system status: $($resp.StatusCode)"
    Write-Host "📦 PROD system raw body:"
    Write-Host $resp.Content
    return ($resp.Content | ConvertFrom-Json)
  }
  catch {
    Write-Host "❌ PROD system failed for '$SystemId'"
    if ($_.Exception.Response) {
      try { Write-Host "📡 PROD system status code: $([int]$_.Exception.Response.StatusCode)" } catch {}
      try { Write-Host "📡 PROD system reason: $($_.Exception.Response.ReasonPhrase)" } catch {}
    }
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
      Write-Host "📦 PROD system error body:"
      Write-Host $_.ErrorDetails.Message
    } else {
      Write-Host "📝 PROD system exception:"
      Write-Host $_.Exception.Message
    }
  }

  Write-Host "🌐 Raven DEV SYSTEM GET: $urlDev"
  try {
    Write-Host "🔐 Trying DEV headers for system..."
    $resp = Invoke-WebRequest -Uri $urlDev -Headers $ravenHeadersDev -Method Get -ErrorAction Stop
    Write-Host "✅ DEV system succeeded"
    Write-Host "📡 DEV system status: $($resp.StatusCode)"
    Write-Host "📦 DEV system raw body:"
    Write-Host $resp.Content
    return ($resp.Content | ConvertFrom-Json)
  }
  catch {
    Write-Host "❌ DEV system failed for '$SystemId'"
    if ($_.Exception.Response) {
      try { Write-Host "📡 DEV system status code: $([int]$_.Exception.Response.StatusCode)" } catch {}
      try { Write-Host "📡 DEV system reason: $($_.Exception.Response.ReasonPhrase)" } catch {}
    }
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
      Write-Host "📦 DEV system error body:"
      Write-Host $_.ErrorDetails.Message
    } else {
      Write-Host "📝 DEV system exception:"
      Write-Host $_.Exception.Message
    }
    return $null
  }
}


function Get-RavenEnrichment {
  param(
    [Parameter(Mandatory=$false)][string]$RootDeviceId
  )

  $out = [ordered]@{
    RavenRootSoftwareVersion = $null
    AntalyaBarcode           = $null
    AntalyaSw                = $null
    PegasusBarcode           = $null
    PegasusSw                = $null
  }

  if ([string]::IsNullOrWhiteSpace($RootDeviceId)) {
    Write-Host "⚠️ Get-RavenEnrichment: RootDeviceId is blank."
    return [pscustomobject]$out
  }

  function Get-PropString {
    param($obj, [string[]]$Names)
    foreach ($n in $Names) {
      if ($obj -and $obj.PSObject.Properties.Name -contains $n) {
        $v = $obj.$n
        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) {
          return [string]$v
        }
      }
    }
    return $null
  }

  function Resolve-RavenDeviceWithSystem {
    param([string]$AnyId)

    if ([string]::IsNullOrWhiteSpace($AnyId)) { return $null }

    Write-Host "🔎 Raven root lookup: deviceId='$AnyId'"
    $dev = Get-RavenDevice -DeviceId $AnyId
    if (-not $dev) {
      Write-Host "⚠️ Raven device not found for '$AnyId'"
      return $null
    }

    Write-Host "🧾 Raven root raw:"
    Write-Host ($dev | ConvertTo-Json -Depth 20)

    $systemId = Get-PropString $dev @("systemId","systemID")
    if (-not [string]::IsNullOrWhiteSpace($systemId)) {
      return $dev
    }

    # Retry with alternate ids from the device response
    $retryIds = @(
      (Get-PropString $dev @("externalDeviceId")),
      (Get-PropString $dev @("sid")),
      (Get-PropString $dev @("rowId")),
      (Get-PropString $dev @("barcode"))
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($rid in $retryIds) {
      Write-Host "🔁 Raven retry lookup using alternate id '$rid'"
      $retryDev = Get-RavenDevice -DeviceId $rid
      if (-not $retryDev) { continue }

      Write-Host "🧾 Raven retry raw:"
      Write-Host ($retryDev | ConvertTo-Json -Depth 20)

      $retrySystemId = Get-PropString $retryDev @("systemId","systemID")
      if (-not [string]::IsNullOrWhiteSpace($retrySystemId)) {
        Write-Host "✅ Found systemId '$retrySystemId' using alternate id '$rid'"
        return $retryDev
      }
    }

    return $dev
  }

  $rootDev = Resolve-RavenDeviceWithSystem -AnyId $RootDeviceId
  if (-not $rootDev) {
    return [pscustomobject]$out
  }

  $out.RavenRootSoftwareVersion = Get-PropString $rootDev @("softwareVersion","version")
  $rootModel = Get-PropString $rootDev @("model")
  $systemId  = Get-PropString $rootDev @("systemId","systemID")

  Write-Host "🧠 Root model: '$rootModel'"
  Write-Host "🧠 Root systemId: '$systemId'"

  # If still blank, try rowId directly as a system id experiment
  if ([string]::IsNullOrWhiteSpace($systemId)) {
    $rowId = Get-PropString $rootDev @("rowId")
    if (-not [string]::IsNullOrWhiteSpace($rowId)) {
      Write-Host "🧪 systemId still blank; trying rowId '$rowId' as system lookup"
      $sys = Get-RavenSystem -SystemId $rowId
      if ($sys) {
        Write-Host "✅ Raven system lookup returned data using rowId '$rowId'"
      } else {
        Write-Host "⚠️ Raven system lookup failed using rowId '$rowId'"
      }
    } else {
      $sys = $null
    }
  } else {
    $sys = Get-RavenSystem -SystemId $systemId
  }

  if (-not $sys) {
    Write-Host "⚠️ No Raven system data available."
    return [pscustomobject]$out
  }

  Write-Host "🧾 Raven system raw:"
  Write-Host ($sys | ConvertTo-Json -Depth 20)

  $deviceIds = @()

  if ($sys.PSObject.Properties.Name -contains "devices" -and $sys.devices) {
    foreach ($d in $sys.devices) {
      if ($d -is [string]) {
        if (-not [string]::IsNullOrWhiteSpace($d)) {
          $deviceIds += [string]$d
        }
      }
      else {
        foreach ($propName in @("deviceId","id","externalId","externalDeviceId","sid","rowId","barcode")) {
          if ($d.PSObject.Properties.Name -contains $propName -and -not [string]::IsNullOrWhiteSpace([string]$d.$propName)) {
            $deviceIds += [string]$d.$propName
            break
          }
        }
      }
    }
  }

  $deviceIds = @($deviceIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  Write-Host "📦 Raven system child device ids found: $($deviceIds.Count)"

foreach ($sid in $deviceIds) {
  Write-Host "🔍 Raven child lookup: '$sid'"
  $dev = Get-RavenDevice -DeviceId $sid
  if (-not $dev) { continue }

  Write-Host "🧾 Raven child raw:"
  Write-Host ($dev | ConvertTo-Json -Depth 20)

  $model = [string]$dev.model
  $type  = [string]$dev.type
  $sw    = [string]$dev.softwareVersion

  $barcodeCandidate = $null
  if ($null -ne $dev.barcode -and -not [string]::IsNullOrWhiteSpace([string]$dev.barcode)) {
    $barcodeCandidate = [string]$dev.barcode
  } elseif (-not [string]::IsNullOrWhiteSpace([string]$dev.externalDeviceId)) {
    $barcodeCandidate = [string]$dev.externalDeviceId
  } elseif (-not [string]::IsNullOrWhiteSpace([string]$dev.cnhHardwareId)) {
    $barcodeCandidate = [string]$dev.cnhHardwareId
  } elseif (-not [string]::IsNullOrWhiteSpace([string]$dev.serialNumber)) {
    $barcodeCandidate = [string]$dev.serialNumber
  }

  Write-Host "   model='$model'"
  Write-Host "   type='$type'"
  Write-Host "   barcodeCandidate='$barcodeCandidate'"
  Write-Host "   versionCandidate='$sw'"

  if (-not $out.AntalyaSw -and ($type -match '^antalya$' -or $model -match 'ANTALYA|CNH03244')) {
    $out.AntalyaBarcode = $barcodeCandidate
    $out.AntalyaSw      = $sw
    Write-Host "✅ Matched ANTALYA"
    continue
  }

  if (-not $out.PegasusSw -and ($model -match 'PEGASUS|CNH03201' -or $type -match 'pegasus|fieldcomputer')) {
    $out.PegasusBarcode = $barcodeCandidate
    $out.PegasusSw      = $sw
    Write-Host "✅ Matched PEGASUS"
    continue
  }
}


Write-Host "🧠 Post-loop Raven enrichment object:"
Write-Host (([pscustomobject]$out) | ConvertTo-Json -Depth 10)

return [pscustomobject]$out

# --- Quick secret sanity ---
Write-Host "🔐 Email: $jiraEmail"
if ([string]::IsNullOrWhiteSpace($jiraToken)) {
  Write-Host "❌ jiraToken is empty! Check your GitHub Action secrets/env."
  exit 1
} else {
  Write-Host "🔐 jiraToken length: $($jiraToken.Length)"
}

# === QUERY JIRA ISSUES (new /search/jql with nextPageToken) ===
$jql = 'project = PREC AND issuetype in ("Customer Task", "PV Task") AND statusCategory != Done'
$searchUrl = "$jiraBaseUrl/rest/api/3/search/jql"

$body = @{
  jql        = $jql
  maxResults = 100
  fields     = @(
    "customfield_13087", # VIN
    "customfield_13088", # CEQ
    "customfield_13089", # Company
    "customfield_13094"  # TDAC
  )
}

Write-Host "🔎 JQL: $jql"
Write-Host "🌐 Site: $jiraBaseUrl"
Write-Host "🔗 Search URL: $searchUrl"
Write-Host "👤 User: $jiraEmail"

$allIssues = @()
$nextPageToken = $null
$searchPage = 0

do {
  $searchPage++
  $payload = $body.Clone()
  if ($nextPageToken) { $payload["nextPageToken"] = $nextPageToken }

  $json = $payload | ConvertTo-Json -Depth 5
  Write-Host "`n📄 Search page $searchPage (nextPageToken=$nextPageToken)"

  try {
    $resp = Invoke-RestMethod -Uri $searchUrl -Method Post -Headers $headers -Body $json
  } catch {
    Show-HttpError $_ "Search failed."
    throw
  }

  $count = @($resp.issues).Count
  Write-Host "➡️ Retrieved $count issues in this page."
  if ($resp.issues) { $allIssues += $resp.issues }

  if ($resp.isLast -eq $true) {
    $nextPageToken = $null
  } else {
    $nextPageToken = $resp.nextPageToken
  }
} while ($nextPageToken)

Write-Host "`n📊 Total issues fetched: $($allIssues.Count)"
if ($allIssues.Count -eq 0) {
  Write-Host "ℹ️ No issues matched your JQL. Running discovery probes..."

  # 0) Verify who we are (token ↔ account)
  try {
    $me = Invoke-RestMethod -Uri "$jiraBaseUrl/rest/api/3/myself" -Headers $headers -Method Get
    Write-Host ("👤 Auth OK as: {0} ({1})" -f $me.displayName, $me.emailAddress)
  } catch {
    Show-HttpError $_ "/myself failed; token/email mismatch or wrong site."
    throw
  }

  # 1) Browse permission on the project
  try {
    $permProj = Invoke-RestMethod `
      -Uri "$jiraBaseUrl/rest/api/3/mypermissions?projectKey=$projectKey&permissions=BROWSE_PROJECTS" `
      -Headers $headers -Method Get
    $canBrowse = $permProj.permissions.BROWSE_PROJECTS.havePermission
    Write-Host ("🔑 Browse Projects on {0}: {1}", $projectKey, $canBrowse)
  } catch {
    Show-HttpError $_ "Could not query mypermissions"
  }

  # 2) Try a known key to prove visibility & get the exact issuetype name
  $knownIssueKey = "PREC-382"   # <-- update to a real key you see in the UI
  $actualType = $null
  try {
    $one = Invoke-RestMethod -Uri "$jiraBaseUrl/rest/api/3/issue/$knownIssueKey?fields=issuetype,project" -Headers $headers -Method Get
    $actualProject = $one.fields.project.key
    $actualType    = $one.fields.issuetype.name
    Write-Host "🔎 Known issue $knownIssueKey -> project=$actualProject  issuetype='$actualType'"
  } catch {
    Show-HttpError $_ "GET /issue/$knownIssueKey failed (no Browse permission or wrong site/project)."
  }

  # 3) List a few recent issues from PREC to confirm API visibility
  try {
    $sampleBody = @{
      jql        = "project = $projectKey ORDER BY created DESC"
      maxResults = 10
      fields     = @("key","issuetype","summary","status")
    } | ConvertTo-Json -Depth 5

    $sample = Invoke-RestMethod -Uri "$jiraBaseUrl/rest/api/3/search/jql" -Method Post -Headers $headers -Body $sampleBody
    Write-Host ("📋 Recent in {0}: {1}", $projectKey, (@($sample.issues).Count))
    foreach ($it in $sample.issues) {
      Write-Host ("  • {0}  [{1}]  {2}", $it.key, $it.fields.issuetype.name, $it.fields.summary)
    }
  } catch {
    Show-HttpError $_ "Sample fetch failed"
  }

  # 4) If we got a real issuetype name from the known key, probe with that
  if ($actualType) {
    $probeBody = @{
      jql        = "project = $projectKey AND issuetype = '$actualType'"
      maxResults = 1
      fields     = @("key")
    } | ConvertTo-Json -Depth 4

    $probe = Invoke-RestMethod -Uri "$jiraBaseUrl/rest/api/3/search/jql" -Method Post -Headers $headers -Body $probeBody
    $probeTotal = [int]$probe.total
    Write-Host ("🐞 Probe count for exact issuetype '{0}': {1}", $actualType, $probeTotal)

    if ($probeTotal -gt 0) {
      # Retry main search using the issuetype string Jira actually stores on your site
      $retryBody = @{
        jql        = "project = $projectKey AND issuetype = '$actualType'"
        maxResults = 100
        fields     = @("customfield_13087","customfield_13089")
      } | ConvertTo-Json -Depth 5

      $retry = Invoke-RestMethod -Uri "$jiraBaseUrl/rest/api/3/search/jql" -Method Post -Headers $headers -Body $retryBody
      $script:allIssues = $retry.issues
      Write-Host ("↩️  Retry found {0} issues. Continuing with update loop.", (@($allIssues).Count))
    }
  }

  # If we still have nothing, stop here with a clear message
  if (-not $allIssues -or $allIssues.Count -eq 0) {
    Write-Host "🛑 Still zero via API. Likely causes:"
    Write-Host "  • The API user/token cannot *Browse* the project or is a different account than the one in the UI."
    Write-Host "  • Issue Security Level hides Task from this account."
    Write-Host "  • Different site or project key."
    exit 0
  }
}

# === PROCESS ISSUES ===
foreach ($issue in $allIssues) {
  $issueId  = $issue.id
  $issueKey = $issue.key
  $vin      = $issue.fields.customfield_13087

  # ✅ SKIP GOES HERE
  $hasTdac    = -not [string]::IsNullOrWhiteSpace([string]$issue.fields.customfield_13094)
  $hasCeqId   = -not [string]::IsNullOrWhiteSpace([string]$issue.fields.customfield_13088)
  $hasCompany = -not [string]::IsNullOrWhiteSpace([string]$issue.fields.customfield_13089)

  if ($hasTdac -and $hasCeqId -and $hasCompany) {
    Write-Host "⏭️  Skipping $issueKey (already has TDAC + CEQ + Company)."
    continue
  }

  Write-Host "`n🔍 Processing: $issueKey (ID: $issueId)  VIN: $vin"
  # --- B) Check my permission to edit this issue ---
  $permBase = "$jiraBaseUrl/rest/api/3/mypermissions?permissions=BROWSE_PROJECTS,EDIT_ISSUES"
  $permUrl  = "$permBase&issueId=$issueId"
  try {
    $perm = Invoke-RestMethod -Uri $permUrl -Method Get -Headers $headers
  } catch {
    Show-HttpError $_ "mypermissions by issueId failed, retrying with issueKey"
    try {
      $perm = Invoke-RestMethod -Uri "$permBase&issueKey=$issueKey" -Method Get -Headers $headers
    } catch {
      Show-HttpError $_ "Failed to check permissions for $issueKey"
      # If you prefer to continue without the check, comment the next line:
      continue
    }
  }
  
  $canBrowse = $perm.permissions.BROWSE_PROJECTS.havePermission
  $canEdit   = $perm.permissions.EDIT_ISSUES.havePermission
  Write-Host "🔑 Edit permission: $canEdit"
  if (-not $canEdit) {
    Write-Host "❌ No 'Edit Issues' permission on $issueKey. Skipping."
    continue
  }

  # --- C1) Map names ↔ IDs to confirm customfield IDs are right ---
  try {
    $withNames = Invoke-RestMethod -Uri "$jiraBaseUrl/rest/api/3/issue/$issueId?expand=names" -Headers $headers -Method Get
    Write-Host "🧭 Field name map:"
    Write-Host "    customfield_13087 => $($withNames.names.customfield_13087)"
    Write-Host "    customfield_13089 => $($withNames.names.customfield_13089)"
    Write-Host "    customfield_13088 => $($withNames.names.customfield_13088)"
    Write-Host "    customfield_13094 => $($withNames.names.customfield_13094)"
    Write-Host "    customfield_13318 => $($withNames.names.customfield_13318)"
    Write-Host "    customfield_13097 => $($withNames.names.customfield_13097)"
    Write-Host "    customfield_13098 => $($withNames.names.customfield_13098)"
  } catch {
    Write-Host "⚠️ Could not fetch names map; continuing."
  }

# --- C2) Check which fields are editable on this issue ---
$editMeta = $null
try {
  $editMeta = Invoke-RestMethod -Uri "$jiraBaseUrl/rest/api/3/issue/$issueId/editmeta" -Headers $headers -Method Get
  $editable = $editMeta.fields.PSObject.Properties.Name
  $editableSample = ($editable | Select-Object -First 20) -join ", "
  Write-Host "🛠️  Editable fields (sample): $editableSample"
} catch {
  Write-Host "⚠️ Could not fetch editmeta for $issueKey; continuing without editability check."
}


  # --- External API calls (your existing logic) ---
  $urlProd = "https://euevoapi010.azure-api.net/gssp/core/v1/assets/$($vin)?domain=AG&assetIdType=VIN&metrics=ENG_HOURS&showPosition=True&showBundleVersion=True&showSource=true"
  $urlMkt  = "https://euevoapipv010.azure-api.net/gsss/core/v1/assets/$($vin)?domain=AG&assetIdType=VIN&metrics=ENG_HOURS&showPosition=True&showBundleVersion=True&showSource=true"

  try { $dataProd = Invoke-RestMethod -Uri $urlProd -Headers $headerExtProd -Method Get } catch { $dataProd = $null }
  try { $dataMkt  = Invoke-RestMethod -Uri $urlMkt  -Headers $headerExtMkt  -Method Get } catch { $dataMkt  = $null }

  if (-not $dataProd -and -not $dataMkt) {
    Write-Host "❌ No data from either API for VIN $vin"
    continue
  }

  if     ($dataProd -and -not $dataMkt) { $chosen = $dataProd; $envType = "PROD" }
  elseif ($dataMkt  -and -not $dataProd){ $chosen = $dataMkt;  $envType = "NON-PROD" }
  else {
    $chosen = if ($dataProd.time -ge $dataMkt.time) { $dataProd } else { $dataMkt }
    $envType = if ($chosen -eq $dataProd) { "PROD" } else { "NON-PROD" }
  }
  try { $ravenRootId = [string]$chosen.devices.tdac } catch {}
  
  Write-Host ("🧪 Raven root id from GSS (devices.tdac): '{0}'" -f (($ravenRootId | Out-String).Trim()))
  # Defensive logs in case shapes vary
  Write-Host "🌎 Source chosen: $envType"
  Write-Host ("→ Latitude: {0}"  -f ($chosen.pos.lat   | Out-String).Trim())
  Write-Host ("→ Longitude: {0}" -f ($chosen.pos.lon   | Out-String).Trim())
  Write-Host ("→ Engine Hours: {0}" -f ($chosen.metrics.value.value | Out-String).Trim())
  Write-Host ("→ Archived: {0}"     -f ($chosen.archived | Out-String).Trim())
  Write-Host ("→ ceqId: {0}"        -f ($chosen.ceqId    | Out-String).Trim())
  Write-Host ("→ companyName: {0}"  -f ($chosen.companyName | Out-String).Trim())
  if ($chosen.devices) {
    Write-Host ("→ devices.tdac: {0}"                 -f ($chosen.devices.tdac | Out-String).Trim())
    Write-Host ("→ devices.deviceBundleVersion: {0}"  -f ($chosen.devices.deviceBundleVersion | Out-String).Trim())
  } else {
    Write-Host "→ devices: (null)"
  }

  # --- D) Build update payload (GSS -> Jira + Raven enrichment) ---

  # 1) Pull GSS values we want to write to Jira
  $gssCeqId = $null
  $gssCompany = $null
  $gssTdac = $null
  $gssBundleVersion = $null

  try { $gssCeqId        = [string]$chosen.ceqId } catch {}
  try { $gssCompany      = [string]$chosen.companyName } catch {}
  try { $gssTdac         = [string]$chosen.devices.tdac } catch {}
  try { $gssBundleVersion= [string]$chosen.devices.deviceBundleVersion } catch {}

  Write-Host "🧩 GSS extracted:"
  Write-Host ("   ceqId:        '{0}'" -f ($gssCeqId | Out-String).Trim())
  Write-Host ("   companyName:  '{0}'" -f ($gssCompany | Out-String).Trim())
  Write-Host ("   tdac(root):   '{0}'" -f ($gssTdac | Out-String).Trim())
  Write-Host ("   bundleVer:    '{0}'" -f ($gssBundleVersion | Out-String).Trim())

  # 2) Raven root id MUST come from GSS tdac (not Jira customfield_13094)
  $ravenRootId = $gssTdac
  if ([string]::IsNullOrWhiteSpace($ravenRootId)) {
    Write-Host "⚠️ Raven root id is blank from GSS. Raven will be skipped for $issueKey."
  } else {
    Write-Host ("🔌 Raven lookup will use rootId='{0}'" -f $ravenRootId)
  }

  # 3) Run Raven enrichment
  $raven = $null
  try {
    $raven = Get-RavenEnrichment -RootDeviceId $ravenRootId
  } catch {
    Show-HttpError $_ "Raven enrichment threw for rootId=$ravenRootId"
    $raven = $null
  }

  if ($raven) {
    Write-Host "🧠 Raven enrichment result:"
    Write-Host ("   rootSw:   '{0}'" -f ($raven.RavenRootSoftwareVersion | Out-String).Trim())
    Write-Host ("   ANT bc:   '{0}'" -f ($raven.AntalyaBarcode | Out-String).Trim())
    Write-Host ("   ANT sw:   '{0}'" -f ($raven.AntalyaSw | Out-String).Trim())
    Write-Host ("   PEG bc:   '{0}'" -f ($raven.PegasusBarcode | Out-String).Trim())
    Write-Host ("   PEG sw:   '{0}'" -f ($raven.PegasusSw | Out-String).Trim())
  } else {
    Write-Host "ℹ️ Raven enrichment returned null/empty."
  }

  # 4) Build fields to set
  $fieldsToSet = @{}

  # --- Always write these from GSS when present ---
  if (-not [string]::IsNullOrWhiteSpace($gssCeqId))   { $fieldsToSet["customfield_13088"] = $gssCeqId }
  if (-not [string]::IsNullOrWhiteSpace($gssTdac))    { $fieldsToSet["customfield_13094"] = $gssTdac }

  # CompanyName: only write if Jira is empty (prevents overwriting)
  $jiraCompany = $issue.fields.customfield_13089
  if ([string]::IsNullOrWhiteSpace([string]$jiraCompany) -and -not [string]::IsNullOrWhiteSpace($gssCompany)) {
    $fieldsToSet["customfield_13089"] = $gssCompany
  } else {
    Write-Host ("ℹ️ Not updating 13089 (already set in Jira to '{0}')" -f ($jiraCompany | Out-String).Trim())
  }

  # --- Raven-derived fields (only if present) ---
  if ($raven -and -not [string]::IsNullOrWhiteSpace($raven.AntalyaBarcode)) { $fieldsToSet["customfield_16650"] = [string]$raven.AntalyaBarcode }
  if ($raven -and -not [string]::IsNullOrWhiteSpace($raven.AntalyaSw))      { $fieldsToSet["customfield_16507"] = [string]$raven.AntalyaSw }
  if ($raven -and -not [string]::IsNullOrWhiteSpace($raven.PegasusBarcode)) { $fieldsToSet["customfield_16649"] = [string]$raven.PegasusBarcode }
  if ($raven -and -not [string]::IsNullOrWhiteSpace($raven.PegasusSw))      { $fieldsToSet["customfield_16505"] = [string]$raven.PegasusSw }

# --- Bundle field 13318 (Raven first, GSS fallback) ---
$bundleToWrite = $null
if ($raven -and -not [string]::IsNullOrWhiteSpace($raven.RavenRootSoftwareVersion)) {
  $bundleToWrite = [string]$raven.RavenRootSoftwareVersion
  Write-Host "✅ 13318 from Raven root softwareVersion"
}
elseif (-not [string]::IsNullOrWhiteSpace($gssBundleVersion)) {
  $bundleToWrite = $gssBundleVersion
  Write-Host "✅ 13318 from GSS deviceBundleVersion (fallback)"
}
else {
  Write-Host "⚠️ No bundle version from Raven or GSS"
}

if (-not [string]::IsNullOrWhiteSpace($bundleToWrite)) {
  $fieldsToSet["customfield_13318"] = $bundleToWrite
}

  # 5) Editmeta filtering (same as you had)
  if (-not $editMeta) {
    Write-Host "⚠️ editmeta missing; skipping $issueKey to avoid 400s."
    continue
  }

  $editableNames = $editMeta.fields.PSObject.Properties.Name
  foreach ($k in @($fieldsToSet.Keys)) {
    if ($editableNames -notcontains $k) {
      Write-Host "🚫 Not editable on this issue screen: $k (skipping)"
      $fieldsToSet.Remove($k) | Out-Null
    }
  }

  if ($fieldsToSet.Count -eq 0) {
    Write-Host "ℹ️ Nothing to update for $issueKey."
    continue
  }

  $updateFields = @{ fields = $fieldsToSet } | ConvertTo-Json -Depth 10
  Write-Host "🧾 Payload to Jira:"
  Write-Host $updateFields

  # --- E) PUT with visible HTTP details ---
  $updateUrl = "$jiraBaseUrl/rest/api/3/issue/$issueId"
  try {
    $respUpd = Invoke-WebRequest -Uri $updateUrl -Method Put -Headers $headers -Body $updateFields
    Write-Host "✅ Updated $issueKey (HTTP $($respUpd.StatusCode))"
  } catch {
    Show-HttpError $_ "Failed to update $issueKey"
    continue
  }
}
