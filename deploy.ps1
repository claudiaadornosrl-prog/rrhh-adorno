# ====================================================================
#  Deploy RRHH Adorno -> GitHub Pages
#  Uso:  cd C:\CRM_Adorno\rrhh-adorno; .\deploy.ps1
#  Requiere: git
#  Opcional: gh CLI (https://cli.github.com/) para crear repo
# ====================================================================

$ErrorActionPreference = "Stop"
$RepoName = "rrhh-adorno"
$OrgName  = "claudiaadornosrl-prog"

Write-Host "Deploy RRHH Adorno -> GitHub Pages" -ForegroundColor Cyan

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: git no esta instalado." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path .git)) {
    Write-Host "Inicializando repo..."
    git init
    git branch -M main
}

if (-not (Test-Path .gitignore)) {
@'
migrations/*.csv
migrations/*.xlsx
.env
*.log
.DS_Store
Thumbs.db
desktop.ini
'@ | Out-File -Encoding utf8 .gitignore
}

git add .
$status = git status --porcelain
if (-not $status) {
    Write-Host "Nada para commitear." -ForegroundColor Green
} else {
    $msg = Read-Host "Mensaje de commit (Enter para usar default)"
    if (-not $msg) { $msg = "update" }
    git commit -m $msg
}

$remote = git remote -v 2>$null
if (-not $remote) {
    Write-Host ""
    Write-Host "No hay remote configurado." -ForegroundColor Yellow
    Write-Host "Opciones:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  A) Con gh CLI:" -ForegroundColor Cyan
    Write-Host "     gh repo create $OrgName/$RepoName --public --source=. --push" -ForegroundColor White
    Write-Host ""
    Write-Host "  B) Si ya creaste el repo por la web:" -ForegroundColor Cyan
    Write-Host "     git remote add origin https://github.com/$OrgName/$RepoName.git" -ForegroundColor White
    Write-Host "     git push -u origin main" -ForegroundColor White
    Write-Host ""
    Write-Host "Despues activar GitHub Pages en Settings -> Pages -> Branch main / root" -ForegroundColor Cyan
    exit 0
}

Write-Host "Pusheando..."
git push origin main

Write-Host ""
Write-Host "Deploy OK." -ForegroundColor Green
Write-Host "URL: https://$OrgName.github.io/$RepoName/" -ForegroundColor Cyan
Write-Host "(puede tardar 1-2 min en GitHub Pages)" -ForegroundColor Gray
