#!/bin/bash
set -e

# Evo API SetupX - Instalación guiada de Evolution API en una sola pasada
# - Instala Docker y Compose si faltan
# - Despliega Evolution API + Postgres + Redis (opcional)
# - Configura NGINX + SSL con Certbot (opcional)
# - Muestra resumen y pasos finales

# Colores y helpers visuales
GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[34m"; RED="\033[31m"; BOLD="\033[1m"; RESET="\033[0m"
info(){ echo -e "${BLUE}➜${RESET} $*"; }
ok(){ echo -e "${GREEN}✔${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
err(){ echo -e "${RED}✖${RESET} $*"; }

banner(){ echo -e "\n${BOLD}${BLUE}==== $* ====${RESET}\n"; }

# Privilegios
if [ "$EUID" -ne 0 ]; then SUDO="sudo"; else SUDO=""; fi

# Detectar distro
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO_ID=${ID:-debian}
  DISTRO_LIKE=${ID_LIKE:-debian}
  DISTRO_CODE=${VERSION_CODENAME:-bookworm}
else
  DISTRO_ID=debian; DISTRO_LIKE=debian; DISTRO_CODE=bookworm
fi

banner "Comprobaciones iniciales"
info "Distro: ${DISTRO_ID} (${DISTRO_CODE})"
info "SUDO: ${SUDO:+sí }"

prompt(){ local label="$1"; local default="$2"; local var;
  read -r -p "${label} [${default}]: " var; echo "${var:-$default}"; }

yn(){ local label="$1"; local default="$2"; local var;
  read -r -p "${label} (y/n) [${default}]: " var; var="${var:-$default}";
  case "$var" in y|Y) return 0;; *) return 1;; esac }

banner "Instalar Docker y Compose si faltan"
# Comprobación de Docker
if command -v docker >/dev/null 2>&1; then
  ok "Docker ya instalado"
else
  info "Instalando Docker..."
  $SUDO apt update -y
  $SUDO apt install -y docker.io
  $SUDO systemctl start docker
  $SUDO systemctl enable docker
  ok "Docker instalado"
fi

# Comprobación de Docker Compose (plugin o clásico)
if docker compose version >/dev/null 2>&1; then
  ok "Docker Compose ya disponible (plugin)"
  DC_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  ok "Docker Compose ya disponible (binario docker-compose)"
  DC_CMD="docker-compose"
else
  info "Instalando Docker Compose plugin..."
  $SUDO apt update -y
  $SUDO apt install -y ca-certificates curl gnupg
  $SUDO install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/${DISTRO_ID}/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO_ID} ${DISTRO_CODE} stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
  $SUDO apt update -y
  $SUDO apt install -y docker-compose-plugin
  ok "Docker Compose plugin instalado"
  DC_CMD="docker compose"
fi

banner "Parámetros de despliegue"
PROJECT_DIR=$(prompt "Carpeta del proyecto" "evolution_project")
AUTH_KEY=$(prompt "AUTHENTICATION_API_KEY" "change-password")

# Selección de base de datos y caché
yn "¿Desplegar Postgres y Redis con Docker (recomendado)?" "y"
if [ $? -eq 0 ]; then
  USE_LOCAL_DB=1
  PG_USER=$(prompt "Usuario Postgres" "myuser")
  PG_PASS=$(prompt "Password Postgres" "mypassword")
  PG_DB=$(prompt "Base de datos Postgres" "evolution")
  DB_URI="postgresql://${PG_USER}:${PG_PASS}@postgres:5432/${PG_DB}"
  REDIS_URI="redis://redis:6379/0"
else
  USE_LOCAL_DB=0
  DB_URI=$(prompt "DATABASE_CONNECTION_URI" "postgresql://user:pass@host:5432/db")
  REDIS_URI=$(prompt "CACHE_REDIS_URI" "redis://host:6379/0")
fi

# Configuración opcional de NGINX + SSL
yn "¿Configurar NGINX + SSL con Certbot?" "y"
if [ $? -eq 0 ]; then
  WANT_SSL=1
  DOMAIN=$(prompt "Subdominio para HTTPS" "api.midominio.com")
  EMAIL=$(prompt "Email para Certbot" "admin@midominio.com")
else
  WANT_SSL=0
  DOMAIN=""
fi

banner "Preparar estructura y archivos"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

cat > .env <<EOF
CONFIG_SESSION_PHONE_VERSION=2.3000.1023204200
AUTHENTICATION_API_KEY=${AUTH_KEY}

DATABASE_ENABLED=true
DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=${DB_URI}

CACHE_REDIS_ENABLED=true
CACHE_REDIS_URI=${REDIS_URI}
CACHE_REDIS_PREFIX_KEY=evolution
CACHE_REDIS_SAVE_INSTANCES=false
CACHE_LOCAL_ENABLED=false
EOF
ok ".env creado"

cat > docker-compose.yml <<EOF
services:
  evolution_api:
    container_name: evolution_api
    image: atendai/evolution-api:latest
    restart: always
    ports:
      - "8080:8080"
    env_file:
      - .env
    depends_on:
      - postgres
      - redis
    volumes:
      - evolution_instances:/evolution/instances

  postgres:
    image: postgres:15
    restart: always
    environment:
      POSTGRES_USER: ${PG_USER:-myuser}
      POSTGRES_PASSWORD: ${PG_PASS:-mypassword}
      POSTGRES_DB: ${PG_DB:-evolution}
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:7
    restart: always

volumes:
  evolution_instances:
  pgdata:
EOF
ok "docker-compose.yml creado"

banner "Limpiar y levantar stack"
$SUDO $DC_CMD down -v || true
$SUDO docker volume prune -f || true
$SUDO $DC_CMD up -d
ok "Stack iniciado"

sleep 3
$SUDO $DC_CMD ps

info "Logs iniciales (puedes salir con Ctrl+C):"
$SUDO docker logs -f evolution_api || true

if [ "$WANT_SSL" = "1" ]; then
  banner "Configurar NGINX + SSL"
  $SUDO apt update -y
  $SUDO apt install -y nginx certbot python3-certbot-nginx

  $SUDO tee /etc/nginx/sites-available/evolution_api > /dev/null <<NGINX
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINX

  $SUDO ln -sf /etc/nginx/sites-available/evolution_api /etc/nginx/sites-enabled/evolution_api
  $SUDO nginx -t && $SUDO systemctl reload nginx

  info "Solicitando certificado con Certbot..."
  $SUDO certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos --redirect --non-interactive || warn "Certbot interactivo puede requerir verificación manual"

  $SUDO nginx -t && $SUDO systemctl reload nginx
  ok "NGINX + SSL configurado"
fi

banner "Resumen y siguientes pasos"
if [ -n "$DOMAIN" ]; then
  echo -e "URL segura: ${BOLD}https://${DOMAIN}${RESET}"
else
  echo -e "Acceso local (VM): ${BOLD}http://localhost:8080${RESET}"
fi

echo -e "Contraseña Manager (AUTHENTICATION_API_KEY): ${BOLD}${AUTH_KEY}${RESET}"

echo -e "\nEjemplo de envío (ajusta ruta según tu versión):"
cat <<EXAMPLE
curl -X POST "https://${DOMAIN:-TU_DOMINIO.com}/<ruta_envio_texto>" \\
  -H "apiKey: ${AUTH_KEY}" \\
  -H "Content-Type: application/json" \\
  -d '{
        "number": "<CHAT_ID>",
        "text": "Hola desde API"
      }'
EXAMPLE

cat <<N8N

n8n (webhook):
- Crea nodo Webhook (POST). Copia la URL de prueba.
- En Evolution API → Eventos → Webhook, pega la URL y activa.
- Activa evento de mensajes (e.g., message:received).
- Al activar el workflow en n8n, cambia la URL a producción.
N8N

ok "SetupX completado"
