<#
  Serves the needutils-wiki-site folder at http://localhost:8000 so the website can be viewed on this PC.

  Run it from the needutils-wiki-site folder:
      powershell -ExecutionPolicy Bypass -File serve.ps1
  Then open http://localhost:8000 in your browser. Press Ctrl+C here to stop.
#>
param(
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $root"
Write-Host "Open http://localhost:$Port in your browser. Press Ctrl+C to stop."

$types = @{
    ".html" = "text/html; charset=utf-8"
    ".htm"  = "text/html; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".js"   = "text/javascript; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".webp" = "image/webp"
    ".svg"  = "image/svg+xml"
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        try {
            $path = [uri]::UnescapeDataString($request.Url.AbsolutePath).TrimStart('/')
            if ($path -eq "") { $path = "index.html" }

            $file = [System.IO.Path]::GetFullPath((Join-Path $root $path))
            # Only serve files inside the site folder.
            if (-not $file.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $file -PathType Leaf)) {
                $response.StatusCode = 404
                $bytes = [System.Text.Encoding]::UTF8.GetBytes("Not found")
            } else {
                $ext = [System.IO.Path]::GetExtension($file).ToLower()
                $response.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { "application/octet-stream" }
                $bytes = [System.IO.File]::ReadAllBytes($file)
            }
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch {
            $response.StatusCode = 500
        } finally {
            $response.OutputStream.Close()
        }
    }
} finally {
    $listener.Stop()
}
