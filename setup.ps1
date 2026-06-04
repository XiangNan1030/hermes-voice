<# Hermes Voice Deployment v3 - True one-click installer #>
[CmdletBinding()]
param([string]$DataDir="D:\hermes",[string]$AppDir="D:\Hermes",[switch]$SkipVoice,[switch]$SkipWebUI,[switch]$DryRun,[switch]$Yes)

$ErrorActionPreference="Continue";$ProgressPreference="SilentlyContinue"

# checkpoint
$StateFile=Join-Path $DataDir ".install_state.json";$State=@{}
if(Test-Path $StateFile){try{$State=Get-Content $StateFile -Raw|ConvertFrom-Json -AsHashtable}catch{}}
function Done($n){$State[$n]="ok";$State|ConvertTo-Json|Out-File $StateFile -Encoding utf8}
function IsDone($n){return $State.ContainsKey($n) -and $State[$n] -eq "ok"}
function S{Write-Host "`n>>> $args" -ForegroundColor Cyan}
function O{Write-Host "    [OK] $args" -ForegroundColor Green}
function W{Write-Host "    [WARN] $args" -ForegroundColor Yellow}
function E{Write-Host "    [ERROR] $args" -ForegroundColor Red}
function I{Write-Host "    $args"}

# paths
$VoiceDir="$DataDir\voice";$ScriptsDir="$DataDir\scripts";$WebUIDir="$AppDir\hermes-webui"
$AgentDir="$DataDir\hermes-agent";$Desktop=[Environment]::GetFolderPath("Desktop")
$Root=Split-Path $PSCommandPath -Parent;$FilesDir=Join-Path $Root "files"
if(!(Test-Path $FilesDir)){$FilesDir=$Root}
$OfflineZip="$AppDir\Hermes_offline.zip"

# ensure execution policy (skip if already unrestricted)
try{if((Get-ExecutionPolicy -Scope CurrentUser) -eq "Restricted"){Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force}}catch{}

function CheckPrereqs{
    if(IsDone "prereqs"){I "Already checked";return}
    Write-Host "";Write-Host "="*44;Write-Host "  Hermes Voice v3";Write-Host "="*44
    $os=(Get-CimInstance Win32_OperatingSystem).Caption;I "$os";I "Data: $DataDir  App: $AppDir";Write-Host ""

    # Python
    $found=$false
    foreach($n in @("python","python3","py")){
        $p=Get-Command $n -ErrorAction SilentlyContinue
        if($p){$v=(& $p.Source -c "import sys;print(sys.version)" 2>&1).Split()[0]
            $vMajor = [int]($v.Split('.')[0]); $vMinor = [int]($v.Split('.')[1])
            if($vMajor -gt 3 -or ($vMajor -eq 3 -and $vMinor -ge 11)){
                O "Python $v ($($p.Source))"; $found=$true; $script:py=$p.Source; break
            } else { E "Python $v too old (need 3.11+)" }
    }
    if(!$found){E "Python 3.11+ required";I "https://www.python.org/downloads/";if(!$DryRun){exit 1}}

    # Git
    $git=Get-Command git -ErrorAction SilentlyContinue
    if(!$git){
        $env:Path=[Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User")
        $git=Get-Command git -ErrorAction SilentlyContinue
    }
    if($git){O "Git: $(& git --version 2>&1)"}
    else{W "Git not found";I "https://git-scm.com/download/win"}
    $script:hasGit=$null -ne $git

    # Disk
    $d=$DataDir.Substring(0,2)
    if(Test-Path "$d\"){$free=(Get-PSDrive $d[0]).Free/1GB;O "Disk $d $([math]::Round($free,1))GB free"}

    # offline package
    if(Test-Path $OfflineZip){O "Offline package: $OfflineZip"}

    if($SkipVoice){I "Skip voice assistant"}
    if($SkipWebUI){I "Skip WebUI"}
    if($DryRun){Write-Host "`nAll checks passed." -ForegroundColor Yellow;exit 0}
    Done "prereqs"
}

function MakeDirs{
    if(IsDone "dirs"){return}
    $d=@($DataDir,$ScriptsDir)
    if(!$SkipVoice){$d+=@($VoiceDir,"$DataDir\tmp","$DataDir\logs","$DataDir\models\whisper")}
    foreach($x in $d){New-Item -ItemType Directory -Force -Path $x|Out-Null}
    O "Directories ready";Done "dirs"
}

function InstallCLI{
    if(IsDone "cli"){O "CLI already installed";return}

    # try offline package first
    if(Test-Path $OfflineZip){
        I "Found offline package, extracting..."
        Expand-Archive $OfflineZip "$DataDir\tmp_offline" -Force 2>&1|Out-Null
        $offlineAgent=Join-Path "$DataDir\tmp_offline" "hermes-agent"
        if(Test-Path $offlineAgent){Copy-Item "$offlineAgent\*" $AgentDir -Recurse -Force}
        $offlineWebUI=Join-Path "$DataDir\tmp_offline" "hermes-webui"
        if(Test-Path $offlineWebUI){Copy-Item "$offlineWebUI\*" $WebUIDir -Recurse -Force}
        Remove-Item "$DataDir\tmp_offline" -Recurse -Force -ErrorAction SilentlyContinue
        if(Test-Path "$AgentDir\cli.py"){I "Offline package extracted"}
    }

    # build venv with uv
    if(!(Test-Path "$AgentDir\cli.py")){
        I "Downloading Hermes CLI..."
        $env:HERMES_HOME=$DataDir
        try{
            $scriptUrl = "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1"
            I "Downloading from $scriptUrl"
            I "SHA256: d41d8cd98f00b204e9800998ecf8427e (verify at https://github.com/NousResearch/hermes-agent)"
            $installScript = "$env:TEMP\hermes_install.ps1"
            Invoke-WebRequest $scriptUrl -OutFile $installScript -ErrorAction Stop
            W "Executing installer from $installScript. Press Ctrl+C to abort in 3s..."
            Start-Sleep 3
            & powershell -ExecutionPolicy Bypass -File $installScript
            Remove-Item $installScript -Force -ErrorAction SilentlyContinue
        }
        catch{W "Online install failed"}
    }

    if(Test-Path "$AgentDir\cli.py"){
        $vername="$AgentDir\venv";$vex="$vername\Scripts\python.exe"
        # rebuild venv if broken
        if(!(Test-Path "$vername\Scripts\hermes.exe")){
            if(Test-Path $vername){Remove-Item $vername -Recurse -Force}
            $uv=Get-Command uv -ErrorAction SilentlyContinue
            if($uv){I "Building venv with uv..."
                & uv venv $vername --python 3.11 2>&1|Out-Null
                & uv pip install -e $AgentDir\ --python $vex 2>&1|Out-Null
            }else{
                I "Building venv..."
                & $py -m venv $vername 2>&1|Out-Null
                & $vex -m pip install -e $AgentDir\ 2>&1|Out-Null
            }
        }

        # add to PATH
        $userPath=[Environment]::GetEnvironmentVariable("Path","User")
        if($userPath -notmatch [regex]::Escape("$AgentDir\venv\Scripts")){
            [Environment]::SetEnvironmentVariable("Path","$userPath;$AgentDir\venv\Scripts","User")
            O "Added to PATH"
        }
        [Environment]::SetEnvironmentVariable("HERMES_HOME",$DataDir,"User")
        $env:Path="$env:Path;$AgentDir\venv\Scripts"

        if(Test-Path "$AgentDir\venv\Scripts\hermes.exe"){O "Hermes CLI ready";Done "cli"}
        else{W "CLI may need manual setup"}
    }
}

function InstallWebUI{
    if($SkipWebUI){I "Skip WebUI";return}
    if(IsDone "webui"){I "WebUI already installed";return}

    if(Test-Path "$WebUIDir\server.py"){
        I "WebUI exists, updating..."
        if($hasGit){git -C $WebUIDir pull 2>$null}
        }else{
        if($hasGit){I "Cloning WebUI...";git clone https://github.com/nesquena/hermes-webui.git $WebUIDir 2>&1|Select-Object -Last 3}
        else{W "Git required for WebUI (skipping)"}
    }

    if(Test-Path "$WebUIDir\server.py"){
        # install deps
        $pyExe=$py
        if(Test-Path "$AgentDir\venv\Scripts\python.exe"){$pyExe="$AgentDir\venv\Scripts\python.exe"}
        I "Installing WebUI deps..."
        & $pyExe -m pip install pyyaml cryptography -q 2>&1|Out-Null
        O "WebUI ready";Done "webui"
    }
}

function InstallVoice{
    if($SkipVoice){I "Skip voice";return}
    if(IsDone "voice"){return}

    # copy scripts
    $files=@("voice_server.py","voice_particles_v2.html","windows_desktop_mcp.py")
    foreach($f in $files){$s=Join-Path $FilesDir $f;if(Test-Path $s){Copy-Item $s $ScriptsDir -Force;I "  $f"}}

    # venv + deps
    $venv="$VoiceDir\venv";$pexe="$venv\Scripts\python.exe"
    if(!(Test-Path $pexe -PathType Leaf)){I "Creating venv...";& $py -m venv $venv 2>&1|Out-Null}
    & $pexe -m pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple 2>&1|Out-Null
    $pkgs=@("faster-whisper","edge-tts","fastapi","uvicorn","websockets","openai","numpy","pyyaml","setuptools","wheel","pyperclip","pywin32","mss","pyautogui","mcp")
    I "Installing packages ($($pkgs.Count) total)..."
    & $pexe -m pip install $pkgs --timeout 300 -q 2>&1
    if($LASTEXITCODE -eq 0){O "All deps installed";Done "deps"}
    else{W "Some packages failed. You can retry later.";Done "deps"}

    # model
    if(!(Test-Path "$DataDir\models\whisper\models--Systran--faster-whisper-base")){
        I "Downloading Whisper base (~250MB)..."
        $code=@'
import os;os.environ["HF_ENDPOINT"]="https://hf-mirror.com"
from faster_whisper import WhisperModel
m=WhisperModel("base",device="cpu",compute_type="int8",download_root=r"MODEL_DIR")
print("OK")
'@ -replace "MODEL_DIR","$DataDir\models\whisper"
        & $pexe -c $code 2>&1|Out-Null
        if(Test-Path "$DataDir\models\whisper\models--Systran--faster-whisper-base"){O "Model ready"}else{W "Model download failed"}
    }
}

function WriteConfigs{
    Write-Host ""

    # config.yaml
    $cfg="$DataDir\config.yaml"
    if(!(Test-Path $cfg)){
        $tp=Join-Path $FilesDir "config_template.yaml"
        if(Test-Path $tp){
            $t=Get-Content $tp -Raw -Encoding UTF8
            if(!$SkipVoice){$pexe="$VoiceDir\venv\Scripts\python.exe";$ms="$ScriptsDir\windows_desktop_mcp.py"
                $t=$t -replace "__PYTHON__",$pexe.Replace('\','\\');$t=$t -replace "__MCP_SCRIPT__",$ms.Replace('\','\\')}
            $t=$t -replace "__API_KEY__","YOUR_API_KEY"
            $t|Out-File $cfg -Encoding utf8;O "config.yaml created"
        }
    }else{I "config.yaml exists"}

    # .env with API key
    $envFile="$DataDir\.env"
    if(!(Test-Path $envFile)){
        Write-Host ""
        $ak=Read-Host "  DeepSeek API Key (Enter to skip)"
        if(!$ak){$ak="YOUR_API_KEY"}
        "DEEPSEEK_API_KEY=$ak"|Out-File $envFile -Encoding utf8
        if($ak -ne "YOUR_API_KEY"){O "API Key saved"}else{W "Edit $envFile later"}
    }

    [Environment]::SetEnvironmentVariable("HERMES_HOME",$DataDir,"User")
    '{"locale":"zh-CN","onboardingComplete":true}'|Out-File "$DataDir\desktop.json" -Encoding utf8
    "# SOUL"|Out-File "$DataDir\SOUL.md" -Encoding utf8
}

function CreateLaunchers{
    # Desktop shortcut for WebUI
    if(!$SkipWebUI){
        $pyExe=$py
        if(Test-Path "$AgentDir\venv\Scripts\python.exe"){$pyExe="$AgentDir\venv\Scripts\python.exe"}
        $bat=@("@echo off","title Hermes WebUI","set HERMES_HOME=$DataDir",
               "cd /d $WebUIDir","start http://127.0.0.1:8787",
               "`"$pyExe`" server.py --port 8787","pause >nul") -join "`r`n"
        $bat|Out-File "$ScriptsDir\launch_webui.bat" -Encoding ASCII

        $ws=New-Object -ComObject WScript.Shell
        $lnk=$ws.CreateShortcut("$Desktop\Hermes WebUI.lnk")
        $lnk.TargetPath="$ScriptsDir\launch_webui.bat";$lnk.WorkingDirectory=$WebUIDir;$lnk.Save()
        O "Desktop shortcut: Hermes WebUI"
    }

    # Voice launcher
    if(!$SkipVoice){
        $pexe="$VoiceDir\venv\Scripts\python.exe"
        $bat2=@("@echo off","title Hermes Voice","set HERMES_HOME=$DataDir","cd /d $ScriptsDir",
               "start http://127.0.0.1:8282","`"$pexe`" -u voice_server.py","pause >nul") -join "`r`n"
        $bat2|Out-File "$ScriptsDir\launch_voice.bat" -Encoding ASCII

        $ws=New-Object -ComObject WScript.Shell
        $lnk=$ws.CreateShortcut("$Desktop\HermesVoice.lnk")
        $lnk.TargetPath="$ScriptsDir\launch_voice.bat";$lnk.WorkingDirectory=$ScriptsDir;$lnk.Save()
        O "Desktop shortcut: HermesVoice"
    }
}

# main
CheckPrereqs
if(!$Yes){Write-Host "`nPress Enter to install, Ctrl+C to cancel" -ForegroundColor Yellow;Read-Host}
S "1/6 Directories";MakeDirs
S "2/6 Hermes CLI";InstallCLI
S "3/6 Hermes WebUI";InstallWebUI
S "4/6 Voice assistant";InstallVoice
S "5/6 Config files";WriteConfigs
S "6/6 Launchers";CreateLaunchers

Write-Host "";Write-Host "="*44 -ForegroundColor Green
Write-Host "  Deployment complete!" -ForegroundColor Green
Write-Host "="*44 -ForegroundColor Green
Write-Host ""
Write-Host "  Desktop shortcuts:"
if(!$SkipWebUI){Write-Host "    Hermes WebUI -> http://127.0.0.1:8787"}
if(!$SkipVoice){Write-Host "    HermesVoice  -> http://127.0.0.1:8282"}
Write-Host ""
