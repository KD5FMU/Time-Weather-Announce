#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Enhanced Weather Script for Global Operations - v2.7.4
#
# Copyright 2025, Jory A. Pratt, W5GLE
# Based on original work by D. Crompton, WA3DSP
# Modified by:              Joe (KD2NFC)
# Enhanced by:              W5GLE team for global operations
# Date:                     2025-10-11
# Version:                  2.7.4
#
# Description:
#   Global weather script with full feature parity to weather.pl:
#   - ICAO airport codes (6000+ airports worldwide)
#   - Postal codes worldwide (US, Canada, Europe, etc.)
#   - 50+ special remote locations (DXpeditions, research stations)
#   - Command line option overrides
#   - Providers: NOAA METAR + Open-Meteo + Nominatim geocoding
#   - Canadian FSA mapping for accurate Ontario locations
#   - Day/night detection for intelligent conditions
#
#   Config: /etc/asterisk/local/weather.ini
#       process_condition="YES"
#       Temperature_mode="F"            # "F" or "C"
#       default_country="us"            # us, ca, fr, de, uk, etc.
#       DEFAULT_PROVIDER="auto"         # auto, metar, or openmeteo
#
#   Outputs:
#       /tmp/temperature
#       /tmp/condition.gsm (or .ulaw)
# ------------------------------------------------------------------------------

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

VERSION="2.7.4"

# ---------- Command Line Options ----------
opt_config_file=""
opt_default_country=""
opt_temperature_mode=""
opt_no_cache=0
opt_no_condition=0
opt_verbose=0
location_arg=""
display_mode=""

show_help(){
  cat <<'EOF'
weather.sh version 2.7.4

Usage: weather.sh [OPTIONS] location_id [v]

Arguments:
  location_id    Postal code, ZIP code, ICAO airport code, or special location
                 ICAO examples: KJFK, EGLL, CYYZ, NZSP, LFPG, RJAA
                 Special: SOUTHPOLE, ALERT, HEARD, BOUVET, MIDWAY, EASTER, etc.
  v              Optional: Display text only (verbose mode), no sound output

Options:
  -c, --config FILE        Use alternate configuration file
  -d, --default-country CC Override default country (us, ca, fr, de, uk, etc.)
  -t, --temperature-mode M Override temperature mode (F or C)
  --no-cache               Disable caching for this request
  --no-condition           Skip weather condition announcements
  -h, --help               Show this help message
  --version                Show version information

Examples:
  Postal Codes:
    weather.sh 90210                    # Beverly Hills, CA (ZIP)
    weather.sh M5H2N2 v                 # Toronto, ON (postal code)
    weather.sh -d fr 75001              # Paris, France
    weather.sh -d de 10115 v            # Berlin, Germany

  ICAO Airport Codes:
    weather.sh KJFK v                   # JFK Airport, New York
    weather.sh EGLL                     # Heathrow, London
    weather.sh CYYZ v                   # Toronto Pearson
    weather.sh LFPG                     # Charles de Gaulle, Paris
    weather.sh RJAA v                   # Narita, Tokyo

  Special Remote Locations:
    weather.sh SOUTHPOLE v              # South Pole Station
    weather.sh ALERT v                  # Alert, Nunavut (northernmost)
    weather.sh HEARD v                  # Heard Island (VK0)
    weather.sh BOUVET v                 # Bouvet Island (3Y0)
    weather.sh EASTER v                 # Easter Island (CE0Y)
    weather.sh MIDWAY v                 # Midway Atoll (KH4)

  With Options:
    weather.sh -t C KJFK                # JFK in Celsius
    weather.sh -d ca M5H2N2             # Force Canadian lookup
    weather.sh --no-cache EGLL v        # Fresh METAR from Heathrow
EOF
  exit 0
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      ;;
    --version)
      echo "weather.sh version $VERSION"
      exit 0
      ;;
    -c|--config)
      opt_config_file="$2"
      shift 2
      ;;
    -d|--default-country)
      opt_default_country="$2"
      shift 2
      ;;
    -t|--temperature-mode)
      opt_temperature_mode="${2^^}"  # Convert to uppercase
      shift 2
      ;;
    --no-cache)
      opt_no_cache=1
      shift
      ;;
    --no-condition)
      opt_no_condition=1
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
    *)
      if [ -z "$location_arg" ]; then
        location_arg="$1"
      else
        display_mode="$1"
      fi
      shift
      ;;
  esac
done

# ---------- Load Config ----------
process_condition="YES"
Temperature_mode="F"
default_country="us"
DEFAULT_PROVIDER="auto"

CONFIG_PATHS=(
  "/etc/asterisk/local/weather.ini"
  "/etc/asterisk/weather.ini"
  "/usr/local/etc/weather.ini"
  "$HOME/.weather.ini"
)

config_loaded=0

# Use custom config if specified
if [ -n "$opt_config_file" ]; then
  if [ -f "$opt_config_file" ]; then
    # shellcheck source=/dev/null
    . "$opt_config_file" 2>/dev/null || true
    config_loaded=1
  else
    echo "ERROR: Custom config file not found: $opt_config_file" >&2
    exit 1
  fi
else
  # Try each config path
  for config_file in "${CONFIG_PATHS[@]}"; do
    if [ -f "$config_file" ]; then
      # shellcheck source=/dev/null
      . "$config_file" 2>/dev/null || true
      config_loaded=1
      break
    fi
  done

  # If no config found, try to create one
  if [ $config_loaded -eq 0 ]; then
    for config_file in "${CONFIG_PATHS[@]}"; do
      # Try to create config file
      config_dir="$(dirname "$config_file")"

      # Create directory if needed and we have permissions
      if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir" 2>/dev/null || continue
      fi

      # Try to create config file
      if cat > "$config_file" 2>/dev/null <<'EOF'
; ============================================================================
; Weather Configuration for saytime-weather
; ============================================================================
; This file controls how weather data is fetched and announced.
; All settings have sensible defaults - no changes required to get started!
; ============================================================================

[weather]

; Temperature display mode: F for Fahrenheit, C for Celsius
; Default: F
Temperature_mode = F

; Process and announce weather conditions (cloudy, rain, clear, etc.)
; Set to NO to only announce temperature
; Default: YES
process_condition = YES

; Default country for ambiguous postal code lookups
; Use ISO 3166-1 alpha-2 country codes: us, ca, de, fr, uk, etc.
; Default: us
default_country = us

; Weather data provider: auto, metar, or openmeteo
; Default: auto (tries best source automatically)
DEFAULT_PROVIDER = auto

; ============================================================================
; USAGE EXAMPLES
; ============================================================================
;
; Test weather for your location:
;   weather.sh KJFK v          # JFK Airport
;   weather.sh 90210 v         # Beverly Hills, CA
;   weather.sh M5H2N2 v        # Toronto, ON
;   weather.sh ALERT v         # Alert, Nunavut
;
; With options:
;   weather.sh -d fr 75001     # Paris with French lookup
;   weather.sh -t C KJFK       # JFK in Celsius
;
; ============================================================================
EOF
      then
        chmod 644 "$config_file" 2>/dev/null || true
        # Now source the newly created config
        # shellcheck source=/dev/null
        . "$config_file" 2>/dev/null || true
        config_loaded=1
        break
      fi
    done
  fi
fi

# Apply command line overrides (take precedence over config)
[ -n "$opt_default_country" ] && default_country="$opt_default_country"
[ -n "$opt_temperature_mode" ] && Temperature_mode="$opt_temperature_mode"
[ "$opt_no_condition" -eq 1 ] && process_condition="NO"
# Note: cache is not applicable to shell script, but we accept the flag for compatibility

case "${DEFAULT_PROVIDER:-}" in
  auto|openmeteo|metar) : ;;
  *) DEFAULT_PROVIDER="auto" ;;
esac
provider="${DEFAULT_PROVIDER}"

destdir="/tmp"

# ---------- Helpers ----------
toupper(){ tr '[:lower:]' '[:upper:]'; }
round(){ awk -v x="$1" 'BEGIN{printf "%.0f", x+0}'; }

# Check if input is ICAO code (4 letters)
is_icao_code(){
  local code="$1"
  [[ "$code" =~ ^[A-Z]{4}$ ]] && return 0
  return 1
}

# Check if input is special location
is_special_location(){
  local loc="$(echo "$1" | toupper | tr -d ' ')"

  case "$loc" in
    # Antarctica
    SOUTHPOLE|MCMURDO|PALMER|VOSTOK|CASEY|MAWSON|DAVIS|SCOTTBASE|SYOWA|CONCORDIA|HALLEY|DUMONT|SANAE)
      return 0 ;;
    # Arctic
    ALERT|EUREKA|THULE|LONGYEARBYEN|BARROW|RESOLUTE|GRISE)
      return 0 ;;
    # Remote Islands / DXpedition Sites
    ASCENSION|STHELENA|TRISTAN|BOUVET|HEARD|KERGUELEN|CROZET|AMSTERDAM|MACQUARIE)
      return 0 ;;
    # Pacific Islands
    MIDWAY|WAKE|JOHNSTON|PALMYRA|JARVIS|HOWLAND|BAKER|KINGMAN)
      return 0 ;;
    # Indian Ocean
    DIEGO|CHAGOS|COCOS|CHRISTMAS)
      return 0 ;;
    # South Atlantic
    FALKLANDS|SOUTHGEORGIA|SOUTHSANDWICH)
      return 0 ;;
    # Pacific Polynesia
    MARQUESAS|EASTER|PITCAIRN|CLIPPERTON|GALAPAGOS)
      return 0 ;;
    # Observatories & Other
    MAUNA|JUNGFRAUJOCH|MCMURDODRY|ATACAMA|GOUGH|MARION|PRINCE|CAMPBELL|AUCKLAND|KERMADEC|CHATHAM)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# Get coordinates for special locations
get_special_coordinates(){
  local loc="$(echo "$1" | toupper | tr -d ' ')"

  case "$loc" in
    # ===== ANTARCTICA =====
    SOUTHPOLE)    echo "-90.0|0.0" ;;
    MCMURDO)      echo "-77.85|166.67" ;;
    PALMER)       echo "-64.77|-64.05" ;;
    VOSTOK)       echo "-78.46|106.84" ;;
    CASEY)        echo "-66.28|110.53" ;;
    MAWSON)       echo "-67.60|62.87" ;;
    DAVIS)        echo "-68.58|77.97" ;;
    SCOTTBASE)    echo "-77.85|166.76" ;;
    SYOWA)        echo "-69.00|39.58" ;;
    CONCORDIA)    echo "-75.10|123.33" ;;
    HALLEY)       echo "-75.58|-26.66" ;;
    DUMONT)       echo "-66.66|140.01" ;;
    SANAE)        echo "-71.67|-2.84" ;;

    # ===== ARCTIC =====
    ALERT)        echo "82.50|-62.35" ;;
    EUREKA)       echo "79.99|-85.93" ;;
    THULE)        echo "76.53|-68.70" ;;
    LONGYEARBYEN) echo "78.22|15.65" ;;
    BARROW)       echo "71.29|-156.79" ;;
    RESOLUTE)     echo "74.72|-94.83" ;;
    GRISE)        echo "76.42|-82.90" ;;

    # ===== REMOTE ISLANDS (DXpedition Sites) =====
    ASCENSION)    echo "-7.95|-14.36" ;;
    STHELENA)     echo "-15.97|-5.72" ;;
    TRISTAN)      echo "-37.11|-12.28" ;;
    BOUVET)       echo "-54.42|3.38" ;;
    HEARD)        echo "-53.10|73.51" ;;
    KERGUELEN)    echo "-49.35|70.22" ;;
    CROZET)       echo "-46.43|51.86" ;;
    AMSTERDAM)    echo "-37.83|77.57" ;;
    MACQUARIE)    echo "-54.62|158.86" ;;

    # ===== PACIFIC ISLANDS =====
    MIDWAY)       echo "28.21|-177.38" ;;
    WAKE)         echo "19.28|166.65" ;;
    JOHNSTON)     echo "16.73|-169.53" ;;
    PALMYRA)      echo "5.89|-162.08" ;;
    JARVIS)       echo "-0.37|-159.99" ;;
    HOWLAND)      echo "0.81|-176.62" ;;
    BAKER)        echo "0.19|-176.48" ;;
    KINGMAN)      echo "6.38|-162.42" ;;

    # ===== INDIAN OCEAN =====
    DIEGO)        echo "-7.26|72.40" ;;
    CHAGOS)       echo "-7.26|72.40" ;;
    COCOS)        echo "-12.19|96.83" ;;
    CHRISTMAS)    echo "-10.49|105.62" ;;

    # ===== SOUTH ATLANTIC =====
    FALKLANDS)    echo "-51.70|-59.52" ;;
    SOUTHGEORGIA) echo "-54.28|-36.51" ;;
    SOUTHSANDWICH) echo "-59.43|-26.35" ;;

    # ===== PACIFIC POLYNESIA =====
    MARQUESAS)    echo "-9.00|-140.00" ;;
    EASTER)       echo "-27.11|-109.36" ;;
    PITCAIRN)     echo "-25.07|-130.10" ;;
    CLIPPERTON)   echo "10.30|-109.22" ;;
    GALAPAGOS)    echo "-0.95|-90.97" ;;

    # ===== MOUNTAIN OBSERVATORIES =====
    MAUNA)        echo "19.54|-155.58" ;;
    JUNGFRAUJOCH) echo "46.55|7.98" ;;

    # ===== EXTREME DESERTS =====
    MCMURDODRY)   echo "-77.85|163.00" ;;
    ATACAMA)      echo "-24.50|-69.25" ;;

    # ===== OTHER NOTABLE REMOTE LOCATIONS =====
    GOUGH)        echo "-40.35|-9.88" ;;
    MARION)       echo "-46.88|37.86" ;;
    PRINCE)       echo "-46.77|37.86" ;;
    CAMPBELL)     echo "-52.55|169.15" ;;
    AUCKLAND)     echo "-50.73|166.09" ;;
    KERMADEC)     echo "-29.25|-177.92" ;;
    CHATHAM)      echo "-43.95|-176.55" ;;

    *) return 1 ;;
  esac
}

# Map METAR codes to condition words
metar_condition_word(){
  local m="$(printf '%s' "$1" | tr -s ' ')"
  [[ "$m" =~ (\+|-)?TS ]] && { echo "thunderstorm"; return; }
  [[ "$m" =~ FZRA|FZDZ|\+RA|-RA|RA ]] && { echo "rain"; return; }
  [[ "$m" =~ SN ]] && { echo "snow"; return; }
  [[ "$m" =~ PL ]] && { echo "hail"; return; }
  [[ "$m" =~ FG ]] && { echo "fog"; return; }
  [[ "$m" =~ BR|HZ|FU|DU|SA ]] && { echo "mist"; return; }
  [[ "$m" =~ OVC|BKN|SCT ]] && { echo "cloudy"; return; }
  [[ "$m" =~ FEW ]] && { echo "clear"; return; }
  [[ "$m" =~ (CLR|SKC) ]] && { echo "clear"; return; }
  echo "clear"
}

# Parse temperature from METAR (returns Fahrenheit)
parse_metar_temp_f(){
  local m="$1" pair chunk sign num t_c_raw
  pair="$(printf '%s' "$m" | grep -oE ' [M]?[0-9]{2}/[M]?[0-9]{2} ' | head -n1 || true)"
  if [ -n "$pair" ]; then
    pair="$(printf '%s' "$pair" | tr -d ' ')"; chunk="${pair%%/*}"
    if [ "${chunk#M}" != "$chunk" ]; then sign='-'; num="${chunk#M}"; else sign=''; num="$chunk"; fi
    num="${num##0}"; [ -z "$num" ] && num=0; t_c_raw="${sign}${num}"
    awk -v c="$t_c_raw" 'BEGIN{printf "%.0f", (c*9/5)+32}'; return 0
  fi
  return 1
}

# Map Open-Meteo WMO weather_code to condition word with day/night detection
openmeteo_condition_word(){
  local code="$1" is_day="${2:-1}"
  case "$code" in
    0) echo "clear" ;;
    1|2) [ "$is_day" = "1" ] && echo "sunny" || echo "clear" ;;  # Day/night aware
    3) echo "cloudy" ;;
    45|48) echo "fog" ;;
    51|53|55|56|57) echo "rain" ;;
    61|63|65|66|67|80|81|82) echo "rain" ;;
    71|73|75|77|85|86) echo "snow" ;;
    95|96|99) echo "thunderstorm" ;;
    *) echo "clear" ;;
  esac
}

# Write condition sound file
write_condition_gsm(){
  local word="$(echo "$1" | awk '{print tolower($1)}')"
  local file1=""

  # Try common sound directories
  for dir in /usr/share/asterisk/sounds/en/wx /var/lib/asterisk/sounds /usr/share/asterisk/sounds/en; do
    if [ -f "${dir}/${word}.gsm" ]; then
      file1="${dir}/${word}.gsm"
      break
    fi
    if [ -f "${dir}/${word}.ulaw" ]; then
      file1="${dir}/${word}.ulaw"
      break
    fi
  done

  if [ -n "$file1" ]; then
    cat "$file1" > "$destdir/condition.gsm"
  else
    rm -f "$destdir/condition.gsm"
  fi
}

# ---------- Canadian FSA to City Mapping ----------
get_canadian_city(){
  local fsa="$1"

  # 3-character FSA mappings (Ontario focus)
  case "$fsa" in
    N7L) echo "Chatham-Kent, Ontario" ;;
    N7M|N7T) echo "Sarnia, Ontario" ;;
    N6A|N6B|N6C|N6E|N6G|N6H|N6J|N6K) echo "London, Ontario" ;;
    N8A|N8H|N8N|N8P|N8R|N8S|N8T|N8V|N8W|N8X|N8Y) echo "Windsor, Ontario" ;;
    N9A|N9B|N9C|N9E|N9G|N9H|N9J|N9K|N9Y) echo "Windsor, Ontario" ;;
    N1G|N1H|N1K|N1L) echo "Guelph, Ontario" ;;
    N3C|N3E|N3H) echo "Cambridge, Ontario" ;;
    N2C|N2E|N2G|N2H|N2J|N2K|N2L|N2M|N2N|N2P|N2R) echo "Kitchener, Ontario" ;;

    # Single-letter fallbacks for major cities
    M*) echo "Toronto, Ontario" ;;
    V*) echo "Vancouver, British Columbia" ;;
    H*) echo "Montreal, Quebec" ;;
    T*) echo "Calgary, Alberta" ;;
    R*) echo "Winnipeg, Manitoba" ;;
    K*) echo "Ottawa, Ontario" ;;
    L*) echo "Mississauga, Ontario" ;;
    N*) echo "London, Ontario" ;;
    P*) echo "Thunder Bay, Ontario" ;;
    S*) echo "Regina, Saskatchewan" ;;
    E*) echo "Moncton, New Brunswick" ;;
    B*) echo "Halifax, Nova Scotia" ;;

    *) return 1 ;;
  esac
}

# ---------- Postal Code to Coordinates (Nominatim) ----------
postal_to_coordinates(){
  local postal="$1"
  local country="${default_country:-us}"

  local url=""
  local postal_upper="$(echo "$postal" | toupper)"

  if [[ "$postal_upper" =~ ^[0-9]{5}$ ]]; then
    # 5-digit: US/Germany/France - use default_country
    url="https://nominatim.openstreetmap.org/search?postalcode=${postal}&country=${country}&format=json&limit=1"
  elif [[ "$postal_upper" =~ ^[A-Z][0-9][A-Z][0-9][A-Z][0-9]$ ]] || [[ "$postal_upper" =~ ^[A-Z][0-9][A-Z].?[0-9][A-Z][0-9]$ ]]; then
    # Canadian postal code (with or without space)
    local normalized="$(echo "$postal_upper" | tr -d ' ' | sed 's/^\([A-Z][0-9][A-Z]\)\([0-9][A-Z][0-9]\)$/\1 \2/')"
    url="https://nominatim.openstreetmap.org/search?postalcode=${normalized}&country=ca&format=json&limit=1"
  else
    # Try generic postal code search
    url="https://nominatim.openstreetmap.org/search?postalcode=${postal}&format=json&limit=1"
  fi

  local response lat lon
  response="$(curl -fsS "$url" 2>/dev/null || true)"

  if [ -n "$response" ] && [ "$response" != "[]" ]; then
    lat="$(echo "$response" | sed -n 's/.*"lat":"\([^"]*\)".*/\1/p' | head -n1)"
    lon="$(echo "$response" | sed -n 's/.*"lon":"\([^"]*\)".*/\1/p' | head -n1)"

    if [ -n "$lat" ] && [ -n "$lon" ]; then
      echo "$lat|$lon"
      return 0
    fi
  fi

  # Canadian FSA fallback
  if [[ "$postal_upper" =~ ^[A-Z][0-9][A-Z] ]]; then
    local fsa="${postal_upper:0:3}"
    local city="$(get_canadian_city "$fsa" || true)"

    if [ -n "$city" ]; then
      sleep 1  # Rate limit
      response="$(curl -fsS "https://nominatim.openstreetmap.org/search?q=$(echo "$city" | sed 's/ /%20/g')&format=json&limit=1" 2>/dev/null || true)"

      if [ -n "$response" ] && [ "$response" != "[]" ]; then
        lat="$(echo "$response" | sed -n 's/.*"lat":"\([^"]*\)".*/\1/p' | head -n1)"
        lon="$(echo "$response" | sed -n 's/.*"lon":"\([^"]*\)".*/\1/p' | head -n1)"

        if [ -n "$lat" ] && [ -n "$lon" ]; then
          echo "$lat|$lon"
          return 0
        fi
      fi
    fi
  fi

  return 1
}

# ---------- Provider: METAR ----------
fetch_metar(){
  local icao="$(echo "$1" | toupper)"
  local metar temp_f cond

  # Try NOAA Aviation Weather API
  metar="$(curl --connect-timeout 15 -fsS "https://aviationweather.gov/api/data/metar?ids=${icao}&format=raw&hours=0&taf=false" 2>/dev/null | head -n1 || true)"

  # Fallback to NWS
  if [ -z "$metar" ]; then
    metar="$(curl --connect-timeout 15 -fsS "https://tgftp.nws.noaa.gov/data/observations/metar/stations/${icao}.TXT" 2>/dev/null | tail -n1 || true)"
  fi

  [ -z "$metar" ] && return 1

  temp_f="$(parse_metar_temp_f "$metar" || true)"
  [ -z "$temp_f" ] && return 1

  cond="$(metar_condition_word "$metar")"
  echo "$temp_f|$cond"
}

# ---------- Provider: Open-Meteo ----------
fetch_openmeteo(){
  local location="$1"

  # Check if it's a special location first
  local coords
  if is_special_location "$location"; then
    coords="$(get_special_coordinates "$location")"
  else
    # Get coordinates from postal code
    coords="$(postal_to_coordinates "$location" || true)"
  fi

  [ -z "$coords" ] && return 1

  lat="${coords%%|*}"
  lon="${coords##*|}"
  [ -z "$lat" ] || [ -z "$lon" ] && return 1

  # Fetch weather from Open-Meteo with is_day for day/night detection
  local data temp code isday
  data="$(curl -fsS "https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,weather_code,is_day&temperature_unit=fahrenheit&timezone=auto" 2>/dev/null || true)"

  temp="$(echo "$data" | sed -n 's/.*"temperature_2m":\s*\([-0-9.]\+\).*/\1/p' | head -n1)"
  code="$(echo "$data" | sed -n 's/.*"weather_code":\s*\([0-9]\+\).*/\1/p' | head -n1)"
  isday="$(echo "$data" | sed -n 's/.*"is_day":\s*\([01]\).*/\1/p' | head -n1)"

  [ -z "$temp" ] && return 1

  local tf="$(round "$temp")"
  [ -z "$isday" ] && isday="1"
  local cond="$(openmeteo_condition_word "${code:-0}" "${isday}")"

  echo "$tf|$cond"
}

# ---------- Main ----------
if [ -z "$location_arg" ]; then
  show_help
fi

arg="$location_arg"
result=""

# Check if ICAO code (4 letters)
if is_icao_code "$(echo "$arg" | toupper)"; then
  if [ "$provider" = "openmeteo" ]; then
    result="$(fetch_openmeteo "$arg" || true)"
    [ -z "$result" ] && result="$(fetch_metar "$arg" || true)"
  else
    result="$(fetch_metar "$arg" || true)"
    [ -z "$result" ] && result="$(fetch_openmeteo "$arg" || true)"
  fi
# Check if special location
elif is_special_location "$arg"; then
  result="$(fetch_openmeteo "$arg" || true)"
else
  # Postal code
  if [ "$provider" = "metar" ]; then
    result="$(fetch_metar "$arg" || true)"
    [ -z "$result" ] && result="$(fetch_openmeteo "$arg" || true)"
  else
    result="$(fetch_openmeteo "$arg" || true)"
    [ -z "$result" ] && result="$(fetch_metar "$arg" || true)"
  fi
fi

[ -z "$result" ] && { echo "No Report"; exit 1; }

temp_f="${result%%|*}"
cond="${result##*|}"
ctemp="$(awk -v f="$temp_f" 'BEGIN{printf "%.0f", (f-32)*5/9}')"

# ---------- Output ----------
if [ "$display_mode" = "v" ]; then
  echo -e "${temp_f}°F, ${ctemp}°C / ${cond}"
  exit 0
fi

rm -f "$destdir/temperature" "$destdir/condition.gsm"

if [ "${Temperature_mode:-F}" = "C" ]; then
  echo "$ctemp" > "$destdir/temperature"
else
  echo "$temp_f" > "$destdir/temperature"
fi

if [ "${process_condition:-YES}" = "YES" ]; then
  write_condition_gsm "$cond"
fi

exit 0
