#!/bin/bash

# Cores
GREEN='\e[32m'
YELLOW='\e[33m'
RED='\e[31m'
BLUE='\e[34m'
WHITE='\e[97m'
ORANGE='\e[38;5;208m'
NC='\e[0m'


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

# Função para verificar requisitos do sistema
check_system_requirements() {
    echo -e "${ORANGE}Verificando requisitos do sistema...${NC}"
    
    # Verificar espaço em disco (em GB, removendo a unidade 'G')
    local free_space=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$free_space" -lt 15 ]; then
        echo -e "${RED}❌ Erro: Espaço em disco insuficiente. Mínimo requerido: 15GB (incluindo n8n)${NC}"
        return 1
    fi
    
    # Verificar memória RAM
    local total_mem=$(free -g | awk 'NR==2 {print $2}')
    if [ $total_mem -lt 4 ]; then
        echo -e "${RED}❌ Erro: Memória RAM insuficiente. Mínimo requerido: 4GB (incluindo n8n)${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Requisitos do sistema atendidos${NC}"
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
    echo -e "${GREEN}          Traefik + Portainer + n8n${NC}"
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
    local total=6
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

# Mostrar banner inicial
clear
show_animated_logo
show_banner
echo ""

# Solicitar informações do usuário
show_step 1
read -p "📧 Endereço de e-mail: " email
echo ""
show_step 2
read -p "🌐 Dominio do Traefik (ex: traefik.seudominio.com): " traefik
echo ""
show_step 3
read -p "🌐 Dominio do Portainer (ex: portainer.seudominio.com): " portainer
echo ""
show_step 4
read -p "🌐 Dominio do Edge (ex: edge.seudominio.com): " edge
echo ""
show_step 5
read -p "🌐 Dominio do n8n (ex: n8n.seudominio.com): " n8n_domain
echo ""
show_step 6
read -p "🔐 Senha para autenticação do n8n (opcional, pressione Enter para pular): " n8n_password
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
    echo -e "🔐 Senha n8n: ${YELLOW}Não configurada${NC}"
fi
echo -e "${GREEN}================================${NC}"
echo ""

read -p "As informações estão certas? (y/n): " confirma1
if [ "$confirma1" == "y" ]; then
    clear
    
    # Verificar requisitos do sistema
    check_system_requirements || exit 1
    
    echo -e "${BLUE}🚀 Iniciando instalação...${NC}"
    
    #########################################################
    # INSTALANDO DEPENDENCIAS
    #########################################################
    echo -e "${YELLOW}📦 Atualizando sistema e instalando dependências...${NC}"
    (sudo apt update -y && sudo apt upgrade -y) > /dev/null 2>&1 &
    spinner $!
    
    echo -e "${YELLOW}🐳 Instalando Docker...${NC}"
    (sudo apt install -y curl && \
    curl -fsSL https://get.docker.com -o get-docker.sh && \
    sudo sh get-docker.sh) > /dev/null 2>&1 &
    spinner $!
    
    mkdir -p ~/Portainer && cd ~/Portainer
    echo -e "${GREEN}✅ Dependências instaladas com sucesso${NC}"
    sleep 2
    clear

    #########################################################
    # CRIANDO DOCKER-COMPOSE.YML
    #########################################################
    cat > docker-compose.yml <<EOL
services:
  traefik:
    container_name: traefik
    image: "traefik:latest"
    restart: always
    command:
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --api.insecure=true
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --log.level=INFO
      - --certificatesresolvers.leresolver.acme.httpchallenge=true
      - --certificatesresolvers.leresolver.acme.email=$email
      - --certificatesresolvers.leresolver.acme.storage=./acme.json
      - --certificatesresolvers.leresolver.acme.httpchallenge.entrypoint=web
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./acme.json:/acme.json"
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
      # - "traefik.http.middlewares.traefik-auth.basicauth.users=\$senha"
      # - "traefik.http.routers.traefik-dashboard.middlewares=traefik-auth"
  
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    command: -H unix:///var/run/docker.sock
    restart: always
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
      - "traefik.http.routers.portainer-edge.rule=Host(\`$edge\`)"
      - "traefik.http.routers.portainer-edge.entrypoints=websecure"
      - "traefik.http.services.portainer-edge.loadbalancer.server.port=8000"
      - "traefik.http.routers.portainer-edge.service=portainer-edge"
      - "traefik.http.routers.portainer-edge.tls.certresolver=leresolver"

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: always
    environment:
      - GENERIC_TIMEZONE=America/Sao_Paulo
      - TZ=America/Sao_Paulo
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
$([ -n "$n8n_password" ] && echo "      - N8N_BASIC_AUTH_ACTIVE=true")
$([ -n "$n8n_password" ] && echo "      - N8N_BASIC_AUTH_USER=admin")
$([ -n "$n8n_password" ] && echo "      - N8N_BASIC_AUTH_PASSWORD=$n8n_password")
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\`$n8n_domain\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
      - "traefik.http.routers.n8n.service=n8n"
      - "traefik.http.routers.n8n.tls.certresolver=leresolver"
      - "traefik.http.routers.n8n.middlewares=n8n-headers"
      - "traefik.http.middlewares.n8n-headers.headers.customrequestheaders.X-Forwarded-Proto=https"

networks:
  traefik:
    external: false

volumes:
  portainer_data:
  n8n_data:
EOL

    #########################################################
    # CERTIFICADOS LETSENCRYPT
    #########################################################
    echo -e "${YELLOW}📝 Gerando certificado LetsEncrypt...${NC}"
    touch acme.json
    sudo chmod 600 acme.json
    
    #########################################################
    # INICIANDO CONTAINER
    #########################################################
    echo -e "${YELLOW}🚀 Iniciando containers...${NC}"
    (sudo docker compose up -d) > /dev/null 2>&1 &
    spinner $!
    
    # Aguardar n8n inicializar
    echo -e "${YELLOW}⏳ Aguardando serviços inicializarem...${NC}"
    sleep 30
    
    clear
    show_animated_logo
    
    echo -e "${GREEN}🎉 Instalação concluída com sucesso!${NC}"
    echo -e "${BLUE}📝 Informações de Acesso:${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "🔗 Traefik: ${YELLOW}https://$traefik${NC}"
    echo -e "🔗 Portainer: ${YELLOW}https://$portainer${NC}"
    echo -e "🔗 Edge: ${YELLOW}https://$edge${NC}"
    echo -e "🔗 n8n: ${YELLOW}https://$n8n_domain${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo -e "${BLUE}💡 Informações Importantes:${NC}"
    echo -e "${YELLOW}• Aguarde alguns minutos para que os certificados SSL sejam gerados${NC}"
    echo -e "${YELLOW}• O n8n estará disponível em produção com SSL automático${NC}"
    if [ -n "$n8n_password" ]; then
        echo -e "${YELLOW}• Acesso ao n8n protegido com usuário: admin / senha configurada${NC}"
    else
        echo -e "${ORANGE}• Configure a autenticação do n8n após o primeiro acesso${NC}"
    fi
    echo -e "${YELLOW}• Timezone configurado para America/Sao_Paulo${NC}"
    echo -e "${YELLOW}• Dados de execução serão limpos automaticamente após 7 dias${NC}"
    echo -e "${YELLOW}• Para ver logs: docker compose logs [serviço]${NC}"
    echo ""
    echo -e "${GREEN}🌟 Visite: https://www.portainer.io/${NC}"
else
    echo -e "${RED}❌ Instalação cancelada. Por favor, inicie novamente.${NC}"
    exit 0
fi
