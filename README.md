# Time-Weather-Announce
Time and Weather Annoucement

Goto the root directory
```
cd ~
```

Then Download this file
```
sudo wget https://raw.githubusercontent.com/KD5FMU/Time-Weather-Announce/refs/heads/main/time_weather.sh
```
and then make it executable.

```
sudo chmod +x time_weather.sh
```

then run it
```
sudo ./time_weather.sh
```

Then you will have to go into the sudo crontab and make changes to the appropriate line

```
00 00-23 * * * (/usr/bin/nice -19 ; /usr/bin/perl /usr/local/sbin/saytime.pl YOUR_ZIP YOUR_NODE_NUMBER > /dev/null)
```
Replace YOUR_ZIP with your local Zip Code and YOUR_NODE_NUMBER with your local AllStarLink node number.
Make sure you leave a space between your zio code and node number.

