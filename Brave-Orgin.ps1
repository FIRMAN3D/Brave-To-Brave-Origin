$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

$RegistryPath = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"

if (-not (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}

$Policies = @{
    "BraveAIChatEnabled"                       = 0
    "BraveNewsDisabled"                        = 1
    "BraveP3AEnabled"                          = 0
    "BraveRewardsDisabled"                     = 1
    "BraveStatsPingEnabled"                    = 0
    "BraveTalkDisabled"                        = 1
    "BraveVPNDisabled"                         = 1
    "BraveWalletDisabled"                      = 1
    "MetricsReportingEnabled"                  = 0
    "SafeBrowsingExtendedReportingEnabled"     = 0
    "TorDisabled"                              = 0
    "UrlKeyedAnonymizedDataCollectionEnabled"  = 0
}

foreach ($Name in $Policies.Keys) {
    Set-ItemProperty -Path $RegistryPath -Name $Name -Value $Policies[$Name] -Type DWord -Force
}

$IconFolder = "$env:ProgramData\BraveOrigin"
$IcoPath = "$IconFolder\brave-origin.ico"

if (-not (Test-Path $IconFolder)) {
    New-Item -Path $IconFolder -ItemType Directory -Force | Out-Null
}

Stop-Process -Name explorer -Force
Remove-Item "$env:LocalAppData\IconCache.db" -Force
Remove-Item "$env:LocalAppData\Microsoft\Windows\Explorer\iconcache_*" -Force
Start-Process explorer

$PngSources = @(
    @{ Size = 16;  Url = "https://i.ibb.co/RTYyFwGx/brave-origin-16x16.png" }
    @{ Size = 24;  Url = "https://i.ibb.co/nsMtWH6h/brave-origin-24x24.png" }
    @{ Size = 32;  Url = "https://i.ibb.co/GfrYvZZv/brave-origin-32x32.png" }
    @{ Size = 48;  Url = "https://i.ibb.co/SwSyPHkY/brave-origin-48x48.png" }
    @{ Size = 64;  Url = "https://i.ibb.co/DfcRrs5R/brave-origin-64x64.png" }
    @{ Size = 128; Url = "https://i.ibb.co/5xRKYSdb/brave-origin-128x128.png" }
    @{ Size = 256; Url = "https://i.ibb.co/7JmwqyhW/brave-origin-256x256.png" }
)

$BmpHeaderLength = 6
$DirectoryIndexLength = 16
$IcoImagesData = @()
$IcoDirectoryEntries = @()
$CurrentOffset = $BmpHeaderLength + ($DirectoryIndexLength * $PngSources.Count)

foreach ($Source in $PngSources) {
    $TempPngPath = "$IconFolder\temp_$($Source.Size).png"
    Invoke-WebRequest -Uri $Source.Url -OutFile $TempPngPath
    
    $Bytes = [System.IO.File]::ReadAllBytes($TempPngPath)
    $IcoImagesData += ,$Bytes
    Remove-Item $TempPngPath -Force

    $Width = if ($Source.Size -eq 256) { 0 } else { $Source.Size }
    $Height = if ($Source.Size -eq 256) { 0 } else { $Source.Size }
    
    $Entry = New-Object Byte[] $DirectoryIndexLength
    $Entry[0] = $Width
    $Entry[1] = $Height
    $Entry[2] = 0 
    $Entry[3] = 0 
    $Entry[4] = 1 
    $Entry[5] = 0
    $Entry[6] = 32 
    $Entry[7] = 0
    
    $SizeBytes = [BitConverter]::GetBytes($Bytes.Length)
    [Array]::Copy($SizeBytes, 0, $Entry, 8, 4)
    
    $OffsetBytes = [BitConverter]::GetBytes($CurrentOffset)
    [Array]::Copy($OffsetBytes, 0, $Entry, 12, 4)
    
    $IcoDirectoryEntries += ,$Entry
    $CurrentOffset += $Bytes.Length
}

$Stream = New-Object System.IO.FileStream($IcoPath, [System.IO.FileMode]::Create)
$Header = [Byte[]]@(0, 0, 1, 0, ($PngSources.Count), 0)
$Stream.Write($Header, 0, $Header.Length)

foreach ($Entry in $IcoDirectoryEntries) { $Stream.Write($Entry, 0, $Entry.Length) }
foreach ($ImageData in $IcoImagesData) { $Stream.Write($ImageData, 0, $ImageData.Length) }
$Stream.Close()

$BraveExe = "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe"
if (-not (Test-Path $BraveExe)) {
    $BraveExe = "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe"
}

if (Test-Path $BraveExe) {
    $TargetPaths = @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("CommonDesktopDirectory"),
        "$env:AppData\Microsoft\Windows\Start Menu\Programs",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    )

    foreach ($Folder in $TargetPaths) {
        if (Test-Path $Folder) {
            $OldShortcut = Join-Path $Folder "Brave.lnk"
            if (Test-Path $OldShortcut) { Remove-Item $OldShortcut -Force }

            $NewShortcutPath = Join-Path $Folder "Brave Origin.lnk"
            $WshShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut($NewShortcutPath)
            $Shortcut.TargetPath = $BraveExe
            $Shortcut.IconLocation = "$IcoPath,0"
            $Shortcut.Save()
        }
    }

    $TaskbarFolder = "$env:AppData\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    if (Test-Path $TaskbarFolder) {
        $OldTaskbar = Join-Path $TaskbarFolder "Brave.lnk"
        if (Test-Path $OldTaskbar) { Remove-Item $OldTaskbar -Force }

        $NewTaskbar = Join-Path $TaskbarFolder "Brave Origin.lnk"
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($NewTaskbar)
        $Shortcut.TargetPath = $BraveExe
        $Shortcut.IconLocation = "$IcoPath,0"
        $Shortcut.Save()
    }

    $Code = @'
    [DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern void SHChangeNotify(long wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
'@
    $Type = Add-Type -MemberDefinition $Code -Name "Shell32" -Namespace "Win32" -PassThru
    $Type::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
    
    Stop-Process -Name explorer -Force

    Stop-Process -Name explorer -Force
    Remove-Item "$env:LocalAppData\IconCache.db" -Force
    Remove-Item "$env:LocalAppData\Microsoft\Windows\Explorer\iconcache_*" -Force
    Start-Process explorer
}
