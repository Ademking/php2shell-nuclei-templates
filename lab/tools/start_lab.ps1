param(
    [string]$PhpExe = 'C:\Users\ASUS\.pvm\versions\php-8.3.30-Win32-vs16-x64\php.exe',
    [string]$PhpCgiExe = 'C:\Users\ASUS\.pvm\versions\php-8.3.30-Win32-vs16-x64\php-cgi.exe',
    [string]$LabRoot = 'C:\Users\ASUS\AppData\Local\Temp\opencode\php2shell-lab',
    [string]$WslDistro = 'kali-linux',
    [string]$WslRepo = '/home/kali/nuclei-template'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fixtures = Join-Path $RepoRoot 'lab\fixtures'

Write-Host "[*] Stopping previous lab processes under $LabRoot"
Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($LabRoot) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 400

New-Item -ItemType Directory -Force -Path (Join-Path $LabRoot 'sessions'), (Join-Path $LabRoot 'logs') | Out-Null
Copy-Item -Recurse -Force (Join-Path $Fixtures '*') $LabRoot

$phpIni = @"
[Session]
session.save_handler = files
session.save_path = "$LabRoot\sessions"
session.use_strict_mode = 0
session.use_cookies = 1
session.use_only_cookies = 1
session.upload_progress.enabled = On
session.upload_progress.cleanup = Off
session.upload_progress.prefix = upload_progress_
session.upload_progress.name = PHP_SESSION_UPLOAD_PROGRESS
session.upload_progress.freq = 1%
session.upload_progress.min_freq = 0

[PHP]
display_errors = On
error_reporting = E_ALL
file_uploads = On
post_max_size = 128M
upload_max_filesize = 128M
expose_php = On
"@
Set-Content -Path (Join-Path $LabRoot 'php.ini') -Value $phpIni -Encoding ASCII

$phpIniPath = Join-Path $LabRoot 'php.ini'
$webroot = Join-Path $LabRoot 'webroot'
$servers = @(
    @{ Port = 18080; Extra = @() },
    @{ Port = 18082; Extra = @('-d', 'session.upload_progress.enabled=0') },
    @{ Port = 18083; Extra = @('-d', 'display_errors=0') },
    @{ Port = 18085; Extra = @('-d', 'session.use_strict_mode=1') },
    @{ Port = 18086; Extra = @('-d', 'session.upload_progress.cleanup=1') }
)

foreach ($server in $servers) {
    $arguments = @('-c', $phpIniPath) + $server.Extra + @('-S', "0.0.0.0:$($server.Port)", '-t', $webroot)
    Start-Process -FilePath $PhpExe -ArgumentList $arguments `
        -RedirectStandardOutput (Join-Path $LabRoot "logs\php-$($server.Port).out.log") `
        -RedirectStandardError (Join-Path $LabRoot "logs\php-$($server.Port).err.log") `
        -WindowStyle Hidden
    Write-Host "[+] PHP built-in server on :$($server.Port)"
}

Start-Process -FilePath $PhpCgiExe -ArgumentList @('-c', $phpIniPath, '-b', '0.0.0.0:9000') `
    -RedirectStandardOutput (Join-Path $LabRoot 'logs\php-cgi.out.log') `
    -RedirectStandardError (Join-Path $LabRoot 'logs\php-cgi.err.log') `
    -WindowStyle Hidden
Write-Host "[+] php-cgi FastCGI on :9000"

$drive = $LabRoot.Substring(0, 1).ToLower()
$wslRoot = '/mnt/' + $drive + (($LabRoot.Substring(2)) -replace '\\', '/')
$winRoot = $LabRoot -replace '\\', '/'
$wslHostIp = ''
$route = wsl -d $WslDistro bash -lc "ip route"
$routeMatch = [regex]::Match(($route -join "`n"), 'default via ([0-9.]+)')
if ($routeMatch.Success) {
    $wslHostIp = $routeMatch.Groups[1].Value
}
if (-not $wslHostIp) {
    throw "Could not determine the WSL default gateway (Windows host address)."
}

$nginxConf = @"
worker_processes 1;
pid /tmp/php2shell-nginx.pid;
error_log /tmp/php2shell-nginx-error.log warn;
events { worker_connections 256; }
http {
    access_log /tmp/php2shell-nginx-access.log;
    client_body_temp_path /tmp/php2shell-client-body;
    proxy_temp_path /tmp/php2shell-proxy;
    fastcgi_temp_path /tmp/php2shell-fastcgi;
    uwsgi_temp_path /tmp/php2shell-uwsgi;
    scgi_temp_path /tmp/php2shell-scgi;
    server {
        listen 18081;
        server_name _;
        root $wslRoot/cgi-webroot;
        index index.php;
        location ~ \.php$ {
            fastcgi_pass ${wslHostIp}:9000;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $winRoot/cgi-webroot`$fastcgi_script_name;
            fastcgi_param DOCUMENT_ROOT $winRoot/cgi-webroot;
            include /etc/nginx/fastcgi_params;
            fastcgi_read_timeout 30s;
        }
    }
}
"@
$nginxConfPath = Join-Path $LabRoot 'nginx-cgi.conf'
Set-Content -Path $nginxConfPath -Value $nginxConf -Encoding ASCII
$wslNginxConf = "$wslRoot/nginx-cgi.conf"

wsl -d $WslDistro bash -lc "nginx -s stop -c '$wslNginxConf' -p /tmp/php2shell-nginx 2>/dev/null; pkill -f 'version_server[.]py' 2>/dev/null; sleep 1; true"
wsl -d $WslDistro bash -lc "rm -rf /tmp/php2shell-nginx; mkdir -p /tmp/php2shell-nginx; nginx -c '$wslNginxConf' -p /tmp/php2shell-nginx"
Write-Host "[+] nginx on :18081 (Windows host $wslHostIp):9000"

wsl -d $WslDistro bash -lc "cd '$WslRepo' && setsid -f python3 lab/tools/version_server.py >/tmp/php2shell-version-server.log 2>&1"
Write-Host "[+] version server on :18084"

Start-Sleep -Seconds 2
Write-Host ""
Write-Host "Lab ready. Run the regression suite from WSL:"
Write-Host "  cd $WslRepo && ./lab/tools/test_templates.sh"
