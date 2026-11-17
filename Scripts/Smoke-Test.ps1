<#
.SYNOPSIS
  Post-deploy smoke tests for the web app. Read-only: never creates data, never uses a key or token.
  Runs after every deploy (testnet, then mainnet); any failure fails the pipeline stage.

.EXAMPLE
  ./Scripts/Smoke-Test.ps1 -Site testnet-app.deltanium.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Site,
    [string]$ExpectCommit = ''
)
$ErrorActionPreference = 'Stop'
$Site = @($Site | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
Add-Type -AssemblyName System.Net.Http
$script:http = [System.Net.Http.HttpClient]::new()
$script:http.Timeout = [TimeSpan]::FromSeconds(30)
$script:failures = 0

function Invoke-Http([string]$Method, [string]$Url, [hashtable]$Headers = @{}, [string]$Body = $null) {
    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Url)
    foreach ($k in $Headers.Keys) { [void]$req.Headers.TryAddWithoutValidation($k, [string]$Headers[$k]) }
    if ($Method -ne 'GET') {
        $req.Content = [System.Net.Http.StringContent]::new($(if ($Body) { $Body } else { '' }), [Text.Encoding]::UTF8, 'application/json')
    }
    $resp = $script:http.SendAsync($req).GetAwaiter().GetResult()
    [pscustomobject]@{ Status = [int]$resp.StatusCode; Body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() }
}

function Check([string]$Name, [scriptblock]$Test) {
    try {
        $detail = & $Test
        Write-Host "PASS $Name $detail"
    } catch {
        $script:failures++
        Write-Host "FAIL $Name : $($_.Exception.Message)"
        Write-Host "##vso[task.logissue type=error]Smoke FAIL $Name : $($_.Exception.Message)"
    }
}

function Expect-Status($r, [int[]]$Want) {
    if ($Want -notcontains $r.Status) { throw "HTTP $($r.Status), want $($Want -join '/'): $($r.Body.Substring(0, [Math]::Min(160, $r.Body.Length)))" }
    "($($r.Status))"
}

function Expect-NoPrivateFields([string]$Json, [string[]]$Fields) {
    foreach ($f in $Fields) {
        if ($Json -match ('"' + $f + '"\s*:')) { throw "response exposes '$f'" }
    }
}
foreach ($s in $Site) {
    $b = "https://$s"
    Write-Host "=== App smoke: $b"

    Check 'version.json' {
        $v = (Invoke-Http GET "$b/version.json").Body | ConvertFrom-Json
        if (-not $v.commit) { throw 'no commit' }
        if ($ExpectCommit -and $v.commit -ne $ExpectCommit) { throw "serves $($v.commit), want $ExpectCommit" }
        $want = if ($s -like 'testnet-*') { 'deltanium-test' } else { 'mainnet' }
        if ($v.network -and $v.network -ne $want) { throw "network=$($v.network), want $want" }
        "$($v.commit.Substring(0,7)) network=$($v.network)"
    }
    Check 'index and main.dart.js load' {
        $r = Invoke-Http GET "$b/"
        Expect-Status $r 200 | Out-Null
        if ($r.Body -notmatch 'flutter') { throw 'index.html is not the Flutter app' }
        Expect-Status (Invoke-Http GET "$b/main.dart.js") 200
    }
}

$script:http.Dispose()
if ($script:failures -gt 0) { throw "$($script:failures) smoke check(s) failed" }
Write-Host 'All App smoke checks passed'
