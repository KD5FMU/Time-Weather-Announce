#!/bin/sh

# Time and Weather Announcement Setup Script
# Originally created by Freddie Mac - KD5FMU on November 17, 2024
# This script automates the installation of tools for time and weather announcements.

# Check if the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "Please run this script as root using 'sudo' or log in as root." >&2
    exit 1
fi

# Check for required arguments: ZIP code and node number
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <ZIP_CODE> <NODE_NUMBER>" >&2
    exit 1
fi

# Assign input arguments to variables
ZIP_CODE="$1"
NODE_NUMBER="$2"

# URLs for required files
BASE_URL="https://raw.githubusercontent.com/KD5FMU/Time-Weather-Announce/refs/heads/main/"
SAYTIME_URL="${BASE_URL}saytime.pl"
WEATHER_URL="${BASE_URL}weather.sh"
INI_URL="${BASE_URL}weather.ini"
SOUND_ZIP_URL="http://hamradiolife.org/downloads/sound_files.zip"

# Directories and files
SOUNDS_DIR="/var/lib/asterisk/sounds"
LOCAL_DIR="/etc/asterisk/local"
BIN_DIR="/usr/local/sbin"
ZIP_FILE="${SOUNDS_DIR}/sound_files.zip"

# Ensure necessary tools are installed
echo "Installing required packages..."
apt install -y bc zip plocate || {
    echo "Failed to install packages. Ensure you have an active internet connection."
    exit 1
}

# Download and set up scripts
echo "Setting up required scripts..."
mkdir -p "$BIN_DIR"
curl -s -o "${BIN_DIR}/saytime.pl" "$SAYTIME_URL" && chmod +x "${BIN_DIR}/saytime.pl"
curl -s -o "${BIN_DIR}/weather.sh" "$WEATHER_URL" && chmod +x "${BIN_DIR}/weather.sh"

# Create configuration directory if not existing
echo "Creating configuration directory..."
mkdir -p "$LOCAL_DIR"

# Download configuration file
echo "Downloading weather configuration file..."
curl -s -o "${LOCAL_DIR}/weather.ini" "$INI_URL"

# Download and extract sound files
echo "Downloading and extracting sound files..."
curl -s -o "$ZIP_FILE" "$SOUND_ZIP_URL"
unzip -o "$ZIP_FILE" -d "$SOUNDS_DIR"
rm -f "$ZIP_FILE"

# Set up a cron job for hourly announcements
echo "Configuring hourly time and weather announcements..."
CRON_COMMENT="# Hourly Time and Weather Announcement"
CRON_JOB="00 00-23 * * * (/usr/bin/nice -19 /usr/bin/perl ${BIN_DIR}/saytime.pl $ZIP_CODE $NODE_NUMBER >/dev/null)"

# Check and add the cron job if it doesn't already exist
CRONTAB_TMP=$(mktemp)
crontab -l 2>/dev/null > "$CRONTAB_TMP"
if ! grep -Fq "$CRON_COMMENT" "$CRONTAB_TMP" && ! grep -Fq "$CRON_JOB" "$CRONTAB_TMP"; then
    {
        echo "$CRON_COMMENT"
        echo "$CRON_JOB"
    } >> "$CRONTAB_TMP"
    crontab "$CRONTAB_TMP"
    echo "Cron job added."
else
    echo "Cron job already exists."
fi
rm "$CRONTAB_TMP"

echo "Setup completed successfully!"
