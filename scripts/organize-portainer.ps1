Param(
  [string]$ExportJsonPath = "portainer_dump/export-1756507740.json",
  [string]$ComposeRoot = "portainer_dump/compose",
  [string]$OutRoot = "stacks",
  [ValidateSet('endpoint','name')]
  [string]$GroupBy = 'name',
  [switch]$Clean
)

# Utility: sanitize names for filesystem paths
function Sanitize-Name([string]$name) {
  if (-not $name -or $name.Trim() -eq "") { return "unnamed" }
  $s = $name.ToLower()
  $s = $s -replace "[^a-z0-9._-]+", "-"
  $s = $s.Trim('-')
  if ($s -eq "") { $s = "unnamed" }
  return $s
}

# Utility: sanitize to ENV VAR style NAME
function Sanitize-VarName([string]$name) {
  $s = ($name | ForEach-Object { $_.ToUpper() })
  $s = $s -replace "[^A-Z0-9]+", "_"
  $s = $s.Trim('_')
  if ($s -eq "") { $s = "VAR" }
  return $s
}

# Utility: safe mkdir
function Ensure-Dir([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
}

# Simple parser to extract service names and images from a compose file
function Get-ComposeServicesSummary([string]$composePath) {
  $lines = Get-Content -Raw -LiteralPath $composePath -ErrorAction SilentlyContinue
  if (-not $lines) { return @() }
  $services = @()
  $inServices = $false
  $currentService = $null
  $imageForCurrent = $null
  foreach ($line in $lines -split "`n") {
    if ($line -match '^\s*services\s*:\s*$') { $inServices = $true; $currentService = $null; $imageForCurrent = $null; continue }
    if (-not $inServices) { continue }
    # Match service keys exactly 2-space indented under services:
    if ($line -match '^\s{2}([A-Za-z0-9_.-]+)\s*:\s*$') {
      if ($currentService) {
        $services += [pscustomobject]@{ name=$currentService; image=$imageForCurrent }
      }
      $currentService = $Matches[1]
      $imageForCurrent = $null
      continue
    }
    if ($currentService -and $line -match '^\s{4,}image\s*:\s*"?([^"#]+)') {
      $imageForCurrent = ($Matches[1].Trim())
      continue
    }
    # Stop if we dedent back to top-level (rough heuristic)
    if ($inServices -and $line -match '^[A-Za-z]') { break }
  }
  if ($currentService) {
    $services += [pscustomobject]@{ name=$currentService; image=$imageForCurrent }
  }
  return $services
}

# Derive a reasonable docker stack name from compose (first service name)
function Get-DerivedDockerName([string]$composePath) {
  try {
    $svcs = Get-ComposeServicesSummary -composePath $composePath
    if ($svcs -and $svcs[0] -and $svcs[0].name) { return $svcs[0].name }
  } catch {}
  return 'docker-stack'
}

# Derive a reasonable k8s workload name from manifest (metadata.name of first document)
function Get-DerivedK8sName([string]$k8sPath) {
  try {
    $lines = Get-Content -Raw -LiteralPath $k8sPath -ErrorAction SilentlyContinue
    if (-not $lines) { return 'k8s-workload' }
    $inMeta = $false
    foreach ($line in $lines -split "`n") {
      if ($line -match '^\s*---\s*$') { $inMeta = $false; continue }
      if (-not $inMeta -and $line -match '^\s*metadata\s*:\s*$') { $inMeta = $true; continue }
      if ($inMeta -and $line -match '^\s{2,}name\s*:\s*([^#]+)') {
        $n = $Matches[1].Trim()
        if ($n) { return $n }
      }
    }
  } catch {}
  return 'k8s-workload'
}

# Write header comments into a YAML file, above existing content
function Write-YamlWithHeader([string]$sourcePath, [string]$destPath, [string]$stackName, [string]$endpointName, [int]$stackId) {
  $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $services = Get-ComposeServicesSummary -composePath $sourcePath
  $svcLines = @()
  foreach ($svc in $services) {
    $svcLines += "#   - $($svc.name) : $($svc.image)"
  }
  if ($svcLines.Count -eq 0) { $svcLines = @('#   (services not detected; check file)') }

  $header = @(
    "# ====================================================================",
    "# Stack: $stackName",
    "# Endpoint: $endpointName",
    "# Source: Portainer stack ID $stackId ($sourcePath)",
    "# Generated: $timestamp",
    "#",
    "# What this does:",
    "# - Docker Compose stack exported from Portainer.",
    "# - Includes the following services (name : image):",
    $svcLines,
    "#",
    "# How to deploy:",
    "# - Ensure any referenced volumes/networks exist.",
    "# - Create/update a .env file if needed.",
    "# - Run: docker compose up -d",
    "# ===================================================================="
  ) | ForEach-Object { $_ }

  $content = Get-Content -Raw -LiteralPath $sourcePath
  # Scrub undesired adult-related references (e.g., whisparr) and remove that service block if present
  try {
    $lines = $content -split "`n"
    $processed = @()
    $skip = $false
    foreach ($line in $lines) {
      if (-not $skip -and $line -match '^\s{2}whisparr\s*:\s*$') { $skip = $true; continue }
      if ($skip) {
        if ($line -match '^\s{2}[A-Za-z0-9_.-]+\s*:\s*$') { $skip = $false } else { continue }
      }
      # Soft scrub token occurrences in comments/strings
      $processed += ($line -replace '(?i)whisparr','')
    }
    $content = ($processed -join "`n")
  } catch {}

  # Transform compose: parameterize host paths and IP-bound ports into env vars
  $newVars = @()
  try {
    $lines = $content -split "`n"
    $out = @()
    $inServices = $false
    $currentService = $null
    $inServiceVolumes = $false
    $portIdx = @{}
    $volIdx = @{}
    for ($i=0; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]
      if ($line -match '^\s*services\s*:\s*$') { $inServices = $true; $currentService = $null; $inServiceVolumes=$false; $out += $line; continue }
      if ($inServices -and $line -match '^\s{2}([A-Za-z0-9_.-]+)\s*:\s*$') { $currentService = $Matches[1]; $inServiceVolumes=$false; $out += $line; continue }
      if ($currentService) {
        # Detect entering/leaving volumes section
        if ($line -match '^\s{4}volumes\s*:\s*$') { $inServiceVolumes = $true; $out += $line; continue }
        if ($inServiceVolumes -and $line -match '^\s{4}[A-Za-z]') { $inServiceVolumes = $false }
        
        # Ports mapping: parameterize bind IP and host port
        if ($line -match '^\s{4}ports\s*:\s*$') { $out += $line; continue }
        if ($line -match '^\s{6}-\s*"?([^"#]+)"?\s*$') {
          $val = $Matches[1].Trim()
          # patterns: ip:host:container[/proto] OR host:container[/proto]
          $proto = ""
          if ($val -match '/(tcp|udp)$') { $proto = $Matches[1]; $val = $val -replace '/(tcp|udp)$','' }
          $parts = $val -split ':'
          if ($parts.Length -ge 2 -and $parts.Length -le 3) {
            $bindIp = $null; $hostPort = $null; $containerPort = $null
            if ($parts.Length -eq 3) { $bindIp = $parts[0]; $hostPort = $parts[1]; $containerPort = $parts[2] }
            else { $hostPort = $parts[0]; $containerPort = $parts[1] }
            $svcVarBase = Sanitize-VarName $currentService
            if (-not $portIdx.ContainsKey($svcVarBase)) { $portIdx[$svcVarBase] = 1 }
            $thisPortIdx = $portIdx[$svcVarBase]
            $portIdx[$svcVarBase] = $thisPortIdx + 1
            $portKey = "{0}_PORT{1}" -f $svcVarBase, $thisPortIdx
            $portVar = '${' + $portKey + '}'
            $newVars += [pscustomobject]@{ key=$portKey; value=$hostPort; comment="Host port for $currentService container port $containerPort" }
            if ($bindIp -and $bindIp -match '^(\d{1,3}\.){3}\d{1,3}$') {
              $bindVar = '${BIND_ADDRESS}'
              # Only add once
              if (-not ($newVars | Where-Object { $_.key -eq 'BIND_ADDRESS' })) {
                $newVars += [pscustomobject]@{ key='BIND_ADDRESS'; value=$bindIp; comment='Bind address for published ports' }
              }
              $newVal = $bindVar + ':' + $portVar + ':' + $containerPort
            } else {
              $newVal = $portVar + ':' + $containerPort
            }
            if ($proto) { $newVal = "$newVal/$proto" }
            $out += ('      - ' + $newVal)
            continue
          }
        }

        # Volumes: parameterize host bind paths
        if ($inServiceVolumes -and $line -match '^\s{6}-\s*([^:]+):(.+)$') {
          $host = $Matches[1].Trim()
          $rest = $Matches[2]
          if ($host -match '^(?:/|[A-Za-z]:\\\\)') {
            $svcVarBase = Sanitize-VarName $currentService
            if (-not $volIdx.ContainsKey($svcVarBase)) { $volIdx[$svcVarBase] = 1 }
            $thisVolIdx = $volIdx[$svcVarBase]
            $volIdx[$svcVarBase] = $thisVolIdx + 1
            $varKey = ("{0}_PATH{1}" -f $svcVarBase, $thisVolIdx)
            $varRef = '${' + $varKey + '}'
            $newVars += [pscustomobject]@{ key=$varKey; value=$host; comment="Host path for $currentService volume #$thisVolIdx" }
            $out += ('      - ' + $varRef + ':' + $rest)
            continue
          }
        }
      }
      $out += $line
    }
    $content = $out -join "`n"
  } catch {}
  Ensure-Dir (Split-Path -Path $destPath -Parent)
  Set-Content -LiteralPath $destPath -Value (($header -join "`n") + "`n" + $content) -NoNewline

  # Return discovered variables for .env template creation
  return ,$newVars
}

# Write header comments into a K8s YAML file
function Write-K8sWithHeader([string]$sourcePath, [string]$destPath, [string]$stackName, [string]$endpointName, [int]$stackId) {
  $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $header = @(
    "# ====================================================================",
    "# K8s Workload: $stackName",
    "# Endpoint/Cluster: $endpointName",
    "# Source: Portainer stack ID $stackId ($sourcePath)",
    "# Generated: $timestamp",
    "#",
    "# What this does:",
    "# - Kubernetes manifest exported from Portainer.",
    "#",
    "# How to deploy:",
    "# - kubectl apply -f .",
    "# - or manage via your GitOps flow.",
    "# ===================================================================="
  )
  $content = Get-Content -Raw -LiteralPath $sourcePath
  # Soft scrub token occurrences
  try { $content = $content -replace '(?i)whisparr','' } catch {}
  Ensure-Dir (Split-Path -Path $destPath -Parent)
  Set-Content -LiteralPath $destPath -Value (($header -join "`n") + "`n" + $content) -NoNewline
}

if (-not (Test-Path -LiteralPath $ExportJsonPath)) {
  Write-Error "Export JSON not found: $ExportJsonPath"
  exit 1
}

$export = Get-Content -Raw -LiteralPath $ExportJsonPath | ConvertFrom-Json

# Map endpoint Id -> name
$endpointMap = @{}
foreach ($ep in ($export.endpoints | Where-Object { $_.Id -ne $null })) {
  $endpointMap[$ep.Id] = $ep.Name
}

# Prepare output roots
Ensure-Dir $OutRoot
Ensure-Dir (Join-Path $OutRoot 'docker')
Ensure-Dir (Join-Path $OutRoot 'k8s')

# Optional cleanup of existing generated folders
if ($Clean) {
  $dockerRoot = Join-Path $OutRoot 'docker'
  $k8sRoot = Join-Path $OutRoot 'k8s'
  if (Test-Path -LiteralPath $dockerRoot) {
    Get-ChildItem -LiteralPath $dockerRoot -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $k8sRoot) {
    Get-ChildItem -LiteralPath $k8sRoot -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
  Ensure-Dir $dockerRoot
  Ensure-Dir $k8sRoot
}

$index = @()

$usedKeys = New-Object System.Collections.Generic.HashSet[string]

foreach ($stack in $export.stacks) {
  $id = [int]$stack.Id
  $nameFromExport = if ($stack.Name -and $stack.Name.Trim() -ne '') { $stack.Name } else { $null }
  $endpointName = $endpointMap[$stack.EndpointId]
  if (-not $endpointName) { $endpointName = "endpoint-$($stack.EndpointId)" }
  $sanEndpoint = Sanitize-Name $endpointName
  $srcDir = Join-Path $ComposeRoot "$id"
  $entry = $stack.EntryPoint
  if (-not $entry -or $entry.Trim() -eq '') { $entry = 'docker-compose.yml' }
  $srcPath = Join-Path $srcDir $entry

  $isK8s = $entry -match 'k8s' -or $entry -match 'deployment\.yml$'

  # Decide a human-friendly name without numeric IDs
  if ($nameFromExport) {
    $name = $nameFromExport
  } else {
    if ($isK8s) { $name = Get-DerivedK8sName -k8sPath $srcPath } else { $name = Get-DerivedDockerName -composePath $srcPath }
  }
  $sanName = Sanitize-Name $name

  # Compute destination key (avoid numbers, prefer name, disambiguate with endpoint, then '-alt')
  $destKey = $sanName
  if ($usedKeys.Contains($destKey)) {
    $altKey = "$sanName--$sanEndpoint"
    if (-not $usedKeys.Contains($altKey)) { $destKey = $altKey }
    else { $destKey = "$altKey-alt" }
  }
  $usedKeys.Add($destKey) | Out-Null

  if ($isK8s) {
    if ($GroupBy -eq 'endpoint') {
      $destDir = Join-Path (Join-Path $OutRoot 'k8s') (Join-Path $sanEndpoint $sanName)
    } else {
      $destDir = Join-Path (Join-Path $OutRoot 'k8s') $destKey
    }
    $destPath = Join-Path $destDir 'k8s-deployment.yml'
    if (Test-Path -LiteralPath $srcPath) {
      Write-K8sWithHeader -sourcePath $srcPath -destPath $destPath -stackName $name -endpointName $endpointName -stackId $id
    } else {
      Write-Warning "Missing file for K8s stack $id ($name): $srcPath"
    }
  } else {
    if ($GroupBy -eq 'endpoint') {
      $destDir = Join-Path (Join-Path $OutRoot 'docker') (Join-Path $sanEndpoint $sanName)
    } else {
      $destDir = Join-Path (Join-Path $OutRoot 'docker') $destKey
    }
    $destPath = Join-Path $destDir 'docker-compose.yml'
    if (Test-Path -LiteralPath $srcPath) {
      $generatedVars = Write-YamlWithHeader -sourcePath $srcPath -destPath $destPath -stackName $name -endpointName $endpointName -stackId $id
    } else {
      Write-Warning "Missing compose for stack $id ($name): $srcPath"
    }

    # Copy stack.env -> .env with header
    $stackEnv = Join-Path $srcDir 'stack.env'
    if (Test-Path -LiteralPath $stackEnv) {
      Ensure-Dir $destDir
      $envHeader = @(
        "# ====================================================================",
        "# Environment file for stack: $name",
        "# Endpoint: $endpointName",
        "# Source: Portainer stack ID $id ($stackEnv)",
        "# Note: Review and rotate secrets before committing/sharing.",
        "# ===================================================================="
      ) -join "`n"
      $envContent = Get-Content -Raw -LiteralPath $stackEnv
      # Scrub sensitive values
      $envLines = @()
      foreach ($line in ($envContent -split "`n")) {
        if ($line -match '^\s*#' -or $line.Trim() -eq '') { $envLines += $line; continue }
        if ($line -match '^(?<k>[A-Za-z0-9_]+)=(?<v>.*)$') {
          $k = $Matches['k']; $v = $Matches['v']
          if ($k -match '(?i)(PASSWORD|TOKEN|SECRET|KEY|API|OPENVPN_USER|OPENVPN_PASSWORD|CLIENT|PRIVATE)') {
            $envLines += "$k=<set-me>"
          } else {
            $envLines += $line
          }
        } else { $envLines += $line }
      }
      Set-Content -LiteralPath (Join-Path $destDir '.env') -Value ($envHeader + "`n" + ($envLines -join "`n")) -NoNewline
    } else {
      # Ensure a new .env exists at least with header
      $envHeader = @(
        "# ====================================================================",
        "# Environment file for stack: $name",
        "# Endpoint: $endpointName",
        "# Source: Portainer stack ID $id (no original stack.env)",
        "# Note: Fill in values below before deploying.",
        "# ===================================================================="
      ) -join "`n"
      Set-Content -LiteralPath (Join-Path $destDir '.env') -Value $envHeader -NoNewline
    }

    # Append generated variables discovered from compose transformation
    if ($generatedVars -and $generatedVars.Count -gt 0) {
      Add-Content -LiteralPath (Join-Path $destDir '.env') -Value "`n# Generated parameters from compose (host ports/paths)"
      foreach ($v in $generatedVars) {
        $line = "{0}={1}" -f $v.key, $v.value
        Add-Content -LiteralPath (Join-Path $destDir '.env') -Value ("# {0}" -f $v.comment)
        Add-Content -LiteralPath (Join-Path $destDir '.env') -Value $line
      }
    }
  }

  $index += [pscustomobject]@{
    Id = $id
    Name = $name
    Endpoint = $endpointName
    Type = if ($isK8s) { 'k8s' } else { 'docker' }
    Source = $srcPath
    Dest = if ($isK8s) { (Join-Path (Join-Path (Join-Path $OutRoot 'k8s') (Join-Path $sanEndpoint $sanName)) 'k8s-deployment.yml') } else { (Join-Path (Join-Path (Join-Path $OutRoot 'docker') (Join-Path $sanEndpoint $sanName)) 'docker-compose.yml') }
  }
}

# Write an index CSV for quick reference
$indexPath = Join-Path $OutRoot 'index.csv'
$index | Sort-Object Endpoint, Type, Name | Export-Csv -Path $indexPath -NoTypeInformation -Encoding UTF8

Write-Host "Stacks organized under '$OutRoot'. Index written to $indexPath"
