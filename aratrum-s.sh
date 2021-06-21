#!/bin/bash
# Aratrum Status
# Copyright (C) 2021, Jonathan Singer (singerjonathan@protonmail.com)

readonly LOG="/home/chia/chia-logs"
readonly MAX_JOBS=7

readonly RECENT=$(($MAX_JOBS * 2))

seconds_to_hms() {
  ((h=${1}/3600))
  ((m=(${1}%3600)/60))
  ((s=${1}%60))
  printf "%02d:%02d:%02d\n" $h $m $s
}

log_name_to_readable_timestamp() {
  echo $1 | sed -e 's/T/ /g' -e 's/_/:/g' -e 's/\..*//g'
}

recent_logs=$(ls $LOG | tail -n $RECENT)
plot_job_paths=$(lsof -Fn -a -c tee +D $LOG | sed -n '/^n/ s/n//p' | sort | tac)
now_s=$(date +%s)
output="ID\t\tTIME\t\tPHASE\tTMP\t\t\tDST\t\t\tINTERVAL\n"
while IFS= read -r log_path; do
  id=$(grep "ID: " $log_path)
  id_short="${id: 4:4}...${id: -4:4}"
  log_file_name=$(basename $log_path)
  start_time=$(log_name_to_readable_timestamp $log_file_name)
  start_s=$(date -d "$start_time" +%s)
  run_s=$(($now_s - $start_s))
  run_time=$(seconds_to_hms $run_s)
  tmp=$(grep -m 1 -oP '(?<=temporary dirs: ).*?(?= and)' $log_path)
  dst=$(grep -m 1 -oP '(?<=/\*.plot ).*' $log_path)
  last_log=$(echo "$recent_logs" | grep -m 1 -B 1 "$log_file_name" | head -n1)
  last_start_time=$(log_name_to_readable_timestamp $last_log)
  last_start_s=$(date -d "$last_start_time" +%s)
  interval_s=$(($start_s - $last_start_s))
  interval_time=$(seconds_to_hms $interval_s)
  # last_finish_time=$(tac $LOG/$last_log | grep -m 1 "Total time" | grep -m 1 -oP '(?<=\)\s).*$')
  phase_match=$(tac $log_path | grep -o -m 1 "Renamed\|Starting phase 4\|Compressing tables 6\|Compressing tables 5\|Compressing tables 4\|Compressing tables 3\|Compressing tables 2\|Compressing tables 1\|Backpropagating on table 2\|Backpropagating on table 3\|Backpropagating on table 4\|Backpropagating on table 5\|Backpropagating on table 6\|Backpropagating on table 7\|Computing table 7\|Computing table 6\|Computing table 5\|Computing table 4\|Computing table 3\|Computing table 2\|Computing table 1" | tr -d '\n')
  if [[ $phase_match == "Renamed" ]]; then
    phase="5:0"
  elif [[ $phase_match == "Starting phase 4" ]]; then
    phase="4:0"
  elif [[ $phase_match == "Compressing tables 6" ]]; then
    phase="3:6"
  elif [[ $phase_match == "Compressing tables 5" ]]; then
    phase="3:5"
  elif [[ $phase_match == "Compressing tables 4" ]]; then
    phase="3:4"
  elif [[ $phase_match == "Compressing tables 3" ]]; then
    phase="3:3"
  elif [[ $phase_match == "Compressing tables 2" ]]; then
    phase="3:2"
  elif [[ $phase_match == "Compressing tables 1" ]]; then
    phase="3:1"
  elif [[ $phase_match == "Backpropagating on table 2" ]]; then
    phase="2:6"
  elif [[ $phase_match == "Backpropagating on table 3" ]]; then
    phase="2:5"
  elif [[ $phase_match == "Backpropagating on table 4" ]]; then
    phase="2:4"
  elif [[ $phase_match == "Backpropagating on table 5" ]]; then
    phase="2:3"
  elif [[ $phase_match == "Backpropagating on table 6" ]]; then
    phase="2:2"
  elif [[ $phase_match == "Backpropagating on table 7" ]]; then
    phase="2:1"
  elif [[ $phase_match == "Computing table 7" ]]; then
    phase="1:7"
  elif [[ $phase_match == "Computing table 6" ]]; then
    phase="1:6"
  elif [[ $phase_match == "Computing table 5" ]]; then
    phase="1:5"
  elif [[ $phase_match == "Computing table 4" ]]; then
    phase="1:4"
  elif [[ $phase_match == "Computing table 3" ]]; then
    phase="1:3"
  elif [[ $phase_match == "Computing table 2" ]]; then
    phase="1:2"
  elif [[ $phase_match == "Computing table 1" ]]; then
    phase="1:1"
  else
    phase="0:0"
  fi
  output="${output}$id_short\t$run_time\t$phase\t$tmp\t$dst\t$interval_time\n"
done <<< "$plot_job_paths"
printf $output

# TODO: Show downtime
# TODO: Show start time
# TODO: Better output format
