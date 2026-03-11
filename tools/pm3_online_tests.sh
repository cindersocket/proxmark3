#!/usr/bin/env bash

# Online tests that require actual PM3 device connection
# This is used to make sure that the language for the functions is english instead of the system default language.
LANG=C.UTF-8

PM3PATH="$(dirname "$0")/.."
cd "$PM3PATH" || exit 1

TESTALL=false
TESTDESFIREVALUE=false
TESTDESFIREHAMMER=false
TESTSMARTCARDHAMMER=false
TESTSEOSHAMMER=false

# https://medium.com/@Drew_Stokes/bash-argument-parsing-54f3b81a6a8f
PARAMS=""
while (( "$#" )); do
  case "$1" in
    -h|--help)
      echo """
Usage: $0 [--pm3bin /path/to/pm3] [desfire_value|desfire_hammer|smartcard_hammer|seos_hammer]
    --pm3bin ...:    Specify path to pm3 binary to test
    desfire_value:   Test DESFire value operations with card
    desfire_hammer:  Hammer ISO14443-A APDUs with and without trace
    smartcard_hammer: Hammer smartcard APDUs with and without trace
    seos_hammer:     Hammer SEOS SAM PACS requests with and without trace
    You must specify a test target - no default 'all' for online tests
"""
      exit 0
      ;;
    --pm3bin)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        PM3BIN=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    desfire_value)
      TESTALL=false
      TESTDESFIREVALUE=true
      shift
      ;;
    desfire_hammer)
      TESTALL=false
      TESTDESFIREHAMMER=true
      shift
      ;;
    smartcard_hammer)
      TESTALL=false
      TESTSMARTCARDHAMMER=true
      shift
      ;;
    seos_hammer)
      TESTALL=false
      TESTSEOSHAMMER=true
      shift
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done
# set positional arguments in their proper place
eval set -- "$PARAMS"

C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m' # No Color
C_OK='\xe2\x9c\x94\xef\xb8\x8f'
C_FAIL='\xe2\x9d\x8c'

# Check if file exists
function CheckFileExist() {
  printf "%-40s" "$1 "
  if [ -f "$2" ]; then
    echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK}"
    return 0
  fi
  if ls "$2" 1> /dev/null 2>&1; then
    echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK}"
    return 0
  fi
  echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL}"
  return 1
}

# Execute command and check result
function CheckExecute() {
  printf "%-40s" "$1 "
  
  start=$(date +%s)
  TIMEINFO=""
  RES=$(eval "$2")
  end=$(date +%s)
  delta=$(expr $end - $start)
  if [ $delta -gt 2 ]; then
    TIMEINFO="  ($delta s)"
  fi
  if echo "$RES" | grep -E -q "$3"; then
    echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK} $TIMEINFO"
    return 0
  fi
  echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL} $TIMEINFO"
  echo "Execution trace:"
  echo "$RES"
  return 1
}

echo -e "${C_BLUE}Iceman Proxmark3 online test tool${C_NC}"
echo ""
echo "work directory: $(pwd)"

if command -v git >/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo -n "git branch: "
  git describe --all
  echo -n "git sha: "
  git rev-parse HEAD
  echo ""
fi

# Check that user specified a test
if [ "$TESTDESFIREVALUE" = false ] && [ "$TESTDESFIREHAMMER" = false ] && [ "$TESTSMARTCARDHAMMER" = false ] && [ "$TESTSEOSHAMMER" = false ]; then
  echo "Error: You must specify a test target. Use -h for help."
  exit 1
fi

while true; do
    # DESFire value tests
    if $TESTDESFIREVALUE; then
      echo -e "\n${C_BLUE}Testing DESFire card value operations${C_NC} ${PM3BIN:=./pm3}"
      echo "  PLACE A FACTORY DESFIRE CARD ON THE READER NOW"
      if ! CheckFileExist "pm3 exists"               "$PM3BIN"; then break; fi
      
      echo "  Formatting card to clean state..."
      if ! CheckExecute "format card"                  "$PM3BIN -c 'hf mfdes formatpicc'" "done"; then break; fi
      
      echo "  Running value operation tests..."
      if ! CheckExecute "card auth test"          "$PM3BIN -c 'hf mfdes auth -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none'" "authenticated.*succes"; then break; fi
      if ! CheckExecute "card app creation"       "$PM3BIN -c 'hf mfdes createapp --aid 123456 --ks1 0F --ks2 0E --numkeys 1'" "successfully created"; then break; fi
      if ! CheckExecute "card value file creation" "$PM3BIN -c 'hf mfdes createvaluefile --aid 123456 --fid 02 --lower 00000000 --upper 000003E8 --value 00000064'" "created successfully"; then break; fi
      if ! CheckExecute "card value get plain"    "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op get -m plain'" "Value.*100"; then break; fi
      if ! CheckExecute "card value get mac"      "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op get -m mac'" "Value.*100"; then break; fi
      if ! CheckExecute "card value credit plain" "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op credit -d 00000032 -m plain'" "Value.*changed"; then break; fi
      if ! CheckExecute "card value get after credit" "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op get -m plain'" "Value.*150"; then break; fi
      if ! CheckExecute "card value credit mac"   "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op credit -d 0000000A -m mac'" "Value.*changed"; then break; fi
      if ! CheckExecute "card value debit plain"  "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op debit -d 00000014 -m plain'" "Value.*changed"; then break; fi
      if ! CheckExecute "card value debit mac"    "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op debit -d 00000014 -m mac'" "Value.*changed"; then break; fi
      if ! CheckExecute "card value final check"  "$PM3BIN -c 'hf mfdes value --aid 123456 --fid 02 --op get -m mac'" "Value.*120"; then break; fi
      if ! CheckExecute "card cleanup"            "$PM3BIN -c 'hf mfdes selectapp --aid 000000; hf mfdes auth -n 0 -t 2tdea -k 00000000000000000000000000000000 --kdf none; hf mfdes deleteapp --aid 123456'" "application.*deleted"; then break; fi
      echo "  card value operation tests completed successfully!"
    fi

    if $TESTDESFIREHAMMER; then
      echo -e "\n${C_BLUE}Testing DESFire ISO14443-A APDU hammer${C_NC} ${PM3BIN:=./pm3}"
      echo "  PLACE A DESFIRE CARD ON THE READER NOW"
      if ! CheckFileExist "pm3 exists" "$PM3BIN"; then break; fi

      if ! CheckExecute "reader alive" "$PM3BIN -c 'hw ping'" "Ping.*OK|received packet"; then break; fi
      if ! CheckExecute "trace-on hammer" "$PM3BIN -c 'script run tests/hf_14a_desfire_hammer -i 750'" "HAMMER PASS"; then break; fi
      if ! CheckExecute "reader alive after trace-on" "$PM3BIN -c 'hw ping'" "Ping.*OK|received packet"; then break; fi
      if ! CheckExecute "trace saturation visible" "$PM3BIN -c 'trace list -1 -t 14a'" "Trace saturated"; then break; fi

      if ! CheckExecute "clear trace buffer" "$PM3BIN -c 'data clear'" ".*"; then break; fi
      if ! CheckExecute "cli no-trace smoke" "$PM3BIN -c 'hf 14a apdu -s --no-trace -d 9060000000'" "<<< status: 91 00"; then break; fi
      if ! CheckExecute "clear trace buffer again" "$PM3BIN -c 'data clear'" ".*"; then break; fi
      if ! CheckExecute "trace-off hammer" "$PM3BIN -c 'script run tests/hf_14a_desfire_hammer -i 250 -n'" "HAMMER PASS"; then break; fi
      if ! CheckExecute "reader alive after trace-off" "$PM3BIN -c 'hw ping'" "Ping.*OK|received packet"; then break; fi
      if ! CheckExecute "trace stays empty" "$PM3BIN -c 'trace list -1 -t 14a'" "there is no trace"; then break; fi

      echo "  DESFire hammer tests completed successfully!"
    fi

    if $TESTSMARTCARDHAMMER; then
      echo -e "\n${C_BLUE}Testing smartcard trace hammer${C_NC} ${PM3BIN:=./pm3}"
      echo "  PLACE A COMPATIBLE CONTACT SMARTCARD ON THE READER NOW"
      if ! CheckFileExist "pm3 exists" "$PM3BIN"; then break; fi

      APDU="00A404000E315041592E5359532E444446303100"
      EXPECTED_SW="9000"

      if ! CheckExecute "reader alive" "$PM3BIN -c 'hw ping'" "Ping.*OK|received packet"; then break; fi
      if ! CheckExecute "trace-on hammer" "$PM3BIN -c 'script run tests/smartcard_trace_hammer -i 750 -a $APDU -w $EXPECTED_SW'" "HAMMER PASS"; then break; fi
      if ! CheckExecute "reader alive after trace-on" "$PM3BIN -c 'hw ping'" "Ping.*OK|received packet"; then break; fi
      if ! CheckExecute "trace saturation visible" "$PM3BIN -c 'trace list -1 -t 7816'" "Trace saturated"; then break; fi

      if ! CheckExecute "clear trace buffer" "$PM3BIN -c 'data clear'" ".*"; then break; fi
      if ! CheckExecute "cli no-trace smoke" "$PM3BIN -c 'smart raw -s --no-trace -0 -d $APDU'" "9000|Response data"; then break; fi
      if ! CheckExecute "clear trace buffer again" "$PM3BIN -c 'data clear'" ".*"; then break; fi
      if ! CheckExecute "trace-off hammer" "$PM3BIN -c 'script run tests/smartcard_trace_hammer -i 250 -n -a $APDU -w $EXPECTED_SW'" "HAMMER PASS"; then break; fi
      if ! CheckExecute "reader alive after trace-off" "$PM3BIN -c 'hw ping'" "Ping.*OK|received packet"; then break; fi
      if ! CheckExecute "trace stays empty" "$PM3BIN -c 'trace list -1 -t 7816'" "there is no trace"; then break; fi

      echo "  Smartcard hammer tests completed successfully!"
    fi

    if $TESTSEOSHAMMER; then
      echo -e "\n${C_BLUE}Testing SEOS SAM hammer${C_NC} ${PM3BIN:=./pm3}"
      echo "  PLACE A SEOS CARD ON THE READER AND INSERT A HID SAM NOW"
      if ! CheckFileExist "pm3 exists" "$PM3BIN"; then break; fi

      if ! CheckExecute "reader alive" "$PM3BIN -c 'hw ping'" "Ping.*OK|received packet"; then break; fi
      if ! CheckExecute "trace-on hammer" "$PM3BIN -c 'script run tests/hf_seos_sam_hammer -i 750'" "HAMMER PASS"; then break; fi
      if ! CheckExecute "reader alive after trace-on" "$PM3BIN -c 'hw ping'" "Ping.*OK|received packet"; then break; fi
      if ! CheckExecute "trace saturation visible" "$PM3BIN -c 'trace list -1 -t seos'" "Trace saturated"; then break; fi

      if ! CheckExecute "clear trace buffer" "$PM3BIN -c 'data clear'" ".*"; then break; fi
      if ! CheckExecute "cli no-trace smoke" "$PM3BIN -c 'hf seos sam --no-trace'" "No PACS data|Physical Access Bits|ObjectID|Tag"; then break; fi
      if ! CheckExecute "clear trace buffer again" "$PM3BIN -c 'data clear'" ".*"; then break; fi
      if ! CheckExecute "trace-off hammer" "$PM3BIN -c 'script run tests/hf_seos_sam_hammer -i 250 -n'" "HAMMER PASS"; then break; fi
      if ! CheckExecute "reader alive after trace-off" "$PM3BIN -c 'hw ping'" "Ping.*OK|received packet"; then break; fi
      if ! CheckExecute "trace stays empty" "$PM3BIN -c 'trace list -1 -t seos'" "there is no trace"; then break; fi

      echo "  SEOS hammer tests completed successfully!"
    fi
  
  echo -e "\n------------------------------------------------------------"
  echo -e "Tests [ ${C_GREEN}OK${C_NC} ] ${C_OK}\n"
  exit 0
done
echo -e "\n------------------------------------------------------------"
echo -e "\nTests [ ${C_RED}FAIL${C_NC} ] ${C_FAIL}\n"
exit 1
