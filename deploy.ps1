# ═══════════════════════════════════════════════════════════════════════
#  Deploy RRHH Adorno → GitHub Pages
#  Uso:  cd C:\CRM_Adorno\rrhh-adorno; .\deploy.ps1
#  Requiere: git, gh CLI (https://cli.github.com/)
# ═══════════════════════════════════════════════════════════════════════

$ErrorActionPreference = "Stop"
$RepoName = "rrhh-adorno"
$OrgName  = "claudiaadornosrl-prog"

Write-Host "🚀 Deploy RRHH Adorno → GitHub Pages" -ForegroundColor Cyan

# Verificar herramientas
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ git no está instalado." -ForegroundColor Red; exit 1
}

# Si no existe .git, inicializar
if (-not (Test-Path .git)) {
    Write-Host "📁 Inicializando repo..."
    git init
    git branch -M main
}

# Crear .gitignore si no existe
if (-not (Test-Path .gitignore)) {
    @'
# Migraciones — datos sensibles
migrations/*.csv
migrations/*.xlsx
.env
*.log

# Sistema
.DS_Store
Thumbs.db
desktop.ini
'@ | Out-File -Encoding utf8 .gitignore
}

# Add + commit
git add .
$status = git status --porcelain
if (-not $status) {
    Write-Host "✅ Nada para commitear." -ForegroundColor Green
} else {
    $msg = Read-Host "Mensaje de commit (Enter para usar 'update')"
    if (-not $msg) { $msg = "update" }
    git commit -m $msg
}

# Verificar remote
$remote = git remote -v 2>$null
if (-not $remote) {
    Write-Host ""
    Write-Host "⚠️  No hay remote configurado." -ForegroundColor Yellow
    Write-Host "    Tenés dos opciones:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    A) Crear el repo nuevo con gh CLI:" -ForegroundColor Cyan
    Write-Host "       gh repo create $OrgName/$RepoName --public --source=. --push" -ForegroundColor White
    Write-Host ""
    Write-Host "    B) Si ya lo creaste por la web:" -ForegroundColor Cyan
    Write-Host "       git remote add origin https://github.com/$OrgName/$RepoName.git" -ForegroundColor White
    Write-Host "       git push -u origin main" -ForegroundColor White
    Write-Host ""
    Write-Host "    Después activá GitHub Pages en Settings → Pages → Branch main / root" -ForegroundColor Cyan
    exit 0
}

# Push
Write-Host "📤 Pusheando..."
git push origin main

Write-Host ""
Write-Host "✅ Deploy OK." -ForegroundColor Green
Write-Host "🌐 https://$OrgName.github.io/$RepoName/" -ForegroundColor Cyan
Write-Host "   (puede tardar 1-2 min en actualizar GitHub Pages)" -ForegroundColor Gray
