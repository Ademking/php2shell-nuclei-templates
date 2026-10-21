param(
    [string]$LabRoot = 'C:\Users\ASUS\AppData\Local\Temp\opencode\php2shell-lab',
    [string]$WslDistro = 'kali-linux'
)

$ErrorActionPreference = 'SilentlyContinue'

$drive = $LabRoot.Substring(0, 1).ToLower()
$wslRoot = '/mnt/' + $drive + (($LabRoot.Substring(2)) -replace '\\', '/')

wsl -d $WslDistro bash -lc "nginx -s stop -c '$wslRoot/nginx-cgi.conf' -p /tmp/php2shell-nginx 2>/dev/null; pkill -f 'version_server[.]py' 2>/dev/null; true" | Out-Null
Write-Host "[*] Stopped nginx and the version server"

Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($LabRoot) } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "[*] Stopped PID $($_.ProcessId)"
    }
