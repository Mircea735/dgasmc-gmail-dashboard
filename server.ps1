$port    = 8080
$dir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch "^127\." -and $_.IPAddress -notmatch "^169\." } | Select-Object -First 1).IPAddress
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host ""
Write-Host "  DGASMC Dashboard pornit pe http://localhost:$port"
if ($localIP) { Write-Host "  Acces retea locala:        http://${localIP}:$port" }
Write-Host "  Telefon - Aprobare:        http://${localIP}:$port/approve"
Write-Host "  Apasa Ctrl+C pentru a opri"
Write-Host ""

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response

        if ($req.Url.AbsolutePath -eq '/api/ocr' -and $req.HttpMethod -eq 'POST') {
            # Proxy catre Anthropic — citeste body ca bytes bruti, fara parsare JSON
            try {
                # Extrage apiKey si beta din query string (?k=...&beta=...)
                $query  = $req.Url.Query.TrimStart('?')
                $params = @{}
                foreach ($pair in $query.Split('&')) {
                    $parts = $pair.Split('=', 2)
                    if ($parts.Length -eq 2) {
                        $params[$parts[0]] = [System.Uri]::UnescapeDataString($parts[1])
                    }
                }
                $apiKey = $params['k']
                $beta   = $params['beta']

                # Citeste body brut
                $ms = New-Object System.IO.MemoryStream
                $req.InputStream.CopyTo($ms)
                $bodyBytes = $ms.ToArray()
                $ms.Close()

                $wreq = [System.Net.HttpWebRequest]::Create('https://api.anthropic.com/v1/messages')
                $wreq.Method      = 'POST'
                $wreq.ContentType = 'application/json; charset=utf-8'
                $wreq.ContentLength = $bodyBytes.Length
                $wreq.Headers.Add('x-api-key', $apiKey)
                $wreq.Headers.Add('anthropic-version', '2023-06-01')
                if ($beta) { $wreq.Headers.Add('anthropic-beta', $beta) }

                $ws = $wreq.GetRequestStream()
                $ws.Write($bodyBytes, 0, $bodyBytes.Length)
                $ws.Close()

                try {
                    $wresp    = $wreq.GetResponse()
                    $rms      = New-Object System.IO.MemoryStream
                    $wresp.GetResponseStream().CopyTo($rms)
                    $wresp.Close()
                    $respBytes = $rms.ToArray()
                    $rms.Close()
                    $res.StatusCode      = 200
                } catch [System.Net.WebException] {
                    $errRsp   = $_.Exception.Response
                    $rms      = New-Object System.IO.MemoryStream
                    $errRsp.GetResponseStream().CopyTo($rms)
                    $errRsp.Close()
                    $respBytes = $rms.ToArray()
                    $rms.Close()
                    $res.StatusCode = [int]$errRsp.StatusCode
                }

                $res.ContentType     = 'application/json; charset=utf-8'
                $res.ContentLength64 = $respBytes.Length
                $res.OutputStream.Write($respBytes, 0, $respBytes.Length)

            } catch {
                $errMsg   = '{"error":{"message":"Proxy error: ' + ($_.Exception.Message -replace '"','`"') + '"}}'
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                $res.StatusCode      = 500
                $res.ContentType     = 'application/json; charset=utf-8'
                $res.ContentLength64 = $errBytes.Length
                $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }

        } elseif ($req.Url.AbsolutePath -eq '/api/pending' -and $req.HttpMethod -eq 'GET') {
            $pendingFile = Join-Path $dir "pending.json"
            if (Test-Path $pendingFile) {
                $content = [System.IO.File]::ReadAllBytes($pendingFile)
                $res.ContentType = "application/json; charset=utf-8"
                $res.ContentLength64 = $content.Length
                $res.OutputStream.Write($content, 0, $content.Length)
            } else {
                $empty = [System.Text.Encoding]::UTF8.GetBytes('{"pending":false}')
                $res.ContentType = "application/json; charset=utf-8"
                $res.ContentLength64 = $empty.Length
                $res.OutputStream.Write($empty, 0, $empty.Length)
            }

        } elseif ($req.Url.AbsolutePath -eq '/api/respond' -and $req.HttpMethod -eq 'POST') {
            $ms = New-Object System.IO.MemoryStream
            $req.InputStream.CopyTo($ms)
            $bodyBytes = $ms.ToArray()
            $ms.Close()
            $responseFile = Join-Path $dir "response.json"
            [System.IO.File]::WriteAllBytes($responseFile, $bodyBytes)
            $pendingFile = Join-Path $dir "pending.json"
            if (Test-Path $pendingFile) { Remove-Item $pendingFile -Force }
            $ok = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true}')
            $res.ContentType = "application/json; charset=utf-8"
            $res.ContentLength64 = $ok.Length
            $res.OutputStream.Write($ok, 0, $ok.Length)

        } elseif ($req.Url.AbsolutePath -eq '/approve') {
            $html = @'
<!DOCTYPE html>
<html lang="ro">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Claude Code - Aprobare</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #0d1117; color: #e6edf3; min-height: 100vh; display: flex; flex-direction: column; align-items: center; padding: 20px; }
  h1 { font-size: 1.1rem; color: #58a6ff; margin-bottom: 20px; margin-top: 10px; }
  #status { font-size: 0.85rem; color: #8b949e; margin-bottom: 16px; }
  #card { background: #161b22; border: 1px solid #30363d; border-radius: 12px; padding: 20px; width: 100%; max-width: 420px; display: none; }
  #tool-name { font-size: 1rem; font-weight: 600; color: #f0f6fc; margin-bottom: 8px; }
  #tool-input { font-size: 0.78rem; color: #8b949e; background: #0d1117; border-radius: 8px; padding: 12px; margin-bottom: 20px; white-space: pre-wrap; word-break: break-all; max-height: 200px; overflow-y: auto; }
  .btns { display: flex; gap: 12px; }
  button { flex: 1; padding: 14px; border: none; border-radius: 8px; font-size: 1rem; font-weight: 600; cursor: pointer; }
  #btn-accept { background: #238636; color: #fff; }
  #btn-deny   { background: #da3633; color: #fff; }
  #waiting { text-align: center; color: #8b949e; font-size: 0.9rem; padding: 40px 0; }
  .dot { animation: blink 1.4s infinite; }
  .dot:nth-child(2) { animation-delay: .2s; }
  .dot:nth-child(3) { animation-delay: .4s; }
  @keyframes blink { 0%,80%,100%{opacity:0} 40%{opacity:1} }
</style>
</head>
<body>
<h1>Claude Code Remote</h1>
<div id="status">Se verifica...</div>
<div id="card">
  <div id="tool-name"></div>
  <div id="tool-input"></div>
  <div class="btns">
    <button id="btn-accept">✓ Accept</button>
    <button id="btn-deny">✕ Deny</button>
  </div>
</div>
<div id="waiting">
  Asteapta cereri<span class="dot">.</span><span class="dot">.</span><span class="dot">.</span>
</div>
<script>
async function poll() {
  try {
    const r = await fetch('/api/pending');
    const d = await r.json();
    if (d.pending) {
      document.getElementById('status').textContent = 'Cerere noua!';
      document.getElementById('tool-name').textContent = '🔧 ' + (d.tool || 'Tool');
      document.getElementById('tool-input').textContent = JSON.stringify(d.input, null, 2);
      document.getElementById('card').style.display = 'block';
      document.getElementById('waiting').style.display = 'none';
    } else {
      document.getElementById('status').textContent = 'In asteptare...';
      document.getElementById('card').style.display = 'none';
      document.getElementById('waiting').style.display = 'block';
    }
  } catch(e) {}
  setTimeout(poll, 1500);
}

async function respond(decision) {
  document.getElementById('card').style.display = 'none';
  document.getElementById('waiting').style.display = 'block';
  document.getElementById('status').textContent = decision === 'allow' ? 'Acceptat!' : 'Respins!';
  await fetch('/api/respond', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({decision}) });
}

document.getElementById('btn-accept').onclick = () => respond('allow');
document.getElementById('btn-deny').onclick   = () => respond('block');
poll();
</script>
</body>
</html>
'@
            $content = [System.Text.Encoding]::UTF8.GetBytes($html)
            $res.ContentType = "text/html; charset=utf-8"
            $res.ContentLength64 = $content.Length
            $res.OutputStream.Write($content, 0, $content.Length)

        } elseif ($req.Url.AbsolutePath -eq '/api/pq') {
            # Citește tabela Power Query din Excel-ul deschis via COM
            try {
                $ms = New-Object System.IO.MemoryStream
                $req.InputStream.CopyTo($ms)
                $bodyStr = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
                $payload = $bodyStr | ConvertFrom-Json
                $tableName = $payload.table
                if (-not $tableName) { throw "Lipseste numele tabelei (table)" }

                $xl = [System.Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application')
                if (-not $xl) { throw "Excel nu este deschis" }

                # Cauta tabela in toate workbook-urile deschise
                $found = $null
                foreach ($wb in $xl.Workbooks) {
                    foreach ($ws in $wb.Worksheets) {
                        foreach ($lo in $ws.ListObjects) {
                            if ($lo.Name -eq $tableName) { $found = $lo; break }
                        }
                        if ($found) { break }
                    }
                    if ($found) { break }
                }
                if (-not $found) { throw "Tabela '$tableName' nu a fost gasita in Excel" }

                $range = $found.Range
                $rows = @()
                $headers = @()
                $headerRow = $found.HeaderRowRange
                for ($c = 1; $c -le $headerRow.Columns.Count; $c++) {
                    $headers += $headerRow.Cells.Item(1, $c).Text
                }
                $dataRange = $found.DataBodyRange
                if ($dataRange) {
                    for ($r = 1; $r -le $dataRange.Rows.Count; $r++) {
                        $obj = @{}
                        for ($c = 1; $c -le $dataRange.Columns.Count; $c++) {
                            $obj[$headers[$c-1]] = $dataRange.Cells.Item($r, $c).Text
                        }
                        $rows += $obj
                    }
                }
                $jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
                $jss.MaxJsonLength = 104857600
                $json = $jss.Serialize(@{ rows = $rows; count = $rows.Count; columns = $headers })
                $b = (New-Object System.Text.UTF8Encoding $false).GetBytes($json)
                $res.ContentType = 'application/json; charset=utf-8'
                $res.ContentLength64 = $b.Length; $res.OutputStream.Write($b, 0, $b.Length)
            } catch {
                $safeMsg = $_.Exception.Message -replace '\\','\\' -replace '"','\"'
                $e = (New-Object System.Text.UTF8Encoding $false).GetBytes('{"error":"' + $safeMsg + '"}')
                $res.StatusCode = 500; $res.ContentType = 'application/json; charset=utf-8'
                $res.ContentLength64 = $e.Length; $res.OutputStream.Write($e, 0, $e.Length)
            }

        } elseif ($req.Url.AbsolutePath -eq '/api/sql-ping') {
            $psVer = $PSVersionTable.PSVersion.ToString()
            $hasSqlClient = $null -ne ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { try { $_.GetType('System.Data.SqlClient.SqlConnection') -ne $null } catch { $false } } | Select-Object -First 1)
            Add-Type -AssemblyName System.Data -ErrorAction SilentlyContinue
            $hasSqlClient2 = $null -ne [System.Type]::GetType('System.Data.SqlClient.SqlConnection, System.Data')
            $info = @{ psVersion=$psVer; sqlClientLoaded=($hasSqlClient -or $hasSqlClient2); serverVersion='2026-04' } | ConvertTo-Json -Compress
            $b = [System.Text.Encoding]::UTF8.GetBytes($info)
            $res.ContentType = 'application/json'; $res.ContentLength64 = $b.Length; $res.OutputStream.Write($b,0,$b.Length)

        } elseif ($req.Url.AbsolutePath -eq '/api/sql' -and $req.HttpMethod -eq 'POST') {
            # SQL Server proxy — executa query si returneaza JSON
            try {
                $ms = New-Object System.IO.MemoryStream
                $req.InputStream.CopyTo($ms)
                $bodyStr = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
                $ms.Close()
                $payload = $bodyStr | ConvertFrom-Json

                $connStr = $payload.conn
                $query   = $payload.query

                if (-not $connStr -or -not $query) { throw "Lipseste conn sau query" }

                # Sanitize: allow only SELECT / EXEC on views
                $trimmed = $query.Trim()
                if ($trimmed -notmatch '^(SELECT|EXEC|EXECUTE)\s') {
                    throw "Doar SELECT/EXEC permis"
                }

                Add-Type -AssemblyName System.Data -ErrorAction SilentlyContinue
                $table = New-Object System.Data.DataTable
                $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
                $conn.Open()
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = $query
                $cmd.CommandTimeout = 30
                $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
                $adapter.Fill($table) | Out-Null
                $conn.Close()

                # Convert DataTable to array of objects
                $rows = @()
                foreach ($row in $table.Rows) {
                    $obj = @{}
                    foreach ($col in $table.Columns) {
                        $val = $row[$col.ColumnName]
                        if ($val -is [System.DBNull]) { $val = $null }
                        elseif ($val -is [datetime]) { $val = $val.ToString('dd.MM.yyyy') }
                        elseif ($val -ne $null) { $val = $val.ToString() }
                        $obj[$col.ColumnName] = $val
                    }
                    $rows += $obj
                }
                # Serializare manuala robusta — evita bug-urile ConvertTo-Json PS5.1 cu diacritice/ghilimele
                $sb = New-Object System.Text.StringBuilder
                $jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
                $jss.MaxJsonLength = 104857600 # 100MB
                $payload = @{ rows = $rows; count = $rows.Count; columns = @($table.Columns | ForEach-Object { $_.ColumnName }) }
                $json = $jss.Serialize($payload)
                $respBytes = (New-Object System.Text.UTF8Encoding $false).GetBytes($json)
                $res.StatusCode = 200
                $res.ContentType = 'application/json; charset=utf-8'
                $res.ContentLength64 = $respBytes.Length
                $res.OutputStream.Write($respBytes, 0, $respBytes.Length)
            } catch {
                $safeMsg = $_.Exception.Message -replace '\\', '\\\\' -replace '"', '\"' -replace "`r`n", ' ' -replace "`n", ' '
                $errMsg = '{"error":"' + $safeMsg + '"}'
                $errBytes = (New-Object System.Text.UTF8Encoding $false).GetBytes($errMsg)
                $res.StatusCode = 500
                $res.ContentType = 'application/json; charset=utf-8'
                $res.ContentLength64 = $errBytes.Length
                $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }

        } elseif ($req.Url.AbsolutePath -eq '/api/raport/start' -and $req.HttpMethod -eq 'POST') {
            # Lanseaza run_raport.py ca job PowerShell asincron
            try {
                $ms = New-Object System.IO.MemoryStream
                $req.InputStream.CopyTo($ms)
                $bodyStr = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
                $ms.Close()

                # Genereaza ID job si scrie params JSON
                $jobId     = [System.Guid]::NewGuid().ToString('N').Substring(0,8)
                $paramsFile = Join-Path $dir "raport_params_$jobId.json"
                $logFile    = Join-Path $dir "raport_log_$jobId.json"
                [System.IO.File]::WriteAllText($paramsFile, $bodyStr, [System.Text.Encoding]::UTF8)
                [System.IO.File]::WriteAllText($logFile, '{"lines":[]}', [System.Text.Encoding]::UTF8)

                $pyScript = Join-Path $dir "run_raport.py"
                $script = {
                    param($py, $params, $log)
                    $lines = @()
                    & python $py $params 2>&1 | ForEach-Object {
                        $lines += $_
                        $obj = @{ lines = $lines }
                        [System.IO.File]::WriteAllText($log, ($obj | ConvertTo-Json -Depth 5 -Compress), [System.Text.Encoding]::UTF8)
                    }
                }
                $job = Start-Job -ScriptBlock $script -ArgumentList $pyScript, $paramsFile, $logFile
                # Salveaza job ID -> PowerShell job ID mapping
                $mapFile = Join-Path $dir "raport_jobs.json"
                $map = @{}
                if (Test-Path $mapFile) {
                    try { $parsed = Get-Content $mapFile -Raw | ConvertFrom-Json; $parsed.PSObject.Properties | ForEach-Object { $map[$_.Name]=$_.Value } } catch {}
                }
                $map[$jobId] = $job.Id
                $map | ConvertTo-Json -Depth 2 -Compress | Out-File $mapFile -Encoding UTF8

                $resp = [System.Text.Encoding]::UTF8.GetBytes(('{"jobId":"' + $jobId + '"}'))
                $res.StatusCode = 200
                $res.ContentType = 'application/json; charset=utf-8'
                $res.ContentLength64 = $resp.Length
                $res.OutputStream.Write($resp, 0, $resp.Length)
            } catch {
                $e = [System.Text.Encoding]::UTF8.GetBytes('{"error":"' + ($_.Exception.Message -replace '"','`"') + '"}')
                $res.StatusCode = 500; $res.ContentType = 'application/json; charset=utf-8'
                $res.ContentLength64 = $e.Length; $res.OutputStream.Write($e, 0, $e.Length)
            }

        } elseif ($req.Url.AbsolutePath -match '^/api/raport/poll/([a-f0-9]+)$' -and $req.HttpMethod -eq 'GET') {
            # Returneaza logul curent al job-ului
            $jobId   = $Matches[1]
            $logFile = Join-Path $dir "raport_log_$jobId.json"
            if (Test-Path $logFile) {
                $content = [System.IO.File]::ReadAllBytes($logFile)
                $res.StatusCode = 200
                $res.ContentType = 'application/json; charset=utf-8'
                $res.ContentLength64 = $content.Length
                $res.OutputStream.Write($content, 0, $content.Length)
            } else {
                $notFound = [System.Text.Encoding]::UTF8.GetBytes('{"error":"job not found"}')
                $res.StatusCode = 404; $res.ContentType = 'application/json; charset=utf-8'
                $res.ContentLength64 = $notFound.Length; $res.OutputStream.Write($notFound, 0, $notFound.Length)
            }

        } elseif ($req.Url.AbsolutePath -match '^/api/raport/download/([a-f0-9]+)$' -and $req.HttpMethod -eq 'GET') {
            # Descarca primul fisier generat de job
            $jobId   = $Matches[1]
            $logFile = Join-Path $dir "raport_log_$jobId.json"
            try {
                $logContent = Get-Content $logFile -Raw | ConvertFrom-Json
                # Gaseste linia "done" cu files[]
                $doneLine = $logContent.lines | Where-Object { $_ -match '"done"' } | Select-Object -Last 1
                if ($doneLine) {
                    $doneObj = $doneLine | ConvertFrom-Json
                    $filePath = $doneObj.files | Select-Object -First 1
                    if ($filePath -and (Test-Path $filePath)) {
                        $bytes = [System.IO.File]::ReadAllBytes($filePath)
                        $fname = [System.IO.Path]::GetFileName($filePath)
                        $res.StatusCode = 200
                        $res.ContentType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                        $res.Headers.Add('Content-Disposition', "attachment; filename*=UTF-8''" + [System.Uri]::EscapeDataString($fname))
                        $res.ContentLength64 = $bytes.Length
                        $res.OutputStream.Write($bytes, 0, $bytes.Length)
                    } else {
                        $e = [System.Text.Encoding]::UTF8.GetBytes('{"error":"fisier negasit"}')
                        $res.StatusCode = 404; $res.ContentType = 'application/json; charset=utf-8'
                        $res.ContentLength64 = $e.Length; $res.OutputStream.Write($e, 0, $e.Length)
                    }
                } else {
                    $e = [System.Text.Encoding]::UTF8.GetBytes('{"error":"job inca ruleaza"}')
                    $res.StatusCode = 202; $res.ContentType = 'application/json; charset=utf-8'
                    $res.ContentLength64 = $e.Length; $res.OutputStream.Write($e, 0, $e.Length)
                }
            } catch {
                $e = [System.Text.Encoding]::UTF8.GetBytes('{"error":"' + ($_.Exception.Message -replace '"','`"') + '"}')
                $res.StatusCode = 500; $res.ContentType = 'application/json; charset=utf-8'
                $res.ContentLength64 = $e.Length; $res.OutputStream.Write($e, 0, $e.Length)
            }

        } elseif ($req.Url.AbsolutePath -eq '/bi' -or $req.Url.AbsolutePath -eq '/bi/') {
            $file    = Join-Path $dir "dashboard-bi.html"
            $content = [System.IO.File]::ReadAllBytes($file)
            $res.ContentType     = "text/html; charset=utf-8"
            $res.ContentLength64 = $content.Length
            $res.OutputStream.Write($content, 0, $content.Length)
        } else {
            $file    = Join-Path $dir "index.html"
            $content = [System.IO.File]::ReadAllBytes($file)
            $res.ContentType     = "text/html; charset=utf-8"
            $res.ContentLength64 = $content.Length
            $res.OutputStream.Write($content, 0, $content.Length)
        }

        $res.OutputStream.Close()
    } catch { }
}
