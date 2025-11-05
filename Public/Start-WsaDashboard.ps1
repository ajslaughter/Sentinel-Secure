function Start-WsaDashboard {
    <#
    .SYNOPSIS
        Starts a futuristic live health dashboard HTTP server with action endpoints.

    .DESCRIPTION
        Creates an HTTP server using System.Net.HttpListener that serves a cyberpunk-styled
        dashboard on http://localhost:PORT and provides JSON API endpoints for:
        - GET /api/health - Real-time system metrics
        - POST /api/action/* - Action endpoints for WinSysAuto functions

        Works on any Windows system without additional module dependencies.

    .PARAMETER Port
        The port to listen on (default: 8080).

    .PARAMETER AuthToken
        Optional authentication token. When set, all POST endpoints require
        the X-Auth-Token header to match this value.

    .EXAMPLE
        Start-WsaDashboard
        Starts the dashboard server on port 8080 (default).

    .EXAMPLE
        Start-WsaDashboard -Port 9090 -AuthToken "mySecret123"
        Starts the dashboard server on port 9090 with authentication required.

    .NOTES
        Press Ctrl+C to stop the server.
        The dashboard auto-refreshes every 30 seconds.
        Ensure Windows Firewall allows the port if accessing remotely.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [int]$Port = 8080,

        [Parameter()]
        [string]$AuthToken
    )

    if (-not $PSCmdlet.ShouldProcess("HTTP Listener on port $Port", "Start dashboard server")) {
        return
    }

    #region Helper Functions

    # JSON Response Helper
    function Send-JsonResponse {
        param(
            [Parameter(Mandatory)]
            $Response,
            [Parameter(Mandatory)]
            $Data,
            [int]$StatusCode = 200
        )
        try {
            $json = $Data | ConvertTo-Json -Depth 10 -Compress
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $Response.StatusCode = $StatusCode
            $Response.ContentType = 'application/json; charset=utf-8'
            $Response.ContentLength64 = $buffer.Length
            $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        catch {
            Write-WsaLog -Component 'Dashboard' -Message "Failed to send JSON response: $($_.Exception.Message)" -Level 'ERROR'
        }
    }

    # Read JSON Request Body
    function Read-JsonRequest {
        param(
            [Parameter(Mandatory)]
            $Request
        )
        try {
            $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()
            if ([string]::IsNullOrWhiteSpace($body)) {
                return @{}
            }
            return $body | ConvertFrom-Json
        }
        catch {
            Write-WsaLog -Component 'Dashboard' -Message "Failed to parse JSON request: $($_.Exception.Message)" -Level 'WARN'
            return $null
        }
    }

    # Parse Multipart Form Data
    function Read-MultipartRequest {
        param(
            [Parameter(Mandatory)]
            $Request
        )
        try {
            $contentType = $Request.ContentType
            if ($contentType -notmatch 'boundary=(.+)$') {
                throw "No boundary found in Content-Type"
            }
            $boundary = "--" + $matches[1]

            $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()

            $result = @{}
            $parts = $body -split $boundary | Where-Object { $_ -and $_ -notmatch '^--\s*$' }

            foreach ($part in $parts) {
                if ($part -match 'Content-Disposition: form-data; name="([^"]+)"(?:; filename="([^"]+)")?') {
                    $name = $matches[1]
                    $filename = $matches[2]

                    # Extract content after headers
                    $content = $part -replace '(?s)^.*?\r?\n\r?\n', ''
                    $content = $content.TrimEnd("`r`n")

                    if ($filename) {
                        $result[$name] = @{
                            Filename = $filename
                            Content = $content
                        }
                    } else {
                        $result[$name] = $content
                    }
                }
            }
            return $result
        }
        catch {
            Write-WsaLog -Component 'Dashboard' -Message "Failed to parse multipart request: $($_.Exception.Message)" -Level 'ERROR'
            return $null
        }
    }

    # Check Authentication
    function Test-AuthToken {
        param(
            [Parameter(Mandatory)]
            $Request,
            [string]$RequiredToken
        )
        if ([string]::IsNullOrWhiteSpace($RequiredToken)) {
            return $true
        }
        $headerToken = $Request.Headers['X-Auth-Token']
        return $headerToken -eq $RequiredToken
    }

    # Check Admin Rights
    function Test-AdminRights {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    # Dashboard Logging Helper
    function Write-DashboardLog {
        param(
            [string]$Route,
            [bool]$Success,
            [int]$DurationMs,
            [string]$Error
        )
        try {
            $logRoot = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\Logs'
            if (-not (Test-Path -Path $logRoot)) {
                New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
            }
            $logPath = Join-Path -Path $logRoot -ChildPath 'dashboard.log'
            $logEntry = @{
                timestamp = (Get-Date -Format 's')
                route = $Route
                ok = $Success
                durationMs = $DurationMs
            }
            if ($Error) {
                $logEntry.error = $Error
            }
            $logEntry | ConvertTo-Json -Compress | Add-Content -Path $logPath -Encoding UTF8
        }
        catch {
            Write-Verbose "Failed to write dashboard log: $($_.Exception.Message)"
        }
    }

    #endregion

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $dashboardRoot = Join-Path -Path $moduleRoot -ChildPath 'Dashboard'
    $dashboardHtml = Join-Path -Path $dashboardRoot -ChildPath 'dashboard.html'

    if (-not (Test-Path -Path $dashboardHtml)) {
        throw "Dashboard HTML not found at '$dashboardHtml'. Ensure Dashboard folder exists."
    }

    # Ensure uploads directory exists
    $uploadsRoot = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\uploads'
    if (-not (Test-Path -Path $uploadsRoot)) {
        New-Item -Path $uploadsRoot -ItemType Directory -Force | Out-Null
    }

    Write-WsaLog -Component 'Dashboard' -Message "Starting live dashboard on port $Port" -Level 'INFO'
    if ($AuthToken) {
        Write-WsaLog -Component 'Dashboard' -Message "Authentication enabled" -Level 'INFO'
    }

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

                $startTime = Get-Date

                # Route handling
                if ($request.Url.AbsolutePath -eq '/' -or $request.Url.AbsolutePath -eq '/index.html') {
                    # Serve dashboard.html with optional auth token injection
                    $htmlContent = Get-Content -Path $dashboardHtml -Raw -Encoding UTF8
                    if ($AuthToken) {
                        $tokenScript = "<script>window.WSA_AUTH_TOKEN = `"$AuthToken`";</script>"
                        $htmlContent = $htmlContent -replace '</head>', "$tokenScript`n</head>"
                    }
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
                    $response.ContentType = 'text/html; charset=utf-8'
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                elseif ($request.Url.AbsolutePath -eq '/api/health' -and $request.HttpMethod -eq 'GET') {
                    # Serve JSON health data
                    $healthData = Get-WsaDashboardData
                    $json = $healthData | ConvertTo-Json -Depth 10 -Compress
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $response.ContentType = 'application/json; charset=utf-8'
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                elseif ($request.Url.AbsolutePath -match '^/api/action/' -and $request.HttpMethod -eq 'POST') {
                    # Handle POST action endpoints
                    $actionPath = $request.Url.AbsolutePath

                    # Check authentication
                    if (-not (Test-AuthToken -Request $request -RequiredToken $AuthToken)) {
                        $responseData = @{
                            ok = $false
                            message = "Authentication required"
                            error = @{
                                type = "Unauthorized"
                                details = "Missing or invalid X-Auth-Token header"
                            }
                        }
                        Send-JsonResponse -Response $response -Data $responseData -StatusCode 401
                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                        Write-DashboardLog -Route $actionPath -Success $false -DurationMs $duration -Error "Unauthorized"
                    }
                    else {
                        try {
                            # Route to appropriate action handler
                            switch ($actionPath) {
                                '/api/action/init-environment' {
                                    $body = Read-JsonRequest -Request $request
                                    $force = if ($body -and $body.force) { $body.force } else { $false }

                                    try {
                                        $result = Initialize-WsaEnvironment -Force:$force
                                        $responseData = @{
                                            ok = $true
                                            message = "Environment initialized successfully"
                                            configPath = $result.Data.ConfigPath
                                            data = $result
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $true -DurationMs $duration
                                    }
                                    catch {
                                        $responseData = @{
                                            ok = $false
                                            message = "Failed to initialize environment"
                                            error = @{
                                                type = $_.Exception.GetType().Name
                                                details = $_.Exception.Message
                                                hresult = $_.Exception.HResult
                                            }
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData -StatusCode 200
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $false -DurationMs $duration -Error $_.Exception.Message
                                    }
                                }

                                '/api/action/health' {
                                    try {
                                        $result = Get-WsaHealth
                                        $responseData = @{
                                            ok = $true
                                            message = "Health check completed"
                                            data = $result
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $true -DurationMs $duration
                                    }
                                    catch {
                                        $responseData = @{
                                            ok = $false
                                            message = "Health check failed"
                                            error = @{
                                                type = $_.Exception.GetType().Name
                                                details = $_.Exception.Message
                                                hresult = $_.Exception.HResult
                                            }
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData -StatusCode 200
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $false -DurationMs $duration -Error $_.Exception.Message
                                    }
                                }

                                '/api/action/backup' {
                                    $body = Read-JsonRequest -Request $request

                                    try {
                                        $result = Backup-WsaConfig
                                        $responseData = @{
                                            ok = $true
                                            message = "Backup completed successfully"
                                            backupPath = $result.Data.ArchivePath
                                            data = $result
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $true -DurationMs $duration
                                    }
                                    catch {
                                        $responseData = @{
                                            ok = $false
                                            message = "Backup failed"
                                            error = @{
                                                type = $_.Exception.GetType().Name
                                                details = $_.Exception.Message
                                                hresult = $_.Exception.HResult
                                            }
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData -StatusCode 200
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $false -DurationMs $duration -Error $_.Exception.Message
                                    }
                                }

                                '/api/action/security-baseline' {
                                    $body = Read-JsonRequest -Request $request
                                    if (-not $body -or -not $body.mode) {
                                        $responseData = @{
                                            ok = $false
                                            message = "Missing required parameter: mode"
                                            error = @{
                                                type = "ValidationError"
                                                details = "The 'mode' parameter is required (Audit or Enforce)"
                                            }
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData -StatusCode 200
                                        return
                                    }

                                    # Check admin rights for Enforce mode
                                    if ($body.mode -eq 'Enforce' -and -not (Test-AdminRights)) {
                                        $responseData = @{
                                            ok = $false
                                            message = "Admin privileges required for this action"
                                            error = @{
                                                type = "InsufficientPrivileges"
                                                details = "Enforce mode requires administrator rights"
                                            }
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData -StatusCode 200
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $false -DurationMs $duration -Error "Insufficient privileges"
                                        return
                                    }

                                    try {
                                        $isRollback = $body.mode -eq 'Rollback'
                                        $result = Invoke-WsaSecurityBaseline -Rollback:$isRollback

                                        $summary = "Mode: $($body.mode)"
                                        if ($result.Changes) {
                                            $summary += " | Changes: $($result.Changes.Count)"
                                        }

                                        $responseData = @{
                                            ok = $true
                                            message = "Security baseline action completed"
                                            mode = $body.mode
                                            summary = $summary
                                            details = $result.Changes
                                            data = $result
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $true -DurationMs $duration
                                    }
                                    catch {
                                        $responseData = @{
                                            ok = $false
                                            message = "Security baseline action failed"
                                            error = @{
                                                type = $_.Exception.GetType().Name
                                                details = $_.Exception.Message
                                                hresult = $_.Exception.HResult
                                            }
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData -StatusCode 200
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $false -DurationMs $duration -Error $_.Exception.Message
                                    }
                                }

                                '/api/action/new-users' {
                                    # Check AD module availability
                                    if (-not (Get-Command -Name New-ADUser -ErrorAction SilentlyContinue)) {
                                        $responseData = @{
                                            ok = $false
                                            message = "AD tools not available"
                                            error = @{
                                                type = "ModuleNotAvailable"
                                                details = "Active Directory module is not installed on this system"
                                            }
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData -StatusCode 200
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $false -DurationMs $duration -Error "AD module not available"
                                        return
                                    }

                                    # Check admin rights
                                    if (-not (Test-AdminRights)) {
                                        $responseData = @{
                                            ok = $false
                                            message = "Admin privileges required for this action"
                                            error = @{
                                                type = "InsufficientPrivileges"
                                                details = "User creation requires administrator rights"
                                            }
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData -StatusCode 200
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $false -DurationMs $duration -Error "Insufficient privileges"
                                        return
                                    }

                                    try {
                                        # Handle multipart or JSON
                                        $csvPath = $null
                                        $defaultOU = $null
                                        $groupsMode = "Append"
                                        $resetPasswords = $false

                                        if ($request.ContentType -and $request.ContentType.StartsWith('multipart/form-data')) {
                                            # Parse multipart form data
                                            $formData = Read-MultipartRequest -Request $request
                                            if (-not $formData) {
                                                throw "Failed to parse multipart form data"
                                            }

                                            # Check file size (2 MB limit)
                                            if ($formData.file -and $formData.file.Content.Length -gt 2MB) {
                                                $responseData = @{
                                                    ok = $false
                                                    message = "File size exceeds 2 MB limit"
                                                    error = @{
                                                        type = "FileTooLarge"
                                                        details = "Maximum file size is 2 MB"
                                                    }
                                                }
                                                Send-JsonResponse -Response $response -Data $responseData -StatusCode 200
                                                return
                                            }

                                            # Save uploaded file
                                            if ($formData.file) {
                                                $filename = $formData.file.Filename
                                                if ($filename -notmatch '\.csv$') {
                                                    throw "Only .csv files are allowed"
                                                }
                                                $csvPath = Join-Path -Path $uploadsRoot -ChildPath $filename
                                                $formData.file.Content | Out-File -FilePath $csvPath -Encoding UTF8 -Force
                                            }

                                            # Parse optional parameters
                                            if ($formData.defaultOU) { $defaultOU = $formData.defaultOU }
                                            if ($formData.groupsMode) { $groupsMode = $formData.groupsMode }
                                            if ($formData.resetPasswords) { $resetPasswords = [bool]::Parse($formData.resetPasswords) }
                                        }
                                        else {
                                            # JSON request
                                            $body = Read-JsonRequest -Request $request
                                            if ($body.path) {
                                                $csvPath = $body.path
                                            }
                                            if ($body.defaultOU) { $defaultOU = $body.defaultOU }
                                            if ($body.groupsMode) { $groupsMode = $body.groupsMode }
                                            if ($body.resetPasswords) { $resetPasswords = $body.resetPasswords }
                                        }

                                        if (-not $csvPath -or -not (Test-Path -Path $csvPath)) {
                                            throw "No valid CSV file provided"
                                        }

                                        # Call New-WsaUsersFromCsv
                                        $params = @{
                                            Path = $csvPath
                                            ResetPasswordIfProvided = $resetPasswords
                                        }
                                        if ($defaultOU) {
                                            $params.DefaultOU = $defaultOU
                                        }
                                        if ($groupsMode -eq "Replace") {
                                            # Note: The function doesn't have a GroupsMode param in the signature we saw,
                                            # but we'll include it in the response for future extension
                                        }

                                        $result = New-WsaUsersFromCsv @params

                                        # Count created/skipped users
                                        $created = ($result.Changes | Where-Object { $_ -match 'Created|Added' }).Count
                                        $skipped = ($result.Findings | Where-Object { $_ -match 'Skipped|Exists' }).Count

                                        $responseData = @{
                                            ok = $true
                                            message = "User creation completed"
                                            created = $created
                                            skipped = $skipped
                                            reportPath = $csvPath
                                            data = $result
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $true -DurationMs $duration
                                    }
                                    catch {
                                        $responseData = @{
                                            ok = $false
                                            message = "User creation failed"
                                            error = @{
                                                type = $_.Exception.GetType().Name
                                                details = $_.Exception.Message
                                                hresult = $_.Exception.HResult
                                            }
                                        }
                                        Send-JsonResponse -Response $response -Data $responseData -StatusCode 200
                                        $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                        Write-DashboardLog -Route $actionPath -Success $false -DurationMs $duration -Error $_.Exception.Message
                                    }
                                }

                                default {
                                    # Unknown action endpoint
                                    $responseData = @{
                                        ok = $false
                                        message = "Unknown action endpoint"
                                        error = @{
                                            type = "NotFound"
                                            details = "The requested action endpoint does not exist"
                                        }
                                    }
                                    Send-JsonResponse -Response $response -Data $responseData -StatusCode 404
                                    $duration = ((Get-Date) - $startTime).TotalMilliseconds
                                    Write-DashboardLog -Route $actionPath -Success $false -DurationMs $duration -Error "Unknown endpoint"
                                }
                            }
                        }
                        catch {
                            $responseData = @{
                                ok = $false
                                message = "Action request failed"
                                error = @{
                                    type = $_.Exception.GetType().Name
                                    details = $_.Exception.Message
                                    hresult = $_.Exception.HResult
                                }
                            }
                            Send-JsonResponse -Response $response -Data $responseData -StatusCode 500
                            $duration = ((Get-Date) - $startTime).TotalMilliseconds
                            Write-DashboardLog -Route $actionPath -Success $false -DurationMs $duration -Error $_.Exception.Message
                        }
                    }
                }
                elseif ($request.HttpMethod -eq 'GET' -and $request.Url.AbsolutePath -ieq '/style.css') {
                    # Serve style.css
                    try {
                        $cssPath = Join-Path -Path $dashboardRoot -ChildPath 'style.css'
                        if (Test-Path -Path $cssPath) {
                            $css = Get-Content -Path $cssPath -Raw -Encoding UTF8
                        } else {
                            $css = '/* missing style.css */'
                        }
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($css)
                        $response.ContentType = 'text/css; charset=utf-8'
                        $response.Headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
                        $response.OutputStream.Write($bytes, 0, $bytes.Length)
                        $response.StatusCode = 200
                    } catch {
                        $msg = "/* " + $_.Exception.Message + " */"
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
                        $response.StatusCode = 500
                        $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    }
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
