#!/bin/bash

# This script was created to simplify the process of adding Time and Weather condition annoucements
# File created by Freddie Mac - KD5FMU on Sunday, November 17th 2024 with the help of ChatGPT.

# Define variables
SAYTIME_URL="https://raw.githubusercontent.com/KD5FMU/Time-Weather-Announce/refs/heads/main/saytime.pl"
WEATHER_URL="https://raw.githubusercontent.com/KD5FMU/Time-Weather-Announce/refs/heads/main/weather.sh"
INI_URL="https://raw.githubusercontent.com/KD5FMU/Time-Weather-Announce/refs/heads/main/weather.ini"
SOUND_ZIP_URL="http://hamradiolife.org/downloads/sound_files.zip"
SOUNDS_DIR="/var/lib/asterisk/sounds"
LOCAL_DIR="/etc/asterisk/local"
BIN_DIR="/usr/local/sbin"
ZIP_FILE="$SOUNDS_DIR/sound_files.zip"

# Ensure dependencies are installed
echo "Installing bc..."
sudo apt install -y bc || { echo "Failed to install bc."; exit 1; }

# Download and set up scripts
echo "Downloading saytime.pl and weather.sh..."
sudo curl -o "$BIN_DIR/saytime.pl" "$SAYTIME_URL" && sudo chmod +x "$BIN_DIR/saytime.pl"
sudo curl -o "$BIN_DIR/weather.sh" "$WEATHER_URL" && sudo chmod +x "$BIN_DIR/weather.sh"

# Create local directory if it doesn't exist
if [ ! -d "$LOCAL_DIR" ]; then
  echo "Creating $LOCAL_DIR..."
  sudo mkdir -p "$LOCAL_DIR"
fi

# Download weather.ini to the local directory
echo "Downloading weather.ini..."
sudo curl -o "$LOCAL_DIR/weather.ini" "$INI_URL"

# Download and unzip sound files
echo "Downloading and extracting sound files..."
sudo curl -o "$ZIP_FILE" "$SOUND_ZIP_URL"
sudo unzip -o "$ZIP_FILE" -d "$SOUNDS_DIR"
sudo rm -f "$ZIP_FILE"

# Install and configure plocate
echo "Installing and configuring plocate..."
sudo apt install -y plocate
sudo rm -f /usr/bin/locate
sudo ln -s /usr/bin/plocate /usr/bin/locate
sudo updatedb

# Add line to sudo crontab
#CRON_LINE="00 00-23 * * * (/usr/bin/nice -19 ; /usr/bin/perl /usr/local/sbin/saytime.pl YOUR_ZIP YOUR_NODE > /dev/null)"
#if ! sudo crontab -l | grep -q "$CRON_LINE"; then
#  echo "Adding line to sudo crontab..."
# (sudo crontab -l; echo "$CRON_LINE") | sudo crontab -
#fi

# Define the cron job and its preceding comment
CRON_COMMENT="# Top of the Hour Time and Weather Announcement"
CRON_JOB="00 00-23 * * * (/usr/bin/nice -19 ; /usr/bin/perl /usr/local/sbin/saytime.pl YOUR_ZIP YOUR_NODE > /dev/null)"

# Add the cron job and comment to the root user's crontab
(sudo crontab -l 2>/dev/null; echo "$CRON_COMMENT"; echo "$CRON_JOB") | sudo crontab -

# Print the current crontab to verify
echo "Current crontab for root:"
sudo crontab -l

echo "Setup completed successfully!"
