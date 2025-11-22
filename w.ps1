<#
  w.ps1 - Versión PowerShell del script de análisis web.
  Uso: pwsh ./w.ps1 -Url https://example.com
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Url
)

if ($Url -notmatch '://') { $Url = "http://$Url" }

Write-Host "Iniciando análisis completo para: $Url" -ForegroundColor Yellow

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Error "Falta el comando: $Name"
        exit 1
    }
}

# Comprobar que Invoke-WebRequest está disponible (PowerShell / pwsh)
# En PowerShell Core viene integrado; en Windows PowerShell 5 puede necesitar ciertos módulos.

$uri = [uri]$Url

function Resolve-IP {
    Write-Host "Resolviendo dirección IP para el servidor..." -ForegroundColor Green
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($uri.Host) | ForEach-Object { $_.IPAddressToString }
        $addresses -join ', '
    } catch {
        Write-Warning "No se pudo resolver el host: $($_.Exception.Message)"
    }
}

function Show-HttpHeaders {
    Write-Host "Cabeceras HTTP completas:" -ForegroundColor Green
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Head -ErrorAction Stop -UseBasicParsing
        $resp.Headers
    } catch {
        Write-Warning "No se pudieron obtener cabeceras: $($_.Exception.Message)"
    }
}

function Check-SecurityHeaders {
    Write-Host "Comprobando cabeceras de seguridad específicas..." -ForegroundColor Green
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Head -ErrorAction Stop -UseBasicParsing
        $headersToCheck = 'X-Frame-Options','X-XSS-Protection','X-Content-Type-Options','Strict-Transport-Security','Content-Security-Policy'
        foreach ($h in $headersToCheck) {
            if ($resp.Headers.$h) { "$h : $($resp.Headers.$h)" } else { "$h : (no presente)" }
        }
    } catch {
        Write-Warning "No se pudieron comprobar cabeceras: $($_.Exception.Message)"
    }
}

function Check-SensitiveFiles {
    Write-Host "Comprobando archivos/directorios sensibles..." -ForegroundColor Green
    $files = '/.git/','/.env','/wp-config.php','/phpinfo.php'
    foreach ($f in $files) {
        try {
            $r = Invoke-WebRequest -Uri ($Url.TrimEnd('/') + $f) -Method Head -ErrorAction Stop
            Write-Host "Posible exposición en: $($Url.TrimEnd('/') + $f) (HTTP $($r.StatusCode))" -ForegroundColor Red
        } catch [System.Net.WebException] {
            $resp = $_.Exception.Response
            if ($resp -and $resp.StatusCode) {
                if ($resp.StatusCode -ne 404) {
                    Write-Host "Posible exposición en: $($Url.TrimEnd('/') + $f) (HTTP $($resp.StatusCode))" -ForegroundColor Red
                }
            }
        } catch {
            # ignore other errors
        }
    }
}

function Check-WordPress {
    Write-Host "Verificando si el sitio utiliza WordPress..." -ForegroundColor Green
    try {
        $content = Invoke-WebRequest -Uri $Url -ErrorAction Stop -UseBasicParsing
        if ($content.Content -match '/wp-content/') { Write-Host 'El sitio parece estar utilizando WordPress.' -ForegroundColor Green }
        else { Write-Host 'No se encontraron indicios claros de WordPress.' -ForegroundColor Yellow }
    } catch {
        Write-Warning "No se pudo comprobar WordPress: $($_.Exception.Message)"
    }
}

function Find-Emails {
    Write-Host "Buscando correos electrónicos..." -ForegroundColor Green
    try {
        $c = (Invoke-WebRequest -Uri $Url -ErrorAction Stop -UseBasicParsing).Content
        [regex]::Matches($c, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}') | ForEach-Object { $_.Value } | Sort-Object -Unique
    } catch {
        Write-Warning "No se pudieron buscar correos: $($_.Exception.Message)"
    }
}

function Find-PhoneNumbers {
    Write-Host "Buscando números de teléfono..." -ForegroundColor Green
    try {
        $c = (Invoke-WebRequest -Uri $Url -ErrorAction Stop -UseBasicParsing).Content
        [regex]::Matches($c, '\+?\d{1,3}?[-.\s]?\(?\d{1,3}\)?[-.\s]?\d{1,4}[-.\s]?\d{1,4}[-.\s]?\d{1,4}') | ForEach-Object { $_.Value } | Sort-Object -Unique
    } catch {
        Write-Warning "No se pudieron buscar teléfonos: $($_.Exception.Message)"
    }
}

function Extract-Links {
    Write-Host "Extrayendo enlaces de la página..." -ForegroundColor Green
    try {
        $c = (Invoke-WebRequest -Uri $Url -ErrorAction Stop -UseBasicParsing).Content
        [regex]::Matches($c, '(?<=href\=")[^"]*') | ForEach-Object { $_.Value } | Sort-Object -Unique
    } catch {
        Write-Warning "No se pudieron extraer enlaces: $($_.Exception.Message)"
    }
}

Resolve-IP
Show-HttpHeaders
Check-SecurityHeaders
Check-SensitiveFiles
Check-WordPress
Find-Emails
Find-PhoneNumbers
Extract-Links
