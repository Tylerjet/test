#!/usr/bin/env bash

set -e

# Get the MAC address of the first network interface for unique id
mac_address=$(ip addr | grep -o -E '([0-9a-fA-F]:?){6}' | head -n 1)
# Use the MAC address to generate a unique identifier
unique_id=$(echo "$mac_address" | sha256sum | cut -c 1-8)

R=$'\e[1;91m'    # Red ${R}
G=$'\e[1;92m'    # Green ${G}
Y=$'\e[1;93m'    # Yellow ${M}
M=$'\e[1;95m'    # Magenta ${M}
C=$'\e[96m'      # Cyan ${C}
NC=$'\e[0m'      # No Color ${NC}

logo () {
    clear
echo -e "${C}$(cat << "EOF"
    __ __ ___                             ____             __                     ____           __        ____
   / //_// (_)___  ____  ___  _____      / __ )____ ______/ /____  ______        /  _/___  _____/ /_____ _/ / /
  / ,<  / / / __ \/ __ \/ _ \/ ___/_____/ __  / __ `/ ___/ //_/ / / / __ \______ / // __ \/ ___/ __/ __ `/ / /
 / /| |/ / / /_/ / /_/ /  __/ /  /_____/ /_/ / /_/ / /__/ ,< / /_/ / /_/ /_____// // / / (__  ) /_/ /_/ / / /
/_/ |_/_/_/ .___/ .___/\___/_/        /_____/\__,_/\___/_/|_|\__,_/ .___/     /___/_/ /_/____/\__/\__,_/_/_/
         /_/   /_/                                               /_/
EOF
)${NC}"
    echo ""
    echo "==============================================================================================================="
    echo ""
}

ask_yn() {
    while true; do
        read -rp "$1 (yes/no, default is yes): " answer
        case $answer in
            [Yy]* | "") return 0;;
            [Nn]* ) return 1;;
            * );;
        esac
    done
}

ask_token() {
    local prompt="$1: "
    local input=""
    echo -n "$prompt" >&2
    stty -echo   # Disable echoing of characters
    while IFS= read -rs -n 1 char; do
        if [[ $char == $'\0' || $char == $'\n' ]]; then
            break
        fi
        input+=$char
        echo -n "*" >&2  # Explicitly echo asterisks to stderr
    done
    stty echo   # Re-enable echoing
    echo >&2   # Move to a new line after user input
    echo "$input"
}


ask_textinput() {
    if [ -n "$2" ]; then
        read -rp "$1 (default is $2): " input
        echo "${input:-$2}"
    else
        read -rp "$1: " input
        echo "$input"
    fi
}

install_repo() {
    logo
    if ask_yn "Do you want to proceed with the installation?"; then
        clear
        logo
        cd "$HOME"
        if [ ! -d "klipper-backup" ]; then
            echo -e "${M}●${NC} Installing Klipper-Backup"
            git clone https://github.com/Staubgeborener/klipper-backup.git 2>/dev/null
            chmod +x ./klipper-backup/script.sh
            cp ./klipper-backup/.env.example ./klipper-backup/.env
            sleep .5
	    logo
            echo -e "${G}●${NC} Klipper-Backup Installed!\n"
        else
            cd klipper-backup
            if [ "$(git rev-parse HEAD)" = "$(git ls-remote $(git rev-parse --abbrev-ref @{u} | sed 's/\// /g') | cut -f1)" ]; then
                echo -e "${G}●${NC} Klipper-Backup ${G}is up to date.${NC}\n"
            else
                if ask_yn "Update is available for Klipper-Backup, proceed with update?"; then
                    logo
                    echo -e "${Y}●${NC} Updating Klipper-Backup\n"
                    if git pull 2>&1 >/dev/null;then
                        logo
                        echo -e "${G}●${NC} Klipper-Backup ${G}Updated${NC}\n"
                    fi
                else
                    logo
                    echo -e "${M}●${NC} Skipping Klipper-Backup update.\n"
                fi
            fi
        fi
        configure
    else
        logo
        echo -e "${R}●${NC} Installation aborted.\n"
        exit 1
    fi
}

configure() {
    if ask_yn "Do you want to proceed with configuring Klipper-Backup?"; then
        logo
        ghtoken=$(ask_token "Enter your github token")
        ghuser=$(ask_textinput "Enter your github username")
        ghrepo=$(ask_textinput "Enter your repository name")
        repobranch=$(ask_textinput "Enter your desired branch name" "main")
        commitname=$(ask_textinput "Enter desired commit username" "$(whoami)")
        commitemail=$(ask_textinput "Enter desired commit email" "$(whoami)@$(hostname)-$unique_id")
        #echo "Set token: $ghtoken"
        sed -i "s/^github_token=.*/github_token=$ghtoken/" "$HOME/klipper-backup/.env"
        #echo "Set Username: $ghuser"
        sed -i "s/^github_username=.*/github_username=$ghuser/" "$HOME/klipper-backup/.env"
        #echo "Set Repo Name: $ghrepo"
        sed -i "s/^github_repository=.*/github_repository=$ghrepo/" "$HOME/klipper-backup/.env"
        #echo "Set branch: $repobranch"
        sed -i "s/^branch_name=.*/branch_name=\"$repobranch\"/" "$HOME/klipper-backup/.env"
        #echo "Set commit username: $commitname"
        sed -i "s/^commit_username=.*/commit_username=\"$commitname\"/" "$HOME/klipper-backup/.env"
        #echo "Set commit email: $commitemail"
        sed -i "s/^commit_email=.*/commit_email=\"$commitemail\"/" "$HOME/klipper-backup/.env"
        logo
        echo -e "${G}●${NC} Configuration Complete!\n"
    else
        logo
        echo -e "${M}●${NC} Skipping configuration.\n"
    fi
}

patch_klipper-backup_update_manager() {
    if ! grep -Eq "^\[update_manager klipper-backup\]\s*$" "$HOME/printer_data/config/moonraker.conf"; then
        ### add new line to conf if it doesn't end with one
        [[ $(tail -c1 "$HOME/printer_data/config/moonraker.conf" | wc -l) -eq 0 ]] && echo "" >> "$HOME/printer_data/config/moonraker.conf"
        ### add klipper-backup update manager section to moonraker.conf
        echo "Adding klipper-backup to update manager."
        if /usr/bin/env bash -c "cat >> $HOME/printer_data/config/moonraker.conf" << MOONRAKER_CONF;
[update_manager klipper-backup]
type: git_repo
path: ~/klipper-backup
origin: https://github.com/Staubgeborener/klipper-backup.git
managed_services: moonraker
primary_branch: main
MOONRAKER_CONF
        then
            sudo systemctl restart moonraker.service
        fi
    fi
}

install_service () {
    if ask_yn "Would you like to install the backup service?"; then
        logo
        echo "Installing Klipper-backup service"
        if dpkg -l | grep -q '^ii.*network-manager'; then
            sudo /usr/bin/env bash -c "cat > /etc/systemd/system/klipper-backup.service" << KLIPPER_SERVICE
[Unit]
Description=Klipper Backup Service
After=NetworkManager-wait-online.service
Wants=NetworkManager-wait-online.service

[Service]
User=$(whoami)
Type=oneshot
ExecStart=/bin/bash -c 'bash $HOME/klipper-backup/script.sh "New Backup on boot \$(date +%%D)"'

[Install]
WantedBy=default.target
KLIPPER_SERVICE
        else
            sudo /usr/bin/env bash -c "cat > /etc/systemd/system/klipper-backup.service" << KLIPPER_SERVICE
[Unit]
Description=Klipper Backup Service
After=network-online.target
Wants=network-online.target

[Service]
User=$(whoami)
Type=oneshot
ExecStart=/bin/bash -c 'bash $HOME/klipper-backup/script.sh "New Backup on boot \$(date +%%D)"'

[Install]
WantedBy=default.target
KLIPPER_SERVICE
        fi
        sudo systemctl daemon-reload
        sudo systemctl enable klipper-backup.service
        sudo systemctl start klipper-backup.service
        logo
        echo -e "${G}●${NC} Service Installed!\n"
    else
        logo
        echo -e "${M}●${NC} Skipping service install.\n"
    fi
}

install_cron () {
    if ask_yn "Would you like to install the cron task?"; then
        logo
        if ! (crontab -l 2>/dev/null | grep -q "$HOME/klipper-backup/script.sh"); then
            (crontab -l 2> /dev/null; echo "0 */4 * * * $HOME/klipper-backup/script.sh") | crontab -
        fi
        echo -e "${G}●${NC} Cron Installed!\n"
    else
        logo
        echo -e "${M}●${NC} Skipping cron install.\n"
    fi
}

install_repo
patch_klipper-backup_update_manager
install_service
install_cron
logo
echo -e "${G}●${NC} Installation Complete!\n"
