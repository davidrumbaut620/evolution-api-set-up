# Guía de despliegue de Evolution API (Google Cloud + Dominio + n8n)

Esta guía te explica, paso a paso y con comandos, cómo:
- Ejecutar el SetupX remoto por URL (recomendado)
- Instalar Docker y Docker Compose en tu VM
- Desplegar Evolution API con Postgres y Redis (Docker)
- Configurar DNS y certificar tu dominio con NGINX + Certbot
- Acceder al Manager y crear tu instancia
- Conectar Evolution API con n8n (webhook de prueba y producción)

## Requisitos
- VM Linux (Debian/Ubuntu) con IP pública y puertos `80/443/8080` abiertos.
- Dominio propio (ej. `api.midominio.com`) apuntando a la IP de la VM.
- n8n instalado (opcional pero recomendado).

## 1) Ejecutar SetupX por URL (recomendado)
Ejecuta en tu VM:
```
# Con curl
curl -fsSL "https://fivel.ink/evo-api-setupx-sh" | bash

# Alternativa con wget
wget -qO- "https://fivel.ink/evo-api-setupx-sh" | bash
```
El SetupX te guiará paso a paso: creará `.env` y `docker-compose.yml`, levantará Evolution API, y opcionalmente configurará NGINX + SSL con Certbot.

Si prefieres el método manual, sigue los pasos 2–7.

## 2) Instalar Docker y Docker Compose (manual)
Ejecuta en la VM (Debian/Ubuntu):
```
bash setup_docker.sh
```
Verifica:
```
docker --version
docker compose version
```

## 3) Desplegar Evolution API (manual)
Edita primero tu clave de acceso en `.env`:
```
AUTHENTICATION_API_KEY=tu-clave-fuerte-aqui
```
Opcional: ajusta credenciales de Postgres en `.env` y `docker-compose.yml`.

Inicia el stack:
```
bash setup_evolution_api.sh
```
Comprueba que corre en `8080`:
```
sudo docker compose ps
sudo docker logs -f evolution_api
```

## 4) Configurar DNS
Crea un registro `A` para tu subdominio (ej. `api.midominio.com`) apuntando a la IP pública de la VM.

## 5) Certificar el dominio (NGINX + Certbot)
Reemplaza `TU_DOMINIO.com` en `certify_domain.sh` por tu subdominio. Luego ejecuta:
```
bash certify_domain.sh
```
Esto configura NGINX como proxy inverso hacia `http://localhost:8080` y aplica SSL válido.

Prueba acceso:
```
https://TU_DOMINIO.com
```

## 6) Acceso al Manager y configuración
- Entra a `https://TU_DOMINIO.com` y usa `AUTHENTICATION_API_KEY` como contraseña.
- Crea una instancia y ajusta opciones (rechazar llamadas, ignorar grupos, etc.).
- Genera el QR y vincula tu WhatsApp.

## 7) Conectar Evolution API con n8n (webhook)
- En n8n, crea un nodo `Webhook` con método `POST`.
- Copia la URL de prueba del webhook en Evolution API → Eventos → Webhook y actívalo.
- Activa el evento de mensajes (ej. `message:received`).
- Prueba enviando un mensaje; verifica que llega a n8n.
- Cuando actives el workflow en n8n, cambia la URL del webhook en Evolution API a la de producción.

## 8) Enviar mensajes vía API (ejemplo genérico)
Usa tu `Server URL` (dominio), `API Key`, `instance` y `chatId`. Ejemplo:
```
curl -X POST "https://TU_DOMINIO.com/<ruta_envio_texto>" \
  -H "apiKey: TU_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
        "number": "<CHAT_ID>",
        "text": "Hola desde API"
      }'
```
Consulta la documentación/colección Postman de Evolution API para la ruta exacta acorde a tu versión.

## Consejos y verificación
- Asegura que la VM no cambie de IP (modo estándar) si usas IP dinámica.
- `nginx -t` y `sudo systemctl reload nginx` para validar/recargar NGINX.
- Si algo falla, revisa `sudo docker logs -f evolution_api`.
