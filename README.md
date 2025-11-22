# WV - Scripts de análisis web

Contenido:
- `w.sh`: Script Bash para análisis básico de un sitio web (cabeceras, archivos sensibles, extracción de emails/teléfonos/enlaces, comprobación de WordPress).
- `w.ps1`: Versión PowerShell para ejecutar en `pwsh`/PowerShell en Windows.
- `w.ps1`: Versión PowerShell para ejecutar en `pwsh`/PowerShell en Windows.

Requisitos
- `curl`, `ping`, `awk`, `grep`, `sort`, `uniq` (para `w.sh`).
- PowerShell (o `pwsh`) para `w.ps1`.
- Opcional: `shellcheck` para validar `w.sh`.

Opciones adicionales
- `--output, -o FILE` (en `w.sh`): guarda la salida en `FILE` (se añade al final si ya existe).

Uso
- Bash (Git Bash / WSL / macOS / Linux):

```bash
bash ./w.sh https://example.com
```

- PowerShell (pwsh):

```powershell
pwsh .\w.ps1 -Url 'https://example.com'
```

Instalación de ShellCheck (opciones)
- Scoop (recomendado en Windows):

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
iex (iwr -useb get.scoop.sh)
scoop install shellcheck
```

- Chocolatey:

```powershell
choco install shellcheck -y
```

- Debian/Ubuntu (WSL):

```bash
sudo apt update
sudo apt install shellcheck
```

Notas
- `w.sh` intenta resolver IPs con `getent`, `dig`, o `ping` y tiene una caída compatible con la sintaxis de `ping` de Windows.
 - `w.sh` intenta resolver IPs con `pwsh`/`Test-Connection` (si `pwsh` está presente), `getent`, `dig`, o `ping` y tiene una caída compatible con la sintaxis de `ping` de Windows.
- Estos scripts hacen peticiones HTTP contra la URL proporcionada; úsalos solo contra objetivos que tengas permiso para analizar.

Licencia
- Sin licencia específica; modifica según tus necesidades.
