#!/bin/sh
#
# Time and Weather Announcement Setup Script
# Copyright (C) 2024 Freddie Mac - KD5FMU
# Copyright (C) 2025 Jory A. Pratt - W5GLE
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/gpl-2.0.html>.

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
SOUNDS_DIR="/var/lib/asterisk/sounds/custom"
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

# Edit the path for sound files in saytime.pl
echo "Adjusting sounds dir in "${BIN_DIR}/saytime.pl""
sed -i.bak 's|/var/lib/asterisk/sounds|/usr/local/share/asterisk/sounds/custom|' "${BIN_DIR}/saytime.pl"

# Create configuration directory if not existing
echo "Creating configuration directory..."
mkdir -p "$LOCAL_DIR"
chown asterisk:asterisk "$LOCAL_DIR"

# Download configuration file
echo "Downloading weather configuration file..."
sudo -u asterisk curl -s -o "${LOCAL_DIR}/weather.ini" "$INI_URL"

# Check if directory exists and create it
if [ ! -d "$SOUNDS_DIR" ]; then
    # Create the directory with the necessary permissions
    mkdir -p "$SOUNDS_DIR"
    echo "Directory '$SOUNDS_DIR' created."
    
    # Set ownership to root:asterisk
    chown asterisk:asterisk "$SOUNDS_DIR"
    echo "Ownership of '$SOUNDS_DIR' set to root:asterisk."
else
    echo "Directory '$SOUNDS_DIR' already exists."
fi

# Download and extract sound files
echo "Downloading and extracting sound files..."
curl -s -o "$ZIP_FILE" "$SOUND_ZIP_URL"
sudo -u asterisk unzip -o "$ZIP_FILE" -d "$SOUNDS_DIR" > /dev/null 2>&1
rm -f "$ZIP_FILE"

# Set up a cron job for hourly announcements
echo "Configuring hourly time and weather announcements..."
CRON_COMMENT="# Hourly Time and Weather Announcement"
CRON_JOB="00 00-23 * * * (/usr/bin/nice -19 /usr/bin/perl ${BIN_DIR}/saytime.pl $ZIP_CODE $NODE_NUMBER >/dev/null)"

# Check and add the cron job if it doesn't already exist
CRONTAB_TMP=$(mktemp)
crontab -u asterisk -l 2>/dev/null > "$CRONTAB_TMP"
if ! grep -Fq "$CRON_COMMENT" "$CRONTAB_TMP" && ! grep -Fq "$CRON_JOB" "$CRONTAB_TMP"; then
    {
        echo "$CRON_COMMENT"
        echo "$CRON_JOB"
    } >> "$CRONTAB_TMP"
    crontab -u asterisk "$CRONTAB_TMP"
    echo "Cron job added."
else
    echo "Cron job already exists."
fi
rm "$CRONTAB_TMP"

# Directory to check
dir_to_check="/var/lib/asterisk/sounds"

# Count the number of directories inside the specified directory, excluding the parent directory (.)
dir_count=$(find "$dir_to_check" -mindepth 1 -maxdepth 1 -type d | wc -l)

# Check if there are more than two directories
if [ "$dir_count" -gt 2 ]; then
  echo "You have files which don't belong"
  echo "You can clean up the directory with the following commands"
  echo "rm -r $dir_to_check/*"
  echo "mkdir -p $dir_to_check/{en,custom}"
  echo "chown asterisk:asterisk -R $dir_to_check/*"
fi

# Update plocate database
echo "Updating plocate database..."
updatedb || {
    echo "Failed to update the plocate database."
    exit 1
}

echo "Setup completed successfully!"
