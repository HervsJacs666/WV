#!bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$#" -ne 1 ]; then
    echo -e "${RED}Uso: $0 <URL-del-sitio-web>${NC}"
    exit 1
fi

URL=$1
DOMAIN=$(echo $URL | awk -F[/:] '{print $4}')

echo -e "${YELLOW}Iniciando análisis completo para: ${URL}${NC}"

resolve_ip() {
    echo -e "${GREEN}Resolviendo dirección IP para el servidor...${NC}"
    ping -c 1 $DOMAIN | grep PING | awk -F'[()]' '{print $2}'
}

show_http_headers() {
    echo -e "${GREEN}Cabeceras HTTP completas:${NC}"
    curl -k -s -I "$URL"
}

check_security_headers() {
    echo -e "${GREEN}Comprobando cabeceras de seguridad específicas...${NC}"
    curl -k -s -I "$URL" | grep -E 'X-Frame-Options|X-XSS-Protection|X-Content-Type-Options|Strict-Transport-Security|Content-Security-Policy'
}

check_sensitive_files() {
    echo -e "${GREEN}Comprobando archivos/directorios sensibles...${NC}"
    FILES=("/.git/" "/.env" "/wp-config.php" "/phpinfo.php")
    for FILE in "${FILES[@]}"; do
        RESPONSE=$(curl -k -s -o /dev/null -w "%{http_code}" "$URL$FILE")
        if [ "$RESPONSE" != "404" ]; then
            echo -e "${RED}Posible exposición en: $URL$FILE${NC}"
        fi
    done
}

check_wordpress() {
    echo -e "${GREEN}Verificando si el sitio utiliza WordPress...${NC}"
    if curl -k -s "$URL" | grep -q "/wp-content/"; then
        echo -e "${GREEN}El sitio parece estar utilizando WordPress.${NC}"
    else
        echo -e "${RED}No se encontraron indicios de WordPress.${NC}"
    fi
}

find_emails() {
    echo -e "${GREEN}Buscando correos electrónicos...${NC}"
    curl -k -s "$URL" | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}' | sort | uniq
}

find_phone_numbers() {
    echo -e "${GREEN}Buscando números de teléfono...${NC}"
    curl -k -s "$URL" | grep -oP '\+?\d{1,3}?[-.\s]?\(?\d{1,3}\)?[-.\s]?\d{1,4}[-.\s]?\d{1,4}[-.\s]?\d{1,4}' | sort | uniq
}

extract_links() {
    echo -e "${GREEN}Extrayendo enlaces de la página...${NC}"
    curl -k -s "$URL" | grep -oP '(?<=href=")[^"]*' | sort | uniq
}

resolve_ip
show_http_headers
check_security_headers
check_sensitive_files
check_wordpress
find_emails
find_phone_numbers
extract_links

