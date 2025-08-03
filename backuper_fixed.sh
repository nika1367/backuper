#!/bin/bash

# Global constants
readonly SCRIPT_SUFFIX="_backuper_script.sh"
readonly TAG="_backuper."
readonly BACKUP_SUFFIX="${TAG}zip"
readonly DATABASE_SUFFIX="${TAG}sql"
readonly LOGS_SUFFIX="${TAG}log"
readonly VERSION="v0.4.0"
readonly OWNER="@ErfJabs"
readonly SPONSORTEXT="خرید سرور مجازی ایران OkaCloud با تانلینگ اختصاصی رایگان"
readonly SPONSORLINK="https://t.me/OkaCloud"


# ANSI color codes
declare -A COLORS=(
    [red]='\033[1;31m' [pink]='\033[1;35m' [green]='\033[1;92m'
    [spring]='\033[38;5;46m' [orange]='\033[1;38;5;208m' [cyan]='\033[1;36m' [reset]='\033[0m'
)

# Logging & Printing functions
print() { echo -e "${COLORS[cyan]}$*${COLORS[reset]}"; }
log() { echo -e "${COLORS[cyan]}[INFO]${COLORS[reset]} $*"; }
warn() { echo -e "${COLORS[orange]}[WARN]${COLORS[reset]} $*" >&2; }
error() { echo -e "${COLORS[red]}[ERROR]${COLORS[reset]} $*" >&2; exit 1; }
wrong() { echo -e "${COLORS[red]}[WRONG]${COLORS[reset]} $*" >&2; }
success() { echo -e "${COLORS[spring]}${COLORS[green]}[SUCCESS]${COLORS[reset]} $*"; }

# Interactive functions
input() { read -p "$(echo -e "${COLORS[orange]}▶ $1${COLORS[reset]} ")" "$2"; }
confirm() { read -p "$(echo -e "${COLORS[pink]}Press any key to continue...${COLORS[reset]}")"; }

# Error handling
trap 'error "An error occurred. Exiting..."' ERR

# Utility functions
check_root() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root"
}

detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    else
        error "Unsupported package manager"
    fi
}

update_os() {
    local package_manager=$(detect_package_manager)
    log "Updating the system using $package_manager..."
    
    case $package_manager in
        apt)
            apt-get update -y && apt-get upgrade -y || error "Failed to update the system"
            ;;
        dnf|yum)
            $package_manager update -y || error "Failed to update the system"
            ;;
        pacman)
            pacman -Syu --noconfirm || error "Failed to update the system"
            ;;
    esac
    success "System updated successfully"
}

install_dependencies() {
    local package_manager=$(detect_package_manager)
    local packages=("wget" "zip" "cron" "msmtp" "mutt")

    log "Installing dependencies: ${packages[*]}..."
    
    case $package_manager in
        apt)
            apt-get install -y "${packages[@]}" || error "Failed to install dependencies"
            if ! apt-get install -y default-mysql-client; then
                apt-get install -y mariadb-client || error "Failed to install MySQL/MariaDB client"
            fi
            ;;
        dnf|yum)
            packages+=("mariadb")
            $package_manager install -y "${packages[@]}" || error "Failed to install dependencies"
            ;;
        pacman)
            packages+=("mariadb")
            pacman -Sy --noconfirm "${packages[@]}" || error "Failed to install dependencies"
            ;;
    esac
    success "Dependencies installed successfully"
}

install_yq() {
    if command -v yq &>/dev/null; then
        success "yq is already installed."
        return
    fi

    log "Installing yq..."
    local ARCH=$(uname -m)
    local YQ_BINARY="yq_linux_amd64"

    [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && YQ_BINARY="yq_linux_arm64"

    wget -q "https://github.com/mikefarah/yq/releases/latest/download/$YQ_BINARY" -O /usr/bin/yq || error "Failed to download yq."
    chmod +x /usr/bin/yq || error "Failed to set execute permissions on yq."

    success "yq installed successfully."
}

generate_password() {
    clear
    print "[PASSWORD PROTECTION]\n"
    print "You can set a password for the archive. The password must contain both letters and numbers, and be at least 8 characters long.\n"
    print "If you don't want a password, just press Enter.\n"

    # اگر مقدار LIMITSIZE هنوز تنظیم نشده، مقدار پیش‌فرض قرار بده
    if [[ -z "$LIMITSIZE" || ! "$LIMITSIZE" =~ ^[0-9]+$ ]]; then
        LIMITSIZE=24
    fi

    while true; do
        input "Enter the password for the archive (or press Enter to skip): " PASSWORD

        if [ -z "$PASSWORD" ]; then
            success "No password will be set for the archive."
            COMPRESS="zip -9 -r -s ${LIMITSIZE}m"
            break
        fi

        # اصلاح شده: بررسی رمز عبور با اجازه دادن به کاراکترهای خاص
        if [[ ! "$PASSWORD" =~ ^[a-zA-Z0-9_@#!\$%^&*]{8,}$ ]]; then
            wrong "Password must be at least 8 characters long and contain only letters, numbers, and allowed special characters: _@#!$%^&* Please try again."
            continue
        fi

        input "Confirm the password: " CONFIRM_PASSWORD

        if [ "$PASSWORD" == "$CONFIRM_PASSWORD" ]; then
            success "Password confirmed."
            COMPRESS="zip -9 -r -e -P $PASSWORD -s ${LIMITSIZE}m"
            break
        else
            wrong "Passwords do not match. Please try again."
        fi
    done
}

# بقیه‌ی توابع و منطق مشابه
