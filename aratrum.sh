#!/bin/bash
# Aratrum
# Copyright (C) 2021, Jonathan Singer (singerjonathan@protonmail.com)

readonly TMPS=("/mnt/tmp/sm1md02-1")
readonly DSTS=("/mnt/dst/wd14-4/hpool")
readonly LOG="/home/chia/chia-logs"
readonly CHIA="/home/chia/chia-blockchain"
readonly MAX_JOBS=7
readonly STAGGER_M=42
readonly POLLING_S=20
readonly PLOT_SIZE=32
readonly BUFFER_SIZE=4500
readonly N_THREADS=4
readonly N_BUCKETS=128
readonly FARMER_PK="a6b0d77c3e2f1051f0f6165f2629f535abfc30b1d521ac95b8bd7b43c51e9a83be04ff084229435565cc33003c9e7f2e"
readonly POOL_PK="99c7435e2935b641e4e8bbecdd2cf778fd7da0a61b7f54a3eb7c7c343225a0a011f74cd2e0e7f207ddc745c0942dae1d"

readonly TIME_FMT="%H:%M:%S"
readonly STAGGER_S=$(($STAGGER_M * 60))
readonly TMPS_LEN=$(echo "${#TMPS[@]}")
readonly DSTS_LEN=$(echo "${#DSTS[@]}")

find_next_array_element() {
  local -r array=("${!1}")
  local -r last_element=$2
  local array_len
  array_len=$(echo "${#array[@]}")
  local next_element
  local last_element_i
  if [ -n "$last_element" ]; then
    for i in "${!array[@]}"; do                    ##
      if [ "${array[$i]}" == $last_element ]; then  #
        last_element_i=$i                           # Find index of array element
      fi                                            #
    done                                           ##
    if [ -n "$last_element_i" ]; then
      local element_i
      element_i=$(($last_element_i + 1))
      if [ $element_i -lt $array_len ]; then ##
        next_element=${array[$element_i]}     #
      else                                    # Wrap to start if out of bounds
        next_element=${array[0]}              #
      fi                                     ##
    else
      next_element=${array[0]}
    fi
  else
    next_element=${array[0]}
  fi
  printf $next_element
}

find_eligible_dst() {
  for i in "${!DSTS[@]}"; do
    plot_job_paths=$(lsof -Fn -a -c tee +D $LOG | sed -n '/^n/ s/n//p')
    dst_plot_job_count=0
    while IFS= read -r log_path; do
      dst_match=$(grep -o -m 1 "/\*.plot $next_dst" $log_path)
      if [ -n "$dst_match" ]; then
        dst_plot_job_count=$(($dst_plot_job_count + 1))
      fi
    done <<< "$plot_job_paths"
    pending_jobs_size=$(($dst_plot_job_count * 106325607))
    # mv_sizes=$(lsof -Fn -a -c mv +D $next_dst | sed -n '/^s/ s/s//p')
    # mv_total_size=$(( $(echo $mv_sizes | sed 's/ /+/g') ))
    dst_avail=$(df --output=avail $next_dst | tail -n1)
    # dst_avail=$(($dst_avail - $pending_jobs_size + $mv_total_size)) # Account for allocated space of running jobs
    dst_avail=$(($dst_avail - $pending_jobs_size))
    if [ $dst_avail -ge 106325607 ]; then # Size of k32 plot in KiB
      dst=$next_dst
      return 0
    fi
    dst_i=$(($dst_i + 1))
    if [ $dst_i -ge $DSTS_LEN ]; then
      dst_i=0
    fi
    next_dst=${DSTS[$dst_i]}
  done
  echo "($now): No new plot started. No dst with sufficient space available. $n_jobs/$MAX_JOBS jobs running."
  exit 2
}

while [ : ]; do
  now_s=$(date +%s)
  now=$(date +"%Y-%m-%d $TIME_FMT")
  n_jobs=$(ps -C "chia plots create" -o pid h | grep "^.*$" -c)
  last_file=$(ls $LOG | grep ".log" | tail -n1) # Get name of last log file
  if test "${last_file#*.log}" != "$last_file"; then # TRUE if $last_file contains .log, FALSE if none exists
    last_tmp=$(grep -m 1 -oP '(?<=temporary dirs: ).*?(?= and)' $LOG/$last_file) # Find tmp used by last job from log file
    tmp=$(find_next_array_element TMPS[@] "$last_tmp")
    last_dst=$(grep -m 1 -oP '(?<=/\*.plot ).*' $LOG/$last_file) # Find dst used by last job from log file
    next_dst=$(find_next_array_element DSTS[@] "$last_dst")
    find_eligible_dst
    last_time=$(echo $last_file | sed -e 's/T/ /g' -e 's/_/:/g' -e 's/\..*//g') # Get timestamp readable by "date -d" from log file name
    last_s=$(date -d "$last_time" +%s)
    diff=$(($now_s - $last_s))
  else # No log files found
    tmp=${TMPS[0]}
    next_dst=${DSTS[0]}
    find_eligible_dst
    diff=$STAGGER_S
  fi
  if [ $diff -ge $STAGGER_S ]; then
    if [ $n_jobs -lt $MAX_JOBS ]; then
      now_file=$(date +"%Y-%m-%dT%H_%M_%S")
      plot_command="chia plots create -k $PLOT_SIZE -b $BUFFER_SIZE -r $N_THREADS -u $N_BUCKETS -t $tmp -d $tmp -f $FARMER_PK -p $POOL_PK"
      move_command="mv -v $tmp/*.plot $dst"
      command="cd $CHIA && . ./activate && printf \"Plot command: $plot_command\nMove command: $move_command\n\" |tee $LOG/$now_file.log && $plot_command |tee -a $LOG/$now_file.log && $move_command |tee -a $LOG/$now_file.log"
      screen -dmS plot bash -c "$command"
      next_s=$(($now_s + $STAGGER_S))
      next=$(date -d "@$next_s" +"$TIME_FMT")
      n_jobs=$(($n_jobs + 1))
      echo "($now): Started a plot with tmp = $tmp and dst = $dst. $n_jobs/$MAX_JOBS jobs running. Next job will try to start at $next."
      sleep $STAGGER_S
    else
      echo "($now): Max ($MAX_JOBS) jobs running. Trying again in ${POLLING_S}s..."
      sleep $POLLING_S
    fi
  else
    last=$(date -d "$last_time" +"$TIME_FMT")
    next_s=$(($last_s + $STAGGER_S))
    next=$(date -d "@$next_s" +"$TIME_FMT")
    remaining_s=$(($STAGGER_S - $diff))
    remaining_m=$(($remaining_s / 60))
    echo "($now): Last job started at $last. $n_jobs/$MAX_JOBS jobs running. Next job will try to start at $next. Waiting ${remaining_s}s (~${remaining_m}m)... (${diff}s/${STAGGER_S}s)"
    sleep $remaining_s
  fi
done

# TODO: Move specific plot instead of *.plot
# TODO: Plot size KiB variable
# TODO: Rewrite in Rust?
