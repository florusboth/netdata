# shellcheck shell=bash
# no need for shebang - this file is loaded from charts.d.plugin
# SPDX-License-Identifier: GPL-3.0-or-later

# netdata
# real-time performance and health monitoring, done right!
# (C) 2016 Costa Tsaousis <costa@tsaousis.gr>
#

apcupsd_ip=
apcupsd_port=

declare -A apcupsd_sources=(
  ["local"]="127.0.0.1:3551"
)

# how frequently to collect UPS data
apcupsd_update_every=10

apcupsd_timeout=3

# the priority of apcupsd related to other charts
apcupsd_priority=90000

apcupsd_get() {
  run -t $apcupsd_timeout apcaccess status "$1"
}

is_ups_alive() {
  local status
  status="$(apcupsd_get "$1" | sed -e 's/STATUS.*: //' -e 't' -e 'd')"
  case "$status" in
    "" | "COMMLOST" | "SHUTTING DOWN") return 1 ;;
    *) return 0 ;;
  esac
}

apcupsd_check() {

  # this should return:
  #  - 0 to enable the chart
  #  - 1 to disable the chart

  require_cmd apcaccess || return 1

  # backwards compatibility
  if [ "${apcupsd_ip}:${apcupsd_port}" != ":" ]; then
    apcupsd_sources["local"]="${apcupsd_ip}:${apcupsd_port}"
  fi

  local host working=0 failed=0
  for host in "${!apcupsd_sources[@]}"; do
    apcupsd_get "${apcupsd_sources[${host}]}" >/dev/null
    # shellcheck disable=2181
    if [ $? -ne 0 ]; then
      error "cannot get information for apcupsd server ${host} on ${apcupsd_sources[${host}]}."
      failed=$((failed + 1))
    else
      if ! is_ups_alive ${apcupsd_sources[${host}]}; then
        error "APC UPS ${host} on ${apcupsd_sources[${host}]} is not online."
        failed=$((failed + 1))
      else
        working=$((working + 1))
      fi
    fi
  done

  if [ ${working} -eq 0 ]; then
    error "No APC UPSes found available."
    return 1
  fi

  return 0
}

apcupsd_create() {
  local host
  for host in "${!apcupsd_sources[@]}"; do
    # create the charts
    cat <<EOF
CHART apcupsd_${host}.charge '' "UPS Charge" "percentage" ups apcupsd.charge area $((apcupsd_priority + 2)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION battery_charge charge absolute 1 100

CHART apcupsd_${host}.battery_voltage '' "UPS Battery Voltage" "Volts" ups apcupsd.battery.voltage line $((apcupsd_priority + 4)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION battery_voltage voltage absolute 1 100
DIMENSION battery_voltage_nominal nominal absolute 1 100

CHART apcupsd_${host}.input_voltage '' "UPS Input Voltage" "Volts" input apcupsd.input.voltage line $((apcupsd_priority + 5)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION input_voltage voltage absolute 1 100
DIMENSION input_voltage_min min absolute 1 100
DIMENSION input_voltage_max max absolute 1 100

CHART apcupsd_${host}.input_frequency '' "UPS Input Frequency" "Hz" input apcupsd.input.frequency line $((apcupsd_priority + 6)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION input_frequency frequency absolute 1 100

CHART apcupsd_${host}.output_voltage '' "UPS Output Voltage" "Volts" output apcupsd.output.voltage line $((apcupsd_priority + 7)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION output_voltage voltage absolute 1 100
DIMENSION output_voltage_nominal nominal absolute 1 100

CHART apcupsd_${host}.load '' "UPS Load" "percentage" ups apcupsd.load area $((apcupsd_priority)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION load load absolute 1 100

CHART apcupsd_${host}.load_usage '' "UPS Load Usage" "Watts" ups apcupsd.load_usage area $((apcupsd_priority + 1)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION load_usage load absolute 1 100

CHART apcupsd_${host}.temp '' "UPS Temperature" "Celsius" ups apcupsd.temperature line $((apcupsd_priority + 8)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION temp temp absolute 1 100

CHART apcupsd_${host}.time '' "UPS Time Remaining" "Minutes" ups apcupsd.time area $((apcupsd_priority + 3)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION time time absolute 1 100

CHART apcupsd_${host}.online '' "UPS ONLINE flag" "boolean" ups apcupsd.online line $((apcupsd_priority + 9)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION online online absolute 1 1

CHART apcupsd_${host}.selftest '' "UPS Self-Test status" "status" ups apcupsd.selftest line $((apcupsd_priority + 10)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION selftest_OK 'OK' absolute 1 1
DIMENSION selftest_NO 'NO' absolute 1 1
DIMENSION selftest_BT 'BT' absolute 1 1
DIMENSION selftest_NG 'NG' absolute 1 1

CHART apcupsd_${host}.status '' "UPS Status" "status" ups apcupsd.status line $((apcupsd_priority + 11)) $apcupsd_update_every '' '' 'apcupsd'
DIMENSION status_ONLINE 'ONLINE' absolute 1 1
DIMENSION status_ONBATT 'ONBATT' absolute 1 1
DIMENSION status_OVERLOAD 'OVERLOAD' absolute 1 1
DIMENSION status_LOWBATT 'LOWBATT' absolute 1 1
DIMENSION status_REPLACEBATT 'REPLACEBATT' absolute 1 1
DIMENSION status_NOBATT 'NOBATT' absolute 1 1
DIMENSION status_SLAVE 'SLAVE' absolute 1 1
DIMENSION status_SLAVEDOWN 'SLAVEDOWN' absolute 1 1
DIMENSION status_COMMLOST 'COMMLOST' absolute 1 1
DIMENSION status_CAL 'CAL' absolute 1 1
DIMENSION status_TRIM 'TRIM' absolute 1 1
DIMENSION status_BOOST 'BOOST' absolute 1 1
DIMENSION status_SHUTTING_DOWN 'SHUTTING_DOWN' absolute 1 1

EOF
  done
  return 0
}

apcupsd_update() {
  # the first argument to this function is the microseconds since last update
  # pass this parameter to the BEGIN statement (see below).

  # do all the work to collect / calculate the values
  # for each dimension
  # remember: KEEP IT SIMPLE AND SHORT

  local host working=0 failed=0
  for host in "${!apcupsd_sources[@]}"; do
    apcupsd_get "${apcupsd_sources[${host}]}" | awk "

BEGIN {
  battery_charge = 0;
  battery_voltage = 0;
  battery_voltage_nominal = 0;
  input_voltage = 0;
  input_voltage_min = 0;
  input_voltage_max = 0;
  input_frequency = 0;
  output_voltage = 0;
  output_voltage_nominal = 0;
  load = 0;
  temp = 0;
  time = 0;
  online = 0;
  nompower = 0;
  load_usage = 0;
  selftest_OK = 0;
  selftest_NO = 0;
  selftest_BT = 0;
  selftest_NG = 0;
  status_ONLINE = 0;
  status_CAL = 0;
  status_TRIM = 0;
  status_BOOST = 0;
  status_ONBATT = 0;
  status_OVERLOAD = 0;
  status_LOWBATT = 0;
  status_REPLACEBATT = 0;
  status_NOBATT = 0;
  status_SLAVE = 0;
  status_SLAVEDOWN = 0;
  status_COMMLOST = 0;
  status_SHUTTING_DOWN = 0;

}
/^BCHARGE.*/   { battery_charge = \$3 * 100 };
/^BATTV.*/     { battery_voltage = \$3 * 100 };
/^NOMBATTV.*/  { battery_voltage_nominal = \$3 * 100 };
/^LINEV.*/     { input_voltage = \$3 * 100 };
/^MINLINEV.*/  { input_voltage_min = \$3 * 100 };
/^MAXLINEV.*/  { input_voltage_max = \$3 * 100 };
/^LINEFREQ.*/  { input_frequency = \$3 * 100 };
/^OUTPUTV.*/   { output_voltage = \$3 * 100 };
/^NOMOUTV.*/   { output_voltage_nominal = \$3 * 100 };
/^LOADPCT.*/   { load = \$3 * 100 };
/^ITEMP.*/     { temp = \$3 * 100 };
/^NOMPOWER.*/  { nompower = \$3 };
/^TIMELEFT.*/  { time = \$3 * 100 };
/^STATUS.*/    { online=(\$0 !~ \"COMMLOST\" && \$0 !~ \"SHUTTING\") ? 1 : 0; };
/^SELFTEST.*/  { selftest_OK = (\$3 == \"OK\") ? 1 : 0;
                 selftest_NO = (\$3 == \"NO\") ? 1 : 0;
                 selftest_BT = (\$3 == \"BT\") ? 1 : 0;
                 selftest_NG = (\$3 == \"NG\") ? 1 : 0;
               };
/^STATUS.*/    { status_ONLINE = (\$0 ~ \"ONLINE\") ? 1 : 0;
                 status_CAL = (\$0 ~ \"CAL\") ? 1 : 0;
                 status_TRIM = (\$0 ~ \"TRIM\") ? 1 : 0;
                 status_BOOST = (\$0 ~ \"BOOST\") ? 1 : 0;
                 status_ONBATT = (\$0 ~ \"ONBATT\") ? 1 : 0;
                 status_OVERLOAD = (\$0 ~ \"OVERLOAD\") ? 1 : 0;
                 status_LOWBATT = (\$0 ~ \"LOWBATT\") ? 1 : 0;
                 status_REPLACEBATT = (\$0 ~ \"REPLACEBATT\") ? 1 : 0;
                 status_NOBATT = (\$0 ~ \"NOBATT\") ? 1 : 0;
                 status_SLAVE = (\$0 ~ \"SLAVE( |$)\") ? 1 : 0;
                 status_SLAVEDOWN = (\$0 ~ \"SLAVEDOWN\") ? 1 : 0;
                 status_COMMLOST = (\$0 ~ \"COMMLOST\") ? 1 : 0;
                 status_SHUTTING_DOWN = (\$0 ~ \"SHUTTING\") ? 1 : 0;
               };

END {
  { load_usage = nompower * load / 100 };

  print \"BEGIN apcupsd_${host}.online $1\";
  print \"SET online = \" online;
  print \"END\"

  if (online == 1) {
    print \"BEGIN apcupsd_${host}.charge $1\";
    print \"SET battery_charge = \" battery_charge;
    print \"END\"

    print \"BEGIN apcupsd_${host}.battery_voltage $1\";
    print \"SET battery_voltage = \" battery_voltage;
    print \"SET battery_voltage_nominal = \" battery_voltage_nominal;
    print \"END\"

    print \"BEGIN apcupsd_${host}.input_voltage $1\";
    print \"SET input_voltage = \" input_voltage;
    print \"SET input_voltage_min = \" input_voltage_min;
    print \"SET input_voltage_max = \" input_voltage_max;
    print \"END\"

    print \"BEGIN apcupsd_${host}.input_frequency $1\";
    print \"SET input_frequency = \" input_frequency;
    print \"END\"

    print \"BEGIN apcupsd_${host}.output_voltage $1\";
    print \"SET output_voltage = \" output_voltage;
    print \"SET output_voltage_nominal = \" output_voltage_nominal;
    print \"END\"

    print \"BEGIN apcupsd_${host}.load $1\";
    print \"SET load = \" load;
    print \"END\"

    print \"BEGIN apcupsd_${host}.load_usage $1\";
    print \"SET load_usage = \" load_usage;
    print \"END\"

    print \"BEGIN apcupsd_${host}.temp $1\";
    print \"SET temp = \" temp;
    print \"END\"

    print \"BEGIN apcupsd_${host}.time $1\";
    print \"SET time = \" time;
    print \"END\"

    print \"BEGIN apcupsd_${host}.selftest $1\";
    print \"SET selftest_OK = \" selftest_OK;
    print \"SET selftest_NO = \" selftest_NO;
    print \"SET selftest_BT = \" selftest_BT;
    print \"SET selftest_NG = \" selftest_NG;
    print \"END\"

    print \"BEGIN apcupsd_${host}.status $1\";
    print \"SET status_ONLINE = \" status_ONLINE;
    print \"SET status_ONBATT = \" status_ONBATT;
    print \"SET status_OVERLOAD = \" status_OVERLOAD;
    print \"SET status_LOWBATT = \" status_LOWBATT;
    print \"SET status_REPLACEBATT = \" status_REPLACEBATT;
    print \"SET status_NOBATT = \" status_NOBATT;
    print \"SET status_SLAVE = \" status_SLAVE;
    print \"SET status_SLAVEDOWN = \" status_SLAVEDOWN;
    print \"SET status_COMMLOST = \" status_COMMLOST;
    print \"SET status_CAL = \" status_CAL;
    print \"SET status_TRIM = \" status_TRIM;
    print \"SET status_BOOST = \" status_BOOST;
    print \"SET status_SHUTTING_DOWN = \" status_SHUTTING_DOWN;
    print \"END\";
  }
}"
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
      failed=$((failed + 1))
      error "failed to get values for APC UPS ${host} on ${apcupsd_sources[${host}]}" && return 1
    else
      working=$((working + 1))
    fi
  done

  [ $working -eq 0 ] && error "failed to get values from all APC UPSes" && return 1

  return 0
}
