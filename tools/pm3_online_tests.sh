#!/usr/bin/env bash

# Online tests that require actual PM3 device connection
# This is used to make sure that the language for the functions is english instead of the system default language.
LANG=C.UTF-8

PM3PATH="$(dirname "$0")/.."
cd "$PM3PATH" || exit 1

TESTALL=false
TESTDESFIREVALUE=false
TESTHIDWIEGAND=false
TESTMFHIDENCODE=false
TESTLFT55XXROUNDTRIP=false
TESTLFT55XXDETECT=false
TESTLFT55XXDETECTWAKEUP=false
TESTLFT55XXSMOKE=false
NEED_MF_HID_ENCODE_WIPE=false
TESTMANUAL=false

# https://medium.com/@Drew_Stokes/bash-argument-parsing-54f3b81a6a8f
PARAMS=""
while (( "$#" )); do
  case "$1" in
    -h|--help)
      echo """
Usage: $0 [--pm3bin /path/to/pm3] [desfire_value|hid_wiegand|mf_hid_encode|lf_t55xx_roundtrip|lf_t55xx_detect|lf_t55xx_detect_wakeup|lf_t55xx_smoke]
    --pm3bin ...:    Specify path to pm3 binary to test
    --manual ...:    Pause after successful online LF HID clone/read checks for external reader verification
    desfire_value:   Test DESFire value operations with card
    hid_wiegand:     Test LF HID T55xx clone and PM3 readback flows
    mf_hid_encode:   Test MIFARE Classic HID encoding flows
    lf_t55xx_roundtrip:
                     Test first-class T55x7 clone+reader credential round trips
    lf_t55xx_detect:
                     Test lf t55xx detect across representative T55x7 configs
    lf_t55xx_detect_wakeup:
                     Test lf t55xx detect wakeup/init-delay recovery on T55x7
    lf_t55xx_smoke:  Run T55x7 round-trip, detect, and wakeup tests
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
    --manual)
      TESTMANUAL=true
      shift
      ;;
    desfire_value)
      TESTALL=false
      TESTDESFIREVALUE=true
      shift
      ;;
    hid_wiegand)
      TESTALL=false
      TESTHIDWIEGAND=true
      shift
      ;;
    mf_hid_encode)
      TESTALL=false
      TESTMFHIDENCODE=true
      shift
      ;;
    lf_t55xx_roundtrip)
      TESTALL=false
      TESTLFT55XXROUNDTRIP=true
      shift
      ;;
    lf_t55xx_detect)
      TESTALL=false
      TESTLFT55XXDETECT=true
      shift
      ;;
    lf_t55xx_detect_wakeup)
      TESTALL=false
      TESTLFT55XXDETECTWAKEUP=true
      shift
      ;;
    lf_t55xx_smoke)
      TESTALL=false
      TESTLFT55XXSMOKE=true
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

function CheckOutputContains() {
  printf "%-40s" "$1 "
  RES=$(eval "$2")
  if printf '%s' "$RES" | grep -F -q "$3"; then
    echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK}"
    return 0
  fi
  echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL}"
  echo "Execution trace:"
  echo "$RES"
  return 1
}

function CheckOutputContainsAll() {
  local LABEL="$1"
  local CMD="$2"
  shift 2
  printf "%-40s" "$LABEL "
  RES=$(eval "$CMD")
  while [ "$#" -gt 0 ]; do
    if ! printf '%s' "$RES" | grep -F -q "$1"; then
      echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL}"
      echo "Execution trace:"
      echo "$RES"
      return 1
    fi
    shift
  done
  echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK}"
  return 0
}

function CheckLfHidCloneReadback() {
  printf "%-40s" "$1 "

  start=$(date +%s)
  TIMEINFO=""
  RES=$($PM3BIN -c "lf hid clone $2; lf hid reader" 2>&1)
  end=$(date +%s)
  delta=$(expr $end - $start)
  if [ $delta -gt 2 ]; then
    TIMEINFO="  ($delta s)"
  fi

  if echo "$RES" | grep -E -q "$3"; then
    echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK} $TIMEINFO"
    if $TESTMANUAL; then
      echo "  Manual check: $4"
      WaitForEnter "PRESENT THE T55xx TAG TO ANOTHER READER AND CONFIRM: $4"
    fi
    return 0
  fi

  echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL} $TIMEINFO"
  echo "Execution trace:"
  echo "$RES"
  return 1
}

function HexToBin() {
  local hex="${1^^}"
  local bin=""
  local i ch
  for ((i=0; i<${#hex}; i++)); do
    ch="${hex:i:1}"
    case "$ch" in
      0) bin+="0000" ;;
      1) bin+="0001" ;;
      2) bin+="0010" ;;
      3) bin+="0011" ;;
      4) bin+="0100" ;;
      5) bin+="0101" ;;
      6) bin+="0110" ;;
      7) bin+="0111" ;;
      8) bin+="1000" ;;
      9) bin+="1001" ;;
      A) bin+="1010" ;;
      B) bin+="1011" ;;
      C) bin+="1100" ;;
      D) bin+="1101" ;;
      E) bin+="1110" ;;
      F) bin+="1111" ;;
      *) return 1 ;;
    esac
  done
  printf "%s" "$bin"
}

function RestoreMfHidEncodeSector0() {
  $PM3BIN -c "hf mf wrbl --blk 3 -b -k 89ECA97F8C2A -d FFFFFFFFFFFFFF078069FFFFFFFFFFFF" >/dev/null 2>&1 || true
  $PM3BIN -c "hf mf wrbl --blk 3 -k FFFFFFFFFFFF -d FFFFFFFFFFFFFF078069FFFFFFFFFFFF" >/dev/null 2>&1 || true
  $PM3BIN -c "hf mf wrbl --blk 3 -k A0A1A2A3A4A5 -d FFFFFFFFFFFFFF078069FFFFFFFFFFFF" >/dev/null 2>&1 || true
  $PM3BIN -c "hf mf wrbl --blk 2 -k FFFFFFFFFFFF -d 00000000000000000000000000000000; \
hf mf wrbl --blk 1 -k FFFFFFFFFFFF -d 00000000000000000000000000000000" >/dev/null 2>&1 || return 1
}

function RestoreMfHidEncodeSector1() {
  $PM3BIN -c "hf mf wrbl --blk 7 -b -k 204752454154 -d FFFFFFFFFFFFFF078069FFFFFFFFFFFF" >/dev/null 2>&1 || true
  $PM3BIN -c "hf mf wrbl --blk 7 -k FFFFFFFFFFFF -d FFFFFFFFFFFFFF078069FFFFFFFFFFFF" >/dev/null 2>&1 || true
  $PM3BIN -c "hf mf wrbl --blk 7 -k 484944204953 -d FFFFFFFFFFFFFF078069FFFFFFFFFFFF" >/dev/null 2>&1 || true
  $PM3BIN -c "hf mf wrbl --blk 6 -k FFFFFFFFFFFF -d 00000000000000000000000000000000; \
hf mf wrbl --blk 5 -k FFFFFFFFFFFF -d 00000000000000000000000000000000; \
hf mf wrbl --blk 4 -k FFFFFFFFFFFF -d 00000000000000000000000000000000" >/dev/null 2>&1 || return 1
}

function RestoreMfHidEncodeCard() {
  RestoreMfHidEncodeSector0 || return 1
  RestoreMfHidEncodeSector1 || return 1

  local verify
  verify=$($PM3BIN -c 'hf mf rdbl --blk 1 -k FFFFFFFFFFFF; hf mf rdbl --blk 2 -k FFFFFFFFFFFF; hf mf rdbl --blk 4 -k FFFFFFFFFFFF; hf mf rdbl --blk 5 -k FFFFFFFFFFFF; hf mf rdbl --blk 6 -k FFFFFFFFFFFF' 2>&1) || return 1
  echo "$verify" | grep -E -q "  1 \| 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" \
    && echo "$verify" | grep -E -q "  2 \| 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" \
    && echo "$verify" | grep -E -q "  4 \| 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" \
    && echo "$verify" | grep -E -q "  5 \| 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" \
    && echo "$verify" | grep -E -q "  6 \| 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
}

function CleanupMfHidEncodeCard() {
  if [ "$NEED_MF_HID_ENCODE_WIPE" != true ]; then
    return 0
  fi

  echo ""
  printf "%-40s" "hf mf encodehid cleanup "
  if RestoreMfHidEncodeCard; then
    echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK}"
  else
    echo -e "[ ${C_YELLOW}WARN${C_NC} ]"
    echo "Cleanup could not restore sectors 0 and 1 to the default usable state."
  fi
}

function CheckMfHidEncodeRoundTrip() {
  printf "%-40s" "$1 "

  start=$(date +%s)
  TIMEINFO=""
  if ! RestoreMfHidEncodeCard >/dev/null 2>&1; then
    echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL}"
    echo "Execution trace:"
    echo "Failed to restore sectors 0 and 1 to the default usable state before running the test."
    return 1
  fi

  RES=$($PM3BIN -c "hf mf encodehid $2; hf mf rdbl --blk 5 -k 484944204953" 2>&1)
  end=$(date +%s)
  delta=$(expr $end - $start)
  if [ $delta -gt 2 ]; then
    TIMEINFO="  ($delta s)"
  fi

  BLOCKHEX=$(printf "%s\n" "$RES" | LC_ALL=C grep -aoE '02( [0-9A-F]{2}){15}' | tail -n1 | tr -d ' ')
  if [ -z "$BLOCKHEX" ]; then
    echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL} $TIMEINFO"
    echo "Execution trace:"
    echo "$RES"
    return 1
  fi

  if [[ "$BLOCKHEX" != 02* ]]; then
    echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL} $TIMEINFO"
    echo "Expected block 5 to start with the 0x02 HID marker."
    echo "Actual block 5 data: $BLOCKHEX"
    echo "Execution trace:"
    echo "$RES"
    return 1
  fi

  RAWPAYLOAD=${BLOCKHEX#02}
  PAYLOADBIN=$(HexToBin "$RAWPAYLOAD") || {
    echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL} $TIMEINFO"
    echo "Execution trace:"
    echo "$RES"
    return 1
  }

  while [[ "$PAYLOADBIN" == 0* ]]; do
    PAYLOADBIN=${PAYLOADBIN#0}
  done

  if [[ "$PAYLOADBIN" != 1* ]]; then
    echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL} $TIMEINFO"
    echo "Expected a sentinel-prefixed Wiegand payload in block 5."
    echo "Actual payload bits: $PAYLOADBIN"
    echo "Execution trace:"
    echo "$RES"
    return 1
  fi

  RECOVERED_BIN=${PAYLOADBIN#1}
  if [ "$RECOVERED_BIN" != "$3" ]; then
    echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL} $TIMEINFO"
    echo "Expected Wiegand bits: $3"
    echo "Actual Wiegand bits:   $RECOVERED_BIN"
    echo "Execution trace:"
    echo "$RES"
    return 1
  fi

  DECODE_RES=$($PM3BIN -c "wiegand decode --bin $RECOVERED_BIN" 2>&1)
  if echo "$DECODE_RES" | grep -E -q "$4"; then
    echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK} $TIMEINFO"
    return 0
  fi

  echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL} $TIMEINFO"
  echo "Decode trace:"
  echo "$DECODE_RES"
  return 1
}

function CheckMfHidEncodeCleanup() {
  printf "%-40s" "$1 "
  RES=$($PM3BIN -c 'hf mf rdbl --blk 1 -k FFFFFFFFFFFF; hf mf rdbl --blk 2 -k FFFFFFFFFFFF; hf mf rdbl --blk 4 -k FFFFFFFFFFFF; hf mf rdbl --blk 5 -k FFFFFFFFFFFF; hf mf rdbl --blk 6 -k FFFFFFFFFFFF' 2>&1)
  if echo "$RES" | grep -E -q "  1 \| 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" \
    && echo "$RES" | grep -E -q "  2 \| 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" \
    && echo "$RES" | grep -E -q "  4 \| 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" \
    && echo "$RES" | grep -E -q "  5 \| 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" \
    && echo "$RES" | grep -E -q "  6 \| 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"; then
    echo -e "[ ${C_GREEN}OK${C_NC} ] ${C_OK}"
    return 0
  fi

  echo -e "[ ${C_RED}FAIL${C_NC} ] ${C_FAIL}"
  echo "Execution trace:"
  echo "$RES"
  return 1
}

function WaitForEnter() {
  echo ""
  echo "$1"
  echo "Press Enter when ready, or Ctrl-C to abort."
  if [ -r /dev/tty ]; then
    stty sane < /dev/tty 2>/dev/null || true
    IFS= read -r < /dev/tty
  else
    read -r
  fi
}

function WaitForUserLFTag() {
  echo "  $1"
  if [ -t 0 ]; then
    read -r -p "  Press Enter when ready..." _
  fi
}

function BackupT55xxTag() {
  T55XX_DUMP_BASE=$(mktemp /tmp/pm3-t55xx-online-XXXXXX)
  rm -f "$T55XX_DUMP_BASE"
  local RES
  RES=$($PM3BIN -c "lf t55xx detect; lf t55xx dump -f $T55XX_DUMP_BASE")
  if [ ! -f "${T55XX_DUMP_BASE}.bin" ]; then
    echo "Failed to save T55xx dump"
    echo "$RES"
    return 1
  fi
  T55XX_BACKUP_ACTIVE=true
  return 0
}

function GetT55xxConfigBlock0() {
  eval "$PM3BIN -c 'lf t55xx config $1'" | sed -n 's/.*Block0............ \([0-9A-F]*\).*/\1/p' | tail -n 1
}

function RestoreT55xxTag() {
  if [ "$T55XX_BACKUP_ACTIVE" != true ] || [ ! -f "${T55XX_DUMP_BASE}.bin" ]; then
    return 0
  fi
  CheckExecute "restore T55xx tag" "$PM3BIN -c 'lf t55xx restore -f ${T55XX_DUMP_BASE}.bin'" "Done|Restoring" || return 1
  return 0
}

function CleanupT55xxBackupFiles() {
  if [ -n "$T55XX_DUMP_BASE" ]; then
    rm -f "${T55XX_DUMP_BASE}.bin" "${T55XX_DUMP_BASE}.json"
  fi
  T55XX_BACKUP_ACTIVE=false
}

function CheckT55xxDetectResult() {
  local LABEL="$1"
  local MOD="$2"
  local RATE="$3"
  local BLOCK0="$4"
  CheckOutputContainsAll "$LABEL" "$PM3BIN -c 'lf t55xx detect'" \
    "Chip type......... T55x7" \
    "Modulation........ $MOD" \
    "Bit rate.......... $RATE" \
    "Block0............ $BLOCK0"
}

function CheckT55xxDetectFixture() {
  local LABEL="$1"
  local CLONE_CMD="$2"
  local MOD="$3"
  local RATE="$4"
  local BLOCK0="$5"

  if ! CheckExecute "clone $LABEL" "$CLONE_CMD" "Done!|Tag T55x7 written"; then return 1; fi
  if ! CheckT55xxDetectResult "detect $LABEL" "$MOD" "$RATE" "$BLOCK0"; then return 1; fi
  return 0
}

function CheckT55xxDetectConfigFixture() {
  local LABEL="$1"
  local CONFIG_ARGS="$2"
  local EXPECT_MOD="$3"
  local EXPECT_RATE="$4"
  local EXPECT_ST="$5"
  local BLOCK0

  BLOCK0=$(GetT55xxConfigBlock0 "$CONFIG_ARGS")
  if [ -z "$BLOCK0" ]; then
    echo "Failed to derive block0 for $LABEL using: $CONFIG_ARGS"
    return 1
  fi

  if ! CheckExecute "write $LABEL block0" "$PM3BIN -c 'lf t55xx write -b 0 -d $BLOCK0'" "Writing page 0  block: 00|Done"; then
    return 1
  fi

  CheckOutputContainsAll "detect $LABEL" "$PM3BIN -c 'lf t55xx detect'" \
    "Modulation........ $EXPECT_MOD" \
    "Bit rate.......... $EXPECT_RATE" \
    "Seq. terminator... $EXPECT_ST" \
    "Block0............ $BLOCK0" || return 1

  return 0
}

function CheckT55xxDetectWakeupFixture() {
  local AOR_POR_BLOCK0="$2"

  if ! CheckExecute "clone wakeup fixture" "$PM3BIN -c 'lf hid clone -w H10301 --fc 31 --cn 337'" "Done!"; then return 1; fi
  if ! CheckExecute "enable AOR/POR" "$PM3BIN -c 'lf t55xx write -b 0 -d $AOR_POR_BLOCK0'" "Writing page 0  block: 00"; then return 1; fi
  if ! CheckOutputContainsAll "detect wakeup fixture" "$PM3BIN -c 'lf t55xx detect'" \
    "Chip type......... T55x7" \
    "Modulation........ FSK2a" \
    "Bit rate.......... 4 - RF/50" \
    "Block0............ $AOR_POR_BLOCK0"; then return 1; fi
  return 0
}

function CheckLFReaderRoundTripFixture() {
  local LABEL="$1"
  local CLONE_CMD="$2"
  local READER_CMD="$3"
  local EXPECT_RE="$4"

  if ! CheckExecute "clone $LABEL" "$CLONE_CMD" "Done!|Tag T55x7 written"; then return 1; fi
  if ! CheckExecute "read $LABEL" "$READER_CMD" "$EXPECT_RE"; then return 1; fi
  return 0
}

function CheckLFReaderRoundTripContainsAll() {
  local LABEL="$1"
  local CLONE_CMD="$2"
  local READER_CMD="$3"
  shift 3

  if ! CheckExecute "clone $LABEL" "$CLONE_CMD" "Done!|Tag T55x7 written"; then return 1; fi
  if ! CheckOutputContainsAll "read $LABEL" "$READER_CMD" "$@"; then return 1; fi
  return 0
}

function RunLFHidCloneFixtures() {
  if ! CheckLfHidCloneReadback "lf hid clone H10301 26-bit" "-w H10301 --fc 118 --cn 1603" "H10301.*FC: 118.*CN: 1603" "H10301 26-bit, FC 118, CN 1603"; then return 1; fi
  if ! CheckLfHidCloneReadback "lf hid clone C1k35s 35-bit" "-w C1k35s --fc 118 --cn 1603" "C1k35s.*FC: 118.*CN: 1603" "C1k35s 35-bit, FC 118, CN 1603"; then return 1; fi
  if ! CheckLfHidCloneReadback "lf hid clone H10304 37-bit" "-w H10304 --fc 118 --cn 1603" "H10304.*FC: 118.*CN: 1603" "H10304 37-bit, FC 118, CN 1603"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "HID 48 raw" "$PM3BIN -c 'lf hid clone -r 01400076000c86'" "$PM3BIN -c 'lf hid reader'" "HID Corporate 1000 48-bit"; then return 1; fi
  return 0
}

function RunLFT55xxRoundTripFixtures() {
  if ! RunLFHidCloneFixtures; then return 1; fi

  if ! CheckLFReaderRoundTripFixture "AWID 26" "$PM3BIN -c 'lf awid clone --fmt 26 --fc 224 --cn 1337'" "$PM3BIN -c 'lf awid reader'" "AWID - len: 26 FC: 224 Card: 1337"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Destron" "$PM3BIN -c 'lf destron clone --uid 1A2B3C4D5E'" "$PM3BIN -c 'lf destron reader'" "FDX-A FECAVA Destron: 1A2B3C4D5E"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "EM410x" "$PM3BIN -c 'lf em 410x clone --id 0F0368568B'" "$PM3BIN -c 'lf em 410x reader'" "EM 410x ID 0F0368568B"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "FDX-B animal" "$PM3BIN -c 'lf fdxb clone --country 999 --national 112233 --animal'" "$PM3BIN -c 'lf fdxb reader'" "Animal ID.*999-000000112233"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Gallagher" "$PM3BIN -c 'lf gallagher clone --raw 0FFD5461A9DA1346B2D1AC32'" "$PM3BIN -c 'lf gallagher reader'" "GALLAGHER - Region: 1 Facility: 16640 Card No\\.: 201 Issue Level: 1"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Guardall G-Prox II" "$PM3BIN -c 'lf gproxii clone --xor 102 --fmt 26 --fc 123 --cn 11223'" "$PM3BIN -c 'lf gproxii reader'" "G-Prox-II - Len: 26 FC: 123 Card: 11223"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Idteck" "$PM3BIN -c 'lf idteck clone --raw 4944544B351FBE4B'" "$PM3BIN -c 'lf idteck reader'" "Raw: 4944544B351FBE4B"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Indala 26" "$PM3BIN -c 'lf indala clone --fc 123 --cn 1337'" "$PM3BIN -c 'lf indala reader'" "Fmt 26 FC: 123 Card: 1337"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "ioProx" "$PM3BIN -c 'lf io clone --vn 1 --fc 101 --cn 1337'" "$PM3BIN -c 'lf io reader'" "IO Prox - XSF\\(01\\)65:01337"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Jablotron" "$PM3BIN -c 'lf jablotron clone --cn 01B669'" "$PM3BIN -c 'lf jablotron reader'" "Printed: 1410-00-0002-1669"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "KERI MS" "$PM3BIN -c 'lf keri clone -t m --fc 6 --cn 12345'" "$PM3BIN -c 'lf keri reader'" "Descrambled MS - FC: 6 Card: 12345"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "NEDAP 64b" "$PM3BIN -c 'lf nedap clone --st 1 --cc 291 --id 12345'" "$PM3BIN -c 'lf nedap reader'" "NEDAP \\(64b\\) - ID: 12345 subtype: 1 customer code: 291 / 0x123"; then return 1; fi
  if ! CheckLFReaderRoundTripContainsAll "NexWatch Nexkey" "$PM3BIN -c 'lf nexwatch clone --cn 521512301 -m 1 --nc'" "$PM3BIN -c 'lf nexwatch reader'" "fingerprint : Nexkey" "88bit id : 521512301"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Noralsy" "$PM3BIN -c 'lf noralsy clone --cn 112233'" "$PM3BIN -c 'lf noralsy reader'" "Noralsy - Card: 112233, Year: 2000"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "PAC/Stanley" "$PM3BIN -c 'lf pac clone --cn CD4F5552'" "$PM3BIN -c 'lf pac reader'" "PAC/Stanley - Card: CD4F5552"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Paradox" "$PM3BIN -c 'lf paradox clone --fc 96 --cn 40426'" "$PM3BIN -c 'lf paradox reader'" "Paradox - ID: .* FC: 96 Card: 40426"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Presco" "$PM3BIN -c 'lf presco clone -c 1E8021D9'" "$PM3BIN -c 'lf presco reader'" "Presco Site code: 30 User code: 8665 Full code: 1E8021D9"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Pyramid" "$PM3BIN -c 'lf pyramid clone --fc 123 --cn 11223'" "$PM3BIN -c 'lf pyramid reader'" "Pyramid - len: 26, FC: 123 Card: 11223"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Securakey" "$PM3BIN -c 'lf securakey clone --raw 7FCB400001ADEA5344300000'" "$PM3BIN -c 'lf securakey reader'" "Securakey - len: 26 FC: 0x35 Card: 64169"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Viking" "$PM3BIN -c 'lf viking clone --cn 01A337'" "$PM3BIN -c 'lf viking reader'" "Viking - Card 0001A337"; then return 1; fi
  if ! CheckLFReaderRoundTripFixture "Visa2000" "$PM3BIN -c 'lf visa2000 clone --cn 112233'" "$PM3BIN -c 'lf visa2000 reader'" "Visa2000 - Card 112233"; then return 1; fi
  return 0
}

trap CleanupMfHidEncodeCard EXIT

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
if [ "$TESTLFT55XXSMOKE" = true ]; then
  TESTLFT55XXROUNDTRIP=true
  TESTLFT55XXDETECT=true
  TESTLFT55XXDETECTWAKEUP=true
fi

if [ "$TESTDESFIREVALUE" = false ] && [ "$TESTHIDWIEGAND" = false ] && [ "$TESTMFHIDENCODE" = false ] && [ "$TESTLFT55XXROUNDTRIP" = false ] && [ "$TESTLFT55XXDETECT" = false ] && [ "$TESTLFT55XXDETECTWAKEUP" = false ]; then
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

    if $TESTHIDWIEGAND; then
      echo -e "\n${C_BLUE}Testing LF HID T55xx clone flows${C_NC} ${PM3BIN:=./pm3}"
      if ! CheckFileExist "pm3 exists"               "$PM3BIN"; then break; fi

      if ! CheckExecute "lf hid clone raw oversize"    "$PM3BIN -c 'lf hid clone -r 01400076000c86' 2>&1" "LF HID clone supports only packed credentials up to 37 bits"; then break; fi
      if ! CheckExecute "lf hid clone bin oversize"    "PAT=\$(printf '01%.0s' {1..48}); $PM3BIN -c \"lf hid clone --bin \$PAT\" 2>&1" "Packed HID encoding supports up to 84 Wiegand bits"; then break; fi
      if ! CheckExecute "lf hid clone new oversize"    "$PM3BIN -c 'lf hid clone --new 0000A4550148AB' 2>&1" "LF HID clone supports only packed credentials up to 37 bits"; then break; fi

      WaitForUserLFTag "PLACE A REWRITABLE T55xx TAG ON THE PM3 NOW"
      if ! RunLFHidCloneFixtures; then break; fi
    fi

    if $TESTLFT55XXROUNDTRIP; then
      T55XX_BACKUP_ACTIVE=false
      echo -e "\n${C_BLUE}Testing first-class T55x7 clone+reader round trips${C_NC} ${PM3BIN:=./pm3}"
      if ! CheckFileExist "pm3 exists" "$PM3BIN"; then break; fi
      WaitForUserLFTag "PLACE A WRITABLE T55x7 TAG ON THE LF ANTENNA NOW"
      if ! BackupT55xxTag; then break; fi

      if ! RunLFT55xxRoundTripFixtures; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi

      if ! RestoreT55xxTag; then CleanupT55xxBackupFiles; break; fi
      CleanupT55xxBackupFiles
      echo "  T55x7 clone+reader round-trip tests completed successfully!"
    fi

    if $TESTLFT55XXDETECT; then
      T55XX_BACKUP_ACTIVE=false
      echo -e "\n${C_BLUE}Testing lf t55xx detect across representative configs${C_NC} ${PM3BIN:=./pm3}"
      if ! CheckFileExist "pm3 exists" "$PM3BIN"; then break; fi
      WaitForUserLFTag "PLACE A WRITABLE T55x7 TAG ON THE LF ANTENNA NOW"
      if ! BackupT55xxTag; then break; fi

      if ! CheckT55xxDetectFixture "EM410x" "$PM3BIN -c 'lf em 410x clone --id 1122334455'" "ASK" "5 - RF/64" "00148040"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi
      if ! CheckT55xxDetectFixture "HID H10301" "$PM3BIN -c 'lf hid clone -w H10301 --fc 31 --cn 337'" "FSK2a" "4 - RF/50" "00107060"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi
      if ! CheckT55xxDetectFixture "Destron" "$PM3BIN -c 'lf destron clone --uid 1A2B3C4D5E'" "FSK2" "4 - RF/50" "00105060"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi
      if ! CheckT55xxDetectFixture "Jablotron" "$PM3BIN -c 'lf jablotron clone --cn 01B669'" "BIPHASE" "5 - RF/64" "00158040"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi
      if ! CheckT55xxDetectFixture "Indala 64" "$PM3BIN -c 'lf indala clone --fc 123 --cn 1337'" "PSK1" "2 - RF/32" "00081040"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi
      if ! CheckT55xxDetectFixture "PAC" "$PM3BIN -c 'lf pac clone --cn CD4F5552'" "DIRECT/NRZ" "2 - RF/32" "00080080"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi
      if ! CheckT55xxDetectConfigFixture "ASK + ST" "--ASK --rate 64 --st" "ASK" "5 - RF/64" "Yes"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi
      if ! CheckT55xxDetectConfigFixture "FSK1" "--FSK1 --rate 50" "FSK1" "4 - RF/50" "No"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi
      if ! CheckT55xxDetectConfigFixture "FSK1A" "--FSK1A --rate 50" "FSK1a" "4 - RF/50" "No"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi
      if ! CheckT55xxDetectConfigFixture "PSK2" "--PSK2 --rate 32" "PSK2" "2 - RF/32" "No"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi
      if ! CheckT55xxDetectConfigFixture "BIA" "--BIA --rate 64" "BIPHASEa - (CDP)" "5 - RF/64" "No"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi

      if ! RestoreT55xxTag; then CleanupT55xxBackupFiles; break; fi
      CleanupT55xxBackupFiles
      echo "  T55xx detect fixture tests completed successfully!"
    fi

    if $TESTLFT55XXDETECTWAKEUP; then
      T55XX_BACKUP_ACTIVE=false
      echo -e "\n${C_BLUE}Testing lf t55xx detect wakeup recovery${C_NC} ${PM3BIN:=./pm3}"
      if ! CheckFileExist "pm3 exists" "$PM3BIN"; then break; fi
      WaitForUserLFTag "PLACE A WRITABLE T55x7 TAG ON THE LF ANTENNA NOW"
      if ! BackupT55xxTag; then break; fi

      if ! CheckT55xxDetectWakeupFixture "00107060" "00107261"; then RestoreT55xxTag; CleanupT55xxBackupFiles; break; fi

      if ! RestoreT55xxTag; then CleanupT55xxBackupFiles; break; fi
      CleanupT55xxBackupFiles
      echo "  T55xx wakeup detect test completed successfully!"
    fi

    if $TESTMFHIDENCODE; then
      echo -e "\n${C_BLUE}Testing MIFARE Classic HID encoding${C_NC} ${PM3BIN:=./pm3}"
      if ! CheckFileExist "pm3 exists"               "$PM3BIN"; then break; fi

      WaitForEnter "PLACE A BLANK MIFARE CLASSIC 1K CARD ON THE PM3 NOW"
      NEED_MF_HID_ENCODE_WIPE=true
      if ! CheckMfHidEncodeRoundTrip "hf mf encodehid bin roundtrip"      "--bin 10001111100000001010100011" "10001111100000001010100011" "H10301.*FC: 31.*CN: 337"; then break; fi
      if ! CheckMfHidEncodeRoundTrip "hf mf encodehid raw roundtrip"      "--raw 063E02A3" "10001111100000001010100011" "H10301.*FC: 31.*CN: 337"; then break; fi
      if ! CheckMfHidEncodeRoundTrip "hf mf encodehid new roundtrip"      "--new 068F80A8C0" "10001111100000001010100011" "H10301.*FC: 31.*CN: 337"; then break; fi
      if ! CheckMfHidEncodeRoundTrip "hf mf encodehid format roundtrip"   "-w H10301 --fc 31 --cn 337" "10001111100000001010100011" "H10301.*FC: 31.*CN: 337"; then break; fi
      if ! RestoreMfHidEncodeCard; then break; fi
      if ! CheckMfHidEncodeCleanup "hf mf encodehid cleanup verify"; then break; fi
    fi
  
  echo -e "\n------------------------------------------------------------"
  echo -e "Tests [ ${C_GREEN}OK${C_NC} ] ${C_OK}\n"
  exit 0
done
echo -e "\n------------------------------------------------------------"
echo -e "\nTests [ ${C_RED}FAIL${C_NC} ] ${C_FAIL}\n"
exit 1
