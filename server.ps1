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
