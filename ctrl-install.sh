#!/bin/bash

# ==============================
# CtrlPanel Installer
# Author : Sherif Fadhil
# GitHub : https://github.com/sherif1day-ux/Pterodactyl-Installer
# ==============================

# Colors
BLUE='\033[0;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Welcome Message
echo -e "${BLUE}[+] =============================================== [+]${NC}"
echo -e "${BLUE}[+]                 CTRL PANEL INSTALLER           [+]${NC}"
echo -e "${BLUE}[+] =============================================== [+]${NC}"
echo -e "${YELLOW}Installer akan memulai proses instalasi CtrlPanel...${NC}"
echo -e "                                                       "
sleep 2

# Download & run installer from GitHub
echo -e "${BLUE}[+] =============================================== [+]${NC}"
echo -e "${BLUE}[+]                 INSTALLER PROCESS              [+]${NC}"
echo -e "${BLUE}[+] =============================================== [+]${NC}"
echo -e "                                                       "
bash <(curl -s https://raw.githubusercontent.com/sherif1day-ux/Pterodactyl-Installer/main/ctrlpanel.sh)

# Success message
echo -e "                                                       "
echo -e "${GREEN}[+] =============================================== [+]${NC}"
echo -e "${GREEN}[+]             SUCCESS INSTALL CTRL PANEL          [+]${NC}"
echo -e "${GREEN}[+] =============================================== [+]${NC}"
echo -e "                                                       "

read -p "Tekan ENTER untuk keluar..."
exit 0
