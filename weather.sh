#!/bin/bash 

# Get current weather condition and temperature based on ZIP code or Airport designator
# Meant to be run on Allstar and requires system locate program and Asterisk sound files
# WA3DSP 4/2017

# 4/30/2017 - Added wunderground temperature report. 
# wunderground station code is preceeded with w- so a station code WPAGLENB5
# would be w-WPAGLENB5 
# wunderground reports only temperature

# 5/10/2017 - added celsius option

# 12/30/2017 - corrected negative temperature not working

# 1/8/2018 - added capability for 3 word condition - "like rain and snow"

# 6/27/2018 - added test for /etc/asterisk/local/weather.ini file

# 11/1/2018 - added 'v' option to only print to screen

# 11/10/2018 - Added degree symbol for visual output

# 1/17/2020 - Changed wunderground to accept api key from config file.

# 11/22/2023 - Better check for Accuweather RSS result data.

#
#  weather.ini file should be in /etc/asterisk/local and contain the following
#
# Uncomment the process_condition and Temperature_mode 
# and set accordingly. 
# Set this to use current WX condition. If "NO" then just temperature.
# wunderground is always no condition
# process_condition="YES"
# Set this to "C" or "F" depending on your location
# Temperature_mode="F"
# Set api key for wunderground 
#api_Key=""
# End of weather.ini file

# 11/3/2018 - added v option for just text, no sound files

# source the allstar variables
if [ -f /etc/asterisk/local/weather.ini ] ; then
    . /etc/asterisk/local/weather.ini
else
    # weather.ini file does not exist set defaults
    # Set this to use current WX condition. If "NO" then just temperature.
    # wunderground is always no condition
    process_condition="YES"
    # Set this to "C" or "F" depending on your location
    Temperature_mode="F"
    # Set api key to null
    api_Key=""	
fi

#echo $process_condition
#echo $Temperature_mode
#echo $api_Key

if [ -z $1 ] 
     then 
       echo
       echo "USAGE: weather.sh <local zip, airport code, or w-<wunderground station code>"
       echo 
       echo "Example: weather.sh 19001, weather.sh phl, weather.sh w-WPAGLENB5"
       echo "         Substitute your local codes"
       echo 
       echo "          Add 'v' as second parameter for just display, no sound"
       echo
       echo "Edit /etc/asterisk/local/weather.ini to turn on/off condition reporting, C or F temperature, or to add an api key for wunderground"
       echo
       exit 0 
fi 

destdir="/tmp"

if [[ ${1:0:2} == "w-" ]]
      then
	if [ -z "$api_Key" ]
	  then
		echo -e "\nwunderground api key missing\n"
		exit
	fi
        wcode=${1:2}
        wunder_code=${wcode^^}

#        wunder_code=${1:2:10}
        w_type="wunder"
        wdata=$(curl --connect-timeout 15 -s "https://api.weather.com/v2/pws/observations/current?stationId=$wunder_code&format=json&units=e&apiKey=$api_Key")

	current=$(echo ${wdata#*temp\":} | cut -f1 -d",")  

        # no condition for wunderground
        process_condition="NO"
else
        current=$(curl --connect-timeout 15 -s https://rss.accuweather.com/rss/liveweather_rss.asp\?metric\=0\&locCode\=$1 | perl -ne 'if (/Currently/) {chomp;/\<title\>Currently: (.*)?\<\/title\>/; print "\n$1"; }')
	current=$(awk '$0 ~ /: 0F/ {printf ("");} $0 !~ /: 0F/ {print $0}' <<< $current)
	[ "$current" == "" ] && wxth=$(hvwx -z "$1") && [ $? -eq 0 ] && current=$wxth
        w_type="accu"
fi

if [ -z "$current" ]; then echo "No Report"; exit; fi


if [ "$w_type" == "wunder" ]
    then
       Temperature=$current
       Condition=""
       Temperature=`printf "%.0f\n" $Temperature`
       CTEMP=$(printf "%.0f" `echo "scale=2;(5/9)*($Temperature-32)"|bc`) 
       echo -e "${Temperature}\xc2\xb0F, ${CTEMP}\xc2\xb0C"
    else
       Condition=`echo $current | cut -d ":" -f 1`

#       Temperature=`echo $current | cut -d ":" -f 2 | sed 's/[^0-9]*//g'`

       Temperature=`echo $current | cut -d ":" -f 2`
       Temperature=`echo ${Temperature:0:-1}`

       CTEMP=$(printf "%.0f" `echo "scale=2;(5/9)*($Temperature-32)"|bc`)
       echo -e "${Temperature}\xc2\xb0F, ${CTEMP}\xc2\xb0C / $Condition"
fi

# If v given as second parameter just echo text, no sound
if [ "$2" == "v" ]
  then
    exit
fi

rm -f "$destdir/temperature"
rm -f "$destdir/condition.gsm"

# Check if Celcious look for reasonably sane temperature
if [ "$Temperature_mode" == "C" ]
   then
     Temperature=$CTEMP
     tmin=-60
     tmax=60
   else
     tmin=-100	
     tmax=150
fi

if (( $Temperature < "$tmin" || $Temperature > "$tmax" ))
   then
     rm -f $destdir/temperature
   else
     echo $Temperature > $destdir/temperature
fi

if [ "$process_condition" == "YES" ] 
  
 then
 
  Condition1=`echo $Condition | awk '{print tolower($1)}'`
  Condition2=`echo $Condition | awk '{print tolower($2)}'`
  Condition3=`echo $Condition | awk '{print tolower($3)}'`

#echo -e "\n$Condition1 - $Condition2 - $Condition3"


  if [ ! -z "$Condition1" ]
     then
      ConditionFile1=`/usr/bin/locate /$Condition1.gsm`
  else
      ConditionFile1=""
  fi

  if [ ! -z "$Condition2" ]
     then
      ConditionFile2=`/usr/bin/locate /$Condition2.gsm`
  else
      ConditionFile2=""
  fi

  if [ ! -z "$Condition3" ]
     then
      ConditionFile3=`/usr/bin/locate /$Condition3.gsm`
  else
      ConditionFile3=""
  fi

  if [ -z "$ConditionFile1" ] && [ -z "$ConditionFile2" ] && [ -z "$ConditionFile3" ]
     then
       rm -f $destdir/condition.gsm
     else
       cat $ConditionFile1 $ConditionFile2 $ConditionFile3 > $destdir/condition.gsm
  fi

fi

# echo -e "\n$ConditionFile1 - $ConditionFile2 - $ConditionFile3"


 
