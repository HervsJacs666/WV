#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    printf '%b\n' "${YELLOW}Uso: $0 [--output FILE] <URL-del-sitio-web>${NC}" >&2
    exit 1
}

# CLI parsing: support --output|-o
OUTPUT=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            OUTPUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            break
            ;;
        -*|--*)
            printf '%b\n' "${RED}Opción desconocida: $1${NC}" >&2
            usage
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL[@]}"
if [ "$#" -lt 1 ]; then
    usage
fi

URL=$1
if [[ "$URL" != *"://"* ]]; then
    URL="http://$URL"
fi

# If OUTPUT was provided, tee all output into that file (append)
if [ -n "${OUTPUT}" ]; then
    # create parent dir as needed
    mkdir -p "$(dirname "$OUTPUT")" 2>/dev/null || true
    exec > >(tee -a "$OUTPUT") 2>&1
fi

# Comprobar herramientas necesarias
required_cmds=(curl ping awk grep sort uniq)
for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf '%b\n' "${RED}Falta el comando: $cmd. Instálalo e inténtalo de nuevo.${NC}" >&2
        exit 1
    fi
done

DOMAIN=$(echo "$URL" | awk -F[/:] '{print $4}')

printf '%b\n' "${YELLOW}Iniciando análisis completo para: ${URL}${NC}"

resolve_ip() {
    printf '%b\n' "${GREEN}Resolviendo dirección IP para el servidor...${NC}"
    # Try multiple ways to resolve an IP for portability (getent, dig, ping variations)
    if command -v pwsh >/dev/null 2>&1; then
        # Use PowerShell Test-Connection if available (Windows-native)
        IP=$(pwsh -NoProfile -Command "try{(Test-Connection -ComputerName '${DOMAIN}' -Count 1 -ErrorAction Stop).IPv4Address.IPAddressToString}catch{''}") || true
        if [ -n "${IP}" ]; then
            printf '%s\n' "$IP"
            return
        fi
    fi
    if command -v getent >/dev/null 2>&1; then
        getent hosts "$DOMAIN" | awk '{print $1; exit}' || printf 'N/A\n'
        return
    fi
    if command -v dig >/dev/null 2>&1; then
        dig +short "$DOMAIN" | head -n1 || printf 'N/A\n'
        return
    fi
    if ping -c 1 "$DOMAIN" >/dev/null 2>&1; then
        ping -c 1 "$DOMAIN" | grep PING | awk -F'[()]' '{print $2}' || printf 'N/A\n'
        return
    fi
    # Windows-like ping (uses -n) — parsing IPv4 from output
    if ping -n 1 "$DOMAIN" >/dev/null 2>&1; then
        ping -n 1 "$DOMAIN" | sed -n '1s/.*(\([0-9\.]*\)).*/\1/p' || printf 'N/A\n'
        return
    fi
    printf 'No se pudo resolver la IP para %s\n' "$DOMAIN"
}

show_http_headers() {
    printf '%b\n' "${GREEN}Cabeceras HTTP completas:${NC}"
    curl -k -sS -I --max-time 10 "$URL" || printf 'No se pudieron obtener cabeceras\n'
}

check_security_headers() {
    printf '%b\n' "${GREEN}Comprobando cabeceras de seguridad específicas...${NC}"
    curl -k -sS -I --max-time 10 "$URL" | grep -E 'X-Frame-Options|X-XSS-Protection|X-Content-Type-Options|Strict-Transport-Security|Content-Security-Policy' || printf 'No se encontraron cabeceras de seguridad específicas\n'
}

check_sensitive_files() {
    printf '%b\n' "${GREEN}Comprobando archivos/directorios sensibles...${NC}"
    FILES=("/.git/" "/.env" "/wp-config.php" "/phpinfo.php")
    for FILE in "${FILES[@]}"; do
        RESPONSE=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 10 "$URL$FILE" || echo "000")
        if [ "$RESPONSE" != "404" ] && [ "$RESPONSE" != "000" ]; then
            printf '%b\n' "${RED}Posible exposición en: $URL$FILE (HTTP $RESPONSE)${NC}"
        fi
    done
}

check_wordpress() {
    printf '%b\n' "${GREEN}Verificando si el sitio utiliza WordPress...${NC}"
    if curl -k -sS --max-time 10 "$URL" | grep -q "/wp-content/"; then
        printf '%b\n' "${GREEN}El sitio parece estar utilizando WordPress.${NC}"
    else
        printf '%b\n' "${YELLOW}No se encontraron indicios claros de WordPress.${NC}"
    fi
}

find_emails() {
    printf '%b\n' "${GREEN}Buscando correos electrónicos...${NC}"
    curl -k -sS --max-time 10 "$URL" | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,6}' | sort -u || true
}

find_phone_numbers() {
    printf '%b\n' "${GREEN}Buscando números de teléfono...${NC}"
    curl -k -sS --max-time 10 "$URL" | grep -oP '\\+?\\d{1,3}?[-.\\s]?\\(?\\d{1,3}\\)?[-.\\s]?\\d{1,4}[-.\\s]?\\d{1,4}[-.\\s]?\\d{1,4}' | sort -u || true
}

extract_links() {
    printf '%b\n' "${GREEN}Extrayendo enlaces de la página...${NC}"
    # extract raw hrefs
    RAW_LINKS=$(curl -k -sS --max-time 10 "$URL" | grep -oP '(?<=href=\")[^\"]*' || true)
    if [ -z "${RAW_LINKS}" ]; then
        return
    fi
    # Normalize links: if python3 available use urljoin, else try simple heuristics
    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
        PY=$(command -v python3 || command -v python)
        printf '%s\n' "$RAW_LINKS" | $PY -c "import sys; from urllib.parse import urljoin; base=sys.argv[1]; print('\n'.join([urljoin(base,l.strip()) for l in sys.stdin if l.strip()]))" "$URL" | sort -u
    else
        # Simple normalization: absolute URLs, protocol-relative, or join base
        printf '%s\n' "$RAW_LINKS" | while read -r L; do
            if [[ "$L" =~ ^https?:// ]]; then
                echo "$L"
            elif [[ "$L" =~ ^// ]]; then
                scheme=$(echo "$URL" | awk -F: '{print $1}')
                echo "$scheme:$L"
            elif [[ "$L" =~ ^/ ]]; then
                base=$(echo "$URL" | awk -F[/:] '{print $1"://"$4}')
                echo "$base$L"
            else
                # relative path
                base=$(echo "$URL" | sed 's#/*$##')
                echo "$base/$L"
            fi
        done | sort -u
    fi
}

resolve_ip
show_http_headers
check_security_headers
check_sensitive_files
check_wordpress
find_emails
find_phone_numbers
extract_links


