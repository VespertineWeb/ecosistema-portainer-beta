#!/bin/bash

# Cores
GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
BLUE='\e[34m'
WHITE='\e[97m'
ORANGE='\e[38;5;208m'
NC='\e[0m'

# Configurações de segurança
LOG_FILE="$HOME/portainer-install.log"
DOCKER_GPG_KEY="/usr/share/keyrings/docker-archive-keyring.gpg"

# Variáveis para portas (padrão)
TRAEFIK_HTTP_PORT="80"
TRAEFIK_HTTPS_PORT="443"

# Função para logging
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Função para mostrar spinner de carregamento
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Função para validar domínios
validate_domain() {
    local domain=$1
    # Regex para validar formato de domínio
    if [[ ! $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo -e "${RED}❌ Domínio inválido: $domain${NC}"
        return 1
    fi
    
    # Verificar se o domínio não está vazio
    if [ -z "$domain" ]; then
        echo -e "${RED}❌ Domínio não pode estar vazio${NC}"
        return 1
    fi
    
    return 0
}

# Função para lidar com conflitos de porta
handle_port_conflicts() {
    echo -e "${YELLOW}🔍 Detectando serviços em conflito...${NC}"
    
    local services_to_stop=()
    
    # Detectar Apache
    if systemctl is-active --quiet apache2; then
        services_to_stop+=("apache2")
    fi
    
    # Detectar Nginx
    if systemctl is-active --quiet nginx; then
        services_to_stop+=("nginx")
    fi
    
    # Detectar outros serviços web comuns
    for service in lighttpd caddy httpd; do
        if systemctl is-active --quiet $service; then
            services_to_stop+=($service)
        fi
    done
    
    if [ ${#services_to_stop[@]} -gt 0 ]; then
        echo -e "${YELLOW}Serviços detectados que podem causar conflito: ${services_to_stop[*]}${NC}"
        echo -e "${RED}⚠️  ATENÇÃO: Isso irá parar os serviços listados acima!${NC}"
        read -p "Deseja continuar e parar estes serviços? (y/n): " confirm_stop
        
        if [ "$confirm_stop" == "y" ]; then
            for service in "${services_to_stop[@]}"; do
                echo -e "${YELLOW}Parando $service...${NC}"
                sudo systemctl stop $service
                sudo systemctl disable $service
                log_message "Serviço $service parado e desabilitado"
            done
            echo -e "${GREEN}✅ Conflitos resolvidos, usando portas padrão (80/443)${NC}"
            TRAEFIK_HTTP_PORT="80"
            TRAEFIK_HTTPS_PORT="443"
        else
            echo -e "${YELLOW}Configurando portas alternativas...${NC}"
            configure_alternative_ports
        fi
    else
        echo -e "${YELLOW}Nenhum serviço web comum detectado${NC}"
        echo -e "${YELLOW}Algo mais pode estar usando as portas 80/443${NC}"
        configure_alternative_ports
    fi
}

# Função para configurar portas alternativas
configure_alternative_ports() {
    echo -e "${BLUE}📝 Configurando portas alternativas para Traefik${NC}"
    echo ""
    
    # Sugerir portas alternativas comuns
    local alt_http_ports=(8080 8081 3000 3001)
    local alt_https_ports=(8443 8444 9443 9444)
    
    echo -e "${YELLOW}Portas HTTP sugeridas: ${alt_http_ports[*]}${NC}"
    while true; do
        read -p "🌐 Porta HTTP para Traefik (padrão: 8080): " custom_http_port
        custom_http_port=${custom_http_port:-8080}
        
        if [[ $custom_http_port =~ ^[0-9]+$ ]] && [ $custom_http_port -ge 1024 ] && [ $custom_http_port -le 65535 ]; then
            if ! ss -tuln | grep -q ":$custom_http_port "; then
                TRAEFIK_HTTP_PORT="$custom_http_port"
                break
            else
                echo -e "${RED}❌ Porta $custom_http_port já está em uso${NC}"
            fi
        else
            echo -e "${RED}❌ Porta inválida. Use um número entre 1024-65535${NC}"
        fi
    done
    
    echo -e "${YELLOW}Portas HTTPS sugeridas: ${alt_https_ports[*]}${NC}"
    while true; do
        read -p "🔒 Porta HTTPS para Traefik (padrão: 8443): " custom_https_port
        custom_https_port=${custom_https_port:-8443}
        
        if [[ $custom_https_port =~ ^[0-9]+$ ]] && [ $custom_https_port -ge 1024 ] && [ $custom_https_port -le 65535 ]; then
            if ! ss -tuln | grep -q ":$custom_https_port " && [ $custom_https_port != $TRAEFIK_HTTP_PORT ]; then
                TRAEFIK_HTTPS_PORT="$custom_https_port"
                break
            else
                if [ $custom_https_port == $TRAEFIK_HTTP_PORT ]; then
                    echo -e "${RED}❌ Porta HTTPS não pode ser igual à porta HTTP${NC}"
                else
                    echo -e "${RED}❌ Porta $custom_https_port já está em uso${NC}"
                fi
            fi
        else
            echo -e "${RED}❌ Porta inválida. Use um número entre 1024-65535${NC}"
        fi
    done
    
    echo -e "${GREEN}✅ Portas configuradas: HTTP=$TRAEFIK_HTTP_PORT, HTTPS=$TRAEFIK_HTTPS_PORT${NC}"
    echo -e "${YELLOW}⚠️  Importante: Você precisará acessar os serviços com as novas portas:${NC}"
    echo -e "${YELLOW}   - HTTP: http://seudominio.com:$TRAEFIK_HTTP_PORT${NC}"
    echo -e "${YELLOW}   - HTTPS: https://seudominio.com:$TRAEFIK_HTTPS_PORT${NC}"
    log_message "Portas alternativas configuradas: HTTP=$TRAEFIK_HTTP_PORT, HTTPS=$TRAEFIK_HTTPS_PORT"
}

# Função para verificar DNS
check_dns() {
    local domain=$1
    log_message "Verificando DNS para $domain"
    
    if command -v nslookup &> /dev/null; then
        if ! nslookup "$domain" > /dev/null 2>&1; then
            echo -e "${YELLOW}⚠️  Aviso: Domínio $domain não resolve. Verifique suas configurações de DNS${NC}"
            log_message "AVISO: DNS não resolve para $domain"
        fi
    else
        echo -e "${YELLOW}⚠️  nslookup não disponível, pulando verificação de DNS${NC}"
    fi
}

# Função para validar email
validate_email() {
    local email=$1
    if [[ ! $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}❌ E-mail inválido: $email${NC}"
        return 1
    fi
    return 0
}

# Função para gerar hash de senha seguro
generate_password_hash() {
    local password=$1
    local username=${2:-"admin"}
    
    if command -v htpasswd &> /dev/null; then
        htpasswd -nbB "$username" "$password" 2>/dev/null | cut -d: -f2
    else
        # Fallback usando openssl
        echo "$password" | openssl passwd -apr1 -stdin 2>/dev/null
    fi
}

# Função para verificar requisitos do sistema
check_system_requirements() {
    log_message "Verificando requisitos do sistema"
    echo -e "${ORANGE}Verificando requisitos do sistema...${NC}"
    
    # Verificar distribuição Linux
    if [ ! -f /etc/os-release ]; then
        echo -e "${RED}❌ Sistema operacional não suportado${NC}"
        return 1
    fi
    
    # Verificar espaço em disco (em GB)
    local free_space=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$free_space" -lt 20 ]; then
        echo -e "${RED}❌ Erro: Espaço em disco insuficiente. Mínimo requerido: 20GB${NC}"
        log_message "ERRO: Espaço insuficiente - $free_space GB disponível"
        return 1
    fi
    
    # Verificar memória RAM
    local total_mem=$(free -g | awk 'NR==2 {print $2}')
    if [ $total_mem -lt 4 ]; then
        echo -e "${RED}❌ Erro: Memória RAM insuficiente. Mínimo requerido: 4GB${NC}"
        log_message "ERRO: RAM insuficiente - ${total_mem}GB disponível"
        return 1
    fi
    
    # Verificar se portas estão livres
    local required_ports=(8000 9000 5678)
    local web_ports=(80 443)
    local ports_in_use=()
    
    # Verificar portas dos serviços (obrigatórias)
    for port in "${required_ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            echo -e "${RED}❌ Erro: Porta $port já está em uso${NC}"
            log_message "ERRO: Porta $port em uso"
            return 1
        fi
    done
    
    # Verificar portas web (podem ser alteradas)
    for port in "${web_ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            ports_in_use+=($port)
        fi
    done
    
    # Se portas web estão em uso, oferecer alternativas
    if [ ${#ports_in_use[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Portas web em uso: ${ports_in_use[*]}${NC}"
        echo -e "${YELLOW}Isso pode indicar que Apache/Nginx já está rodando${NC}"
        echo ""
        echo -e "${BLUE}Opções disponíveis:${NC}"
        echo -e "${YELLOW}1) Parar serviços conflitantes e usar portas padrão (80/443)${NC}"
        echo -e "${YELLOW}2) Usar portas alternativas para Traefik${NC}"
        echo -e "${YELLOW}3) Cancelar instalação${NC}"
        read -p "Escolha (1-3): " port_choice
        
        case $port_choice in
            1)
                handle_port_conflicts
                ;;
            2)
                configure_alternative_ports
                ;;
            3)
                echo -e "${RED}❌ Instalação cancelada devido a conflitos de porta${NC}"
                log_message "Instalação cancelada - conflitos de porta"
                return 1
                ;;
            *)
                echo -e "${RED}❌ Opção inválida${NC}"
                return 1
                ;;
        esac
    fi
    
    echo -e "${GREEN}✅ Requisitos do sistema atendidos${NC}"
    log_message "Requisitos do sistema verificados com sucesso"
    return 0
}

# Função para detectar e instalar Docker
install_docker_secure() {
    log_message "Iniciando instalação segura do Docker"
    
    # Verificar se Docker já está instalado
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version 2>/dev/null)
        echo -e "${GREEN}✅ Docker já está instalado: $docker_version${NC}"
        log_message "Docker já instalado, pulando instalação"
        return 0
    fi
    
    # Verificar se Podman está instalado (alternativa)
    if command -v podman &> /dev/null; then
        echo -e "${YELLOW}🔍 Podman detectado. Deseja usar Podman em vez do Docker? (y/n)${NC}"
        read -p "Resposta: " use_podman
        if [ "$use_podman" == "y" ]; then
            install_podman_alternative
            return $?
        fi
    fi
    
    echo -e "${BLUE}Selecione a versão do Docker:${NC}"
    echo -e "${YELLOW}1) Docker CE (Community Edition) - Gratuito [Recomendado]${NC}"
    echo -e "${YELLOW}2) Usar Podman (alternativa segura)${NC}"
    echo -e "${YELLOW}3) Instalar manualmente mais tarde${NC}"
    read -p "Escolha (1-3): " docker_choice
    
    case $docker_choice in
        1)
            echo -e "${YELLOW}🐳 Instalando Docker CE (Community Edition)...${NC}"
            install_docker_ce
            ;;
        2)
            echo -e "${YELLOW}🐳 Instalando Podman...${NC}"
            install_podman_alternative
            ;;
        3)
            echo -e "${YELLOW}⚠️  Você precisará instalar Docker manualmente antes de continuar${NC}"
            echo -e "${YELLOW}Visite: https://docs.docker.com/engine/install/ubuntu/${NC}"
            exit 1
            ;;
        *)
            echo -e "${RED}❌ Opção inválida. Instalando Docker CE por padrão...${NC}"
            install_docker_ce
            ;;
    esac
}

# Função para instalar Docker CE
install_docker_ce() {
    
    # Atualizar repositórios
    (sudo apt-get update -y) > /dev/null 2>&1 &
    spinner $!
    
    # Instalar dependências
    echo -e "${YELLOW}📦 Instalando dependências...${NC}"
    (sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apache2-utils) > /dev/null 2>&1 &
    spinner $!
    
    # Adicionar chave GPG oficial do Docker
    echo -e "${YELLOW}🔐 Adicionando chave GPG do Docker...${NC}"
    if [ ! -f "$DOCKER_GPG_KEY" ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o "$DOCKER_GPG_KEY"
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Erro ao baixar chave GPG do Docker${NC}"
            log_message "ERRO: Falha ao baixar chave GPG"
            return 1
        fi
    fi
    
    # Adicionar repositório do Docker
    echo -e "${YELLOW}📝 Configurando repositório do Docker...${NC}"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$DOCKER_GPG_KEY] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Atualizar repositórios novamente
    (sudo apt-get update -y) > /dev/null 2>&1 &
    spinner $!
    
    # Instalar Docker
    echo -e "${YELLOW}🚀 Instalando Docker Engine...${NC}"
    (sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin) > /dev/null 2>&1 &
    spinner $!
    
    # Verificar instalação
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Erro na instalação do Docker${NC}"
        log_message "ERRO: Docker não foi instalado corretamente"
        return 1
    fi
    
    # Adicionar usuário ao grupo docker
    sudo usermod -aG docker $USER
    
    echo -e "${GREEN}✅ Docker CE instalado com sucesso${NC}"
    log_message "Docker CE instalado com sucesso"
    return 0
}

# Função para instalar Podman como alternativa
install_podman_alternative() {
    log_message "Instalando Podman como alternativa ao Docker"
    
    # Atualizar repositórios
    (sudo apt-get update -y) > /dev/null 2>&1 &
    spinner $!
    
    # Instalar Podman
    (sudo apt-get install -y podman podman-compose) > /dev/null 2>&1 &
    spinner $!
    
    # Verificar instalação
    if ! command -v podman &> /dev/null; then
        echo -e "${RED}❌ Erro na instalação do Podman${NC}"
        log_message "ERRO: Podman não foi instalado corretamente"
        return 1
    fi
    
    # Configurar alias para compatibilidade
    echo "alias docker='podman'" >> ~/.bashrc
    echo "alias docker-compose='podman-compose'" >> ~/.bashrc
    
    echo -e "${GREEN}✅ Podman instalado com sucesso${NC}"
    echo -e "${YELLOW}ℹ️  Aliases criados: docker -> podman, docker-compose -> podman-compose${NC}"
    log_message "Podman instalado com sucesso"
    return 0
}

# Logo animado
show_animated_logo() {
    clear
    echo -e "${BLUE}"
    echo -e " _____           _        _                "
    echo -e "|  __ \         | |      (_)               "
    echo -e "| |__) |__  _ __| |_ __ _ _ _ __   ___ _ __  "
    echo -e "|  ___/ _ \| '__| __/ _\` | | '_ \ / _ \ '__| "
    echo -e "| |  | (_) | |  | || (_| | | | | |  __/ |    "
    echo -e "|_|   \___/|_|   \__\__,_|_|_| |_|\___|_|    "
    echo -e "${NC}"
    echo -e "${GREEN}          Traefik + Portainer + n8n (Versão Segura)${NC}"
    sleep 1
}

# Função para mostrar um banner colorido
function show_banner() {
    echo -e "${BLUE}=============================================================================="
    echo -e "=                                                                            ="
    echo -e "=                 ${ORANGE}Preencha as informações solicitadas abaixo${GREEN}                 ="
    echo -e "=                                                                            ="
    echo -e "==============================================================================${NC}"
}

# Função para mostrar uma mensagem de etapa com barra de progresso
function show_step() {
    local current=$1
    local total=7
    local percent=$((current * 100 / total))
    local completed=$((percent / 2))
    
    echo -ne "${GREEN}Passo ${YELLOW}$current/$total ${GREEN}["
    for ((i=0; i<50; i++)); do
        if [ $i -lt $completed ]; then
            echo -ne "="
        else
            echo -ne " "
        fi
    done
    echo -e "] ${percent}%${NC}"
}

# Inicializar log
log_message "=== Iniciando instalação do Portainer Stack ==="

# Mostrar banner inicial
clear
show_animated_logo
show_banner
echo ""

# Solicitar informações do usuário com validação
while true; do
    show_step 1
    read -p "📧 Endereço de e-mail: " email
    if validate_email "$email"; then
        break
    fi
done

echo ""
while true; do
    show_step 2
    read -p "🌐 Dominio do Traefik (ex: traefik.seudominio.com): " traefik
    if validate_domain "$traefik"; then
        check_dns "$traefik"
        break
    fi
done

echo ""
while true; do
    show_step 3
    read -p "🌐 Dominio do Portainer (ex: portainer.seudominio.com): " portainer
    if validate_domain "$portainer"; then
        check_dns "$portainer"
        break
    fi
done

echo ""
while true; do
    show_step 4
    read -p "🌐 Dominio do Edge (ex: edge.seudominio.com): " edge
    if validate_domain "$edge"; then
        check_dns "$edge"
        break
    fi
done

echo ""
while true; do
    show_step 5
    read -p "🌐 Dominio do n8n (ex: n8n.seudominio.com): " n8n_domain
    if validate_domain "$n8n_domain"; then
        check_dns "$n8n_domain"
        break
    fi
done

echo ""
show_step 6
read -s -p "🔐 Senha para autenticação do n8n (recomendado): " n8n_password
echo ""

echo ""
show_step 7
read -s -p "🔐 Senha para dashboard do Traefik (recomendado): " traefik_password
echo ""

# Verificação de dados
clear
echo -e "${BLUE}📋 Resumo das Informações${NC}"
echo -e "${GREEN}================================${NC}"
echo -e "📧 Seu E-mail: ${ORANGE}$email${NC}"
echo -e "🌐 Dominio do Traefik: ${ORANGE}$traefik${NC}"
echo -e "🌐 Dominio do Portainer: ${ORANGE}$portainer${NC}"
echo -e "🌐 Dominio do Edge: ${ORANGE}$edge${NC}"
echo -e "🌐 Dominio do n8n: ${ORANGE}$n8n_domain${NC}"
if [ -n "$n8n_password" ]; then
    echo -e "🔐 Senha n8n: ${ORANGE}Configurada${NC}"
else
    echo -e "🔐 Senha n8n: ${YELLOW}Não configurada (será necessário configurar após instalação)${NC}"
fi
if [ -n "$traefik_password" ]; then
    echo -e "🔐 Senha Traefik: ${ORANGE}Configurada${NC}"
else
    echo -e "🔐 Senha Traefik: ${YELLOW}Não configurada (dashboard será público)${NC}"
fi
echo -e "${GREEN}================================${NC}"
echo ""

read -p "As informações estão certas? (y/n): " confirma1
if [ "$confirma1" == "y" ]; then
    clear
    
    # Verificar requisitos do sistema
    check_system_requirements || exit 1
    
    echo -e "${BLUE}🚀 Iniciando instalação segura...${NC}"
    log_message "Usuário confirmou instalação"
    
    # Instalar Docker de forma segura
    install_docker_secure || exit 1
    
    # Criar diretório de trabalho
    WORK_DIR="$HOME/Portainer"
    mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
    log_message "Diretório de trabalho criado: $WORK_DIR"
    
    clear

    #########################################################
    # CRIANDO DOCKER-COMPOSE.YML SEGURO
    #########################################################
    echo -e "${YELLOW}📝 Gerando configuração segura...${NC}"
    log_message "Gerando docker-compose.yml"
    
    # Gerar hash da senha do Traefik se fornecida
    traefik_auth_config=""
    if [ -n "$traefik_password" ]; then
        traefik_hash=$(generate_password_hash "$traefik_password" "admin")
        if [ -n "$traefik_hash" ]; then
            traefik_auth_config="      - \"traefik.http.middlewares.traefik-auth.basicauth.users=admin:$traefik_hash\"
      - \"traefik.http.routers.traefik-dashboard.middlewares=traefik-auth\""
        fi
    fi
    
    cat > docker-compose.yml <<EOL
services:
  traefik:
    container_name: traefik
    image: "traefik:v3.0"
    restart: unless-stopped
    command:
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --api.dashboard=true
      - --api.insecure=false
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --log.level=INFO
      - --log.filepath=/var/log/traefik.log
      - --accesslog=true
      - --accesslog.filepath=/var/log/access.log
      - --certificatesresolvers.leresolver.acme.httpchallenge=true
      - --certificatesresolvers.leresolver.acme.email=$email
      - --certificatesresolvers.leresolver.acme.storage=/acme.json
      - --certificatesresolvers.leresolver.acme.httpchallenge.entrypoint=web
      - --global.sendanonymoususage=false
    ports:
      - "$TRAEFIK_HTTP_PORT:80"
      - "$TRAEFIK_HTTPS_PORT:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./acme.json:/acme.json"
      - "./logs:/var/log"
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.http-catchall.rule=hostregexp(\`{host:.+}\`)"
      - "traefik.http.routers.http-catchall.entrypoints=web"
      - "traefik.http.routers.http-catchall.middlewares=redirect-to-https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
      - "traefik.http.routers.traefik-dashboard.rule=Host(\`$traefik\`)"
      - "traefik.http.routers.traefik-dashboard.entrypoints=websecure"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"
      - "traefik.http.routers.traefik-dashboard.tls.certresolver=leresolver"
      - "traefik.http.middlewares.secure-headers.headers.accesscontrolallowmethods=GET,OPTIONS,PUT"
      - "traefik.http.middlewares.secure-headers.headers.accesscontrolmaxage=100"
      - "traefik.http.middlewares.secure-headers.headers.hostsproxyheaders=X-Forwarded-Host"
      - "traefik.http.middlewares.secure-headers.headers.sslredirect=true"
      - "traefik.http.middlewares.secure-headers.headers.sslproxyheaders.X-Forwarded-Proto=https"
$traefik_auth_config
  
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    command: -H unix:///var/run/docker.sock
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(\`$portainer\`)"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
      - "traefik.http.routers.portainer.service=portainer"
      - "traefik.http.routers.portainer.tls.certresolver=leresolver"
      - "traefik.http.routers.portainer.middlewares=secure-headers"
      - "traefik.http.routers.portainer-edge.rule=Host(\`$edge\`)"
      - "traefik.http.routers.portainer-edge.entrypoints=websecure"
      - "traefik.http.services.portainer-edge.loadbalancer.server.port=8000"
      - "traefik.http.routers.portainer-edge.service=portainer-edge"
      - "traefik.http.routers.portainer-edge.tls.certresolver=leresolver"
      - "traefik.http.routers.portainer-edge.middlewares=secure-headers"

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    environment:
      - GENERIC_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
      - N8N_DEFAULT_LOCALE=pt-BR
      - N8N_HOST=https://$n8n_domain
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://$n8n_domain/
      - N8N_METRICS=true
      - N8N_LOG_LEVEL=info
      - N8N_LOG_OUTPUT=console
      - N8N_USER_FOLDER=/home/node/.n8n
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168
      - N8N_SECURE_COOKIE=true
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
$([ -n "$n8n_password" ] && echo "      - N8N_BASIC_AUTH_ACTIVE=true")
$([ -n "$n8n_password" ] && echo "      - N8N_BASIC_AUTH_USER=admin")
$([ -n "$n8n_password" ] && echo "      - N8N_BASIC_AUTH_PASSWORD=$n8n_password")
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - traefik
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\`$n8n_domain\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
      - "traefik.http.routers.n8n.service=n8n"
      - "traefik.http.routers.n8n.tls.certresolver=leresolver"
      - "traefik.http.routers.n8n.middlewares=n8n-headers,secure-headers"
      - "traefik.http.middlewares.n8n-headers.headers.customrequestheaders.X-Forwarded-Proto=https"
      - "traefik.http.middlewares.n8n-headers.headers.customrequestheaders.X-Forwarded-For=\$\$remote_addr"

networks:
  traefik:
    external: false
    driver: bridge

volumes:
  portainer_data:
    driver: local
  n8n_data:
    driver: local
EOL

    #########################################################
    # CERTIFICADOS LETSENCRYPT
    #########################################################
    echo -e "${YELLOW}📝 Configurando certificados SSL...${NC}"
    touch acme.json
    chmod 600 acme.json
    mkdir -p logs
    log_message "Arquivos de configuração criados"
    
    #########################################################
    # INICIANDO CONTAINERS
    #########################################################
    echo -e "${YELLOW}🚀 Iniciando containers...${NC}"
    log_message "Iniciando containers Docker"
    
    # Usar docker compose (versão mais nova) ou docker-compose (versão antiga)
    if docker compose version &> /dev/null; then
        (docker compose up -d) > /dev/null 2>&1 &
    else
        (docker-compose up -d) > /dev/null 2>&1 &
    fi
    spinner $!
    
    if [ $? -eq 0 ]; then
        log_message "Containers iniciados com sucesso"
    else
        echo -e "${RED}❌ Erro ao iniciar containers${NC}"
        log_message "ERRO: Falha ao iniciar containers"
        exit 1
    fi
    
    # Aguardar serviços inicializarem
    echo -e "${YELLOW}⏳ Aguardando serviços inicializarem...${NC}"
    log_message "Aguardando inicialização dos serviços"
    
    # Verificar se os containers estão rodando
    sleep 15
    for service in traefik portainer n8n; do
        if ! docker ps | grep -q "$service"; then
            echo -e "${YELLOW}⚠️  Serviço $service pode não ter iniciado corretamente${NC}"
            log_message "AVISO: Serviço $service com problemas"
        fi
    done
    
    sleep 15
    
    clear
    show_animated_logo
    
    echo -e "${GREEN}🎉 Instalação concluída com sucesso!${NC}"
    log_message "Instalação concluída com sucesso"
    
    echo -e "${BLUE}📝 Informações de Acesso:${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "🔗 Traefik: ${YELLOW}https://$traefik${NC}"
    if [ -n "$traefik_password" ]; then
        echo -e "   👤 Usuário: admin / Senha: [configurada]"
    fi
    echo -e "🔗 Portainer: ${YELLOW}https://$portainer${NC}"
    echo -e "🔗 Edge: ${YELLOW}https://$edge${NC}"
    echo -e "🔗 n8n: ${YELLOW}https://$n8n_domain${NC}"
    if [ -n "$n8n_password" ]; then
        echo -e "   👤 Usuário: admin / Senha: [configurada]"
    fi
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo -e "${BLUE}💡 Informações Importantes:${NC}"
    if [ "$TRAEFIK_HTTP_PORT" != "80" ] || [ "$TRAEFIK_HTTPS_PORT" != "443" ]; then
        echo -e "${ORANGE}⚠️  ATENÇÃO: Usando portas não-padrão ($TRAEFIK_HTTP_PORT/$TRAEFIK_HTTPS_PORT)${NC}"
        echo -e "${ORANGE}   Você precisará incluir a porta na URL para acessar os serviços${NC}"
        echo -e "${ORANGE}   Exemplo: https://seudominio.com:$TRAEFIK_HTTPS_PORT${NC}"
        echo ""
    fi
    echo -e "${YELLOW}• Aguarde alguns minutos para que os certificados SSL sejam gerados${NC}"
    echo -e "${YELLOW}• Todos os serviços estão configurados com HTTPS automático${NC}"
    echo -e "${YELLOW}• Headers de segurança configurados automaticamente${NC}"
    echo -e "${YELLOW}• Logs disponíveis em: $WORK_DIR/logs/${NC}"
    echo -e "${YELLOW}• Para verificar status: docker ps${NC}"
    echo -e "${YELLOW}• Para ver logs: docker compose logs [serviço]${NC}"
    echo -e "${YELLOW}• Log de instalação: $LOG_FILE${NC}"
    echo ""
    echo -e "${GREEN}🔒 Melhorias de Segurança Aplicadas:${NC}"
    echo -e "${YELLOW}• Instalação segura do Docker via repositório oficial${NC}"
    echo -e "${YELLOW}• Validação de domínios e e-mails${NC}"
    echo -e "${YELLOW}• Verificação de requisitos do sistema${NC}"
    echo -e "${YELLOW}• Headers de segurança HTTP configurados${NC}"
    echo -e "${YELLOW}• Autenticação básica opcional configurada${NC}"
    echo -e "${YELLOW}• Logs de auditoria habilitados${NC}"
    echo -e "${YELLOW}• Health checks configurados${NC}"
    echo ""
    echo -e "${GREEN}🌟 Próximos passos:${NC}"
    echo -e "${YELLOW}1. Configure DNS para apontar seus domínios para este servidor${NC}"
    echo -e "${YELLOW}2. Aguarde a geração dos certificados SSL (pode levar alguns minutos)${NC}"
    echo -e "${YELLOW}3. Acesse o Portainer para configurar sua primeira conta admin${NC}"
    echo -e "${YELLOW}4. Configure autenticação no n8n se não foi definida uma senha${NC}"
    
else
    echo -e "${RED}❌ Instalação cancelada pelo usuário.${NC}"
    log_message "Instalação cancelada pelo usuário"
    exit 0
fi
