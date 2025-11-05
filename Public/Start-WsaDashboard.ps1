function Start-WsaDashboard {
    <#
    .SYNOPSIS
        Starts a futuristic live health dashboard HTTP server.

    .DESCRIPTION
        Creates an HTTP server using System.Net.HttpListener that serves a cyberpunk-styled
        dashboard on http://localhost:PORT and provides a JSON API endpoint at /api/health
        for real-time system metrics.

        Works on any Windows system without additional module dependencies.

    .PARAMETER Port
        The port to listen on (default: 8080).

    .EXAMPLE
        Start-WsaDashboard
        Starts the dashboard server on port 8080 (default).

    .EXAMPLE
        Start-WsaDashboard -Port 9090
        Starts the dashboard server on port 9090.

    .NOTES
        Press Ctrl+C to stop the server.
        The dashboard auto-refreshes every 30 seconds.
        Ensure Windows Firewall allows the port if accessing remotely.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [int]$Port = 8080
    )

    if (-not $PSCmdlet.ShouldProcess("HTTP Listener on port $Port", "Start dashboard server")) {
        return
    }

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $dashboardRoot = Join-Path -Path $moduleRoot -ChildPath 'Dashboard'
    $dashboardHtml = Join-Path -Path $dashboardRoot -ChildPath 'dashboard.html'

    if (-not (Test-Path -Path $dashboardHtml)) {
        throw "Dashboard HTML not found at '$dashboardHtml'. Ensure Dashboard folder exists."
    }

    Write-WsaLog -Component 'Dashboard' -Message "Starting live dashboard on port $Port" -Level 'INFO'

    # Create HTTP listener
    $listener = New-Object System.Net.HttpListener
    $prefix = "http://localhost:$Port/"
    $listener.Prefixes.Add($prefix)

    try {
        $listener.Start()
        Write-Host "`n" -NoNewline
        Write-Host "=" * 60 -ForegroundColor Cyan
        Write-Host "  WinSysAuto Dashboard Server Started" -ForegroundColor Cyan
        Write-Host "=" * 60 -ForegroundColor Cyan
        Write-Host "`n  URL: " -NoNewline
        Write-Host $prefix -ForegroundColor Green
        Write-Host "  API: " -NoNewline
        Write-Host "${prefix}api/health" -ForegroundColor Green
        Write-Host "`n  Press Ctrl+C to stop the server" -ForegroundColor Yellow
        Write-Host "=" * 60 -ForegroundColor Cyan
        Write-Host "`n"

        Write-WsaLog -Component 'Dashboard' -Message "HTTP listener started successfully on $prefix" -Level 'INFO'

        # Main server loop
        while ($listener.IsListening) {
            try {
                $context = $listener.GetContext()
                $request = $context.Request
                $response = $context.Response

                Write-Verbose "Request received: $($request.HttpMethod) $($request.Url.AbsolutePath)"
                Write-WsaLog -Component 'Dashboard' -Message "Request: $($request.HttpMethod) $($request.Url.AbsolutePath)" -Level 'DEBUG'

                # Route handling
                if ($request.Url.AbsolutePath -eq '/' -or $request.Url.AbsolutePath -eq '/index.html') {
                    # Serve dashboard.html
                    $htmlContent = Get-Content -Path $dashboardHtml -Raw -Encoding UTF8
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
                    $response.ContentType = 'text/html; charset=utf-8'
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                elseif ($request.Url.AbsolutePath -eq '/api/health') {
                    # Serve JSON health data
                    $healthData = Get-WsaDashboardData
                    $json = $healthData | ConvertTo-Json -Depth 10 -Compress
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = 'application/json; charset=utf-8'
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                else {
                    # 404 Not Found
                    $response.StatusCode = 404
                    $errorMsg = '404 Not Found'
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($errorMsg)
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }

                $response.Close()
            }
            catch {
                Write-WsaLog -Component 'Dashboard' -Message "Request error: $($_.Exception.Message)" -Level 'WARN'
            }
        }
    }
    catch {
        $msg = "Dashboard server error: $($_.Exception.Message)"
        Write-WsaLog -Component 'Dashboard' -Message $msg -Level 'ERROR'
        Write-Host "`nERROR: $msg" -ForegroundColor Red
        Write-Host "Hint: Make sure port $Port is not already in use." -ForegroundColor Yellow
        throw
    }
    finally {
        if ($listener.IsListening) {
            $listener.Stop()
            Write-WsaLog -Component 'Dashboard' -Message 'Dashboard server stopped' -Level 'INFO'
        }
        $listener.Close()
        Write-Host "`nDashboard server stopped." -ForegroundColor Cyan
    }
}
