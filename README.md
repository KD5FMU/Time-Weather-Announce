![HRC Logo](https://github.com/KD5FMU/Time-Weather-Announce/blob/main/TimeWeather2.png)

# Time and Weather Conditions Announcement
This script file will install the needed files and scripts to initiate the Top of the Hour Time and Weather Condition Announcement moved over from HamVoIP AllStar Software. Here is how you install it.



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
Make sure you leave a space between your zip code and node number.

You don't have to but prob should reboot your node.

Your can test the node by running this line 

```
sudo perl /usr/local/sbin/saytime.pl Your_Zip_Code Your_Node_Number
```

makeing the appropriate changes to your Zip Code and Node Number and then hit enter and of all went well you will hear the time and weather conditions announce.

You can use this video as a reference.
https://youtu.be/DJ9w9pNzkyo?si=BcNo6ONEnXvT-KM0

It is my hope that you find this script file very helpful and useful. 

73 DE KD5FMU

"Ham On Y'all!"


