#!/bin/bash

## setting stuff up
# pretty pointless, might remove later
fix() {
	cut -b -$1 --complement | xargs -rd'\n' printf 'P /%s\n'
}

remote=$1
ropts=$2

tmp=${TMPDIR:-/tmp}
filter=$tmp/bsync-filter-$$
control=$tmp/bsync-control-$$
cfg_l=${XDG_CONFIG_HOME:-~/.config}/bsync
if ! name_l=$(cat "$cfg_l/name")
then
	read -p "Unique name for this machine: " name_l
	echo "$name_l" > "$cfg_l/name"
fi

# ssh can't parse single quotes anyways, so the following is fine
sshm() {
	ssh "$remote" -o "controlpath='$control'" $@
}
sshm -MNf

trap "sshm -O exit; rm '$filter';" EXIT TERM
trap "exit 1" INT

# looks weird, but imo cleanest way go doing it & it can be easily changed 
# for other shells
# also you will need to have your XDG_CONFIG_HOME set before the interactivity
# check in your bashrc
cfg_r=$(sshm 'bash -lc "echo \$XDG_CONFIG_HOME"')
if ! name_r=$(sshm "cat '$cfg_r/name'")
then
	read -p "Unique name for the remote machine: " name_r
	sshm "echo '$name_r' > '$cfg_r/name'"
fi

last_l=$cfg_l/last-$name_r
[ -e "$last_l" ] || touch "$last_l"
last_r=$cfg_r/last-$name_l
sshm "[ -e '$last_r' ] || touch '$last_r' ]"

## main loop
cd
while read line <&3
do
	# check for whitespace, comments, early ends, etc.
	[[ $line =~ ^# ]] || [[ $line =~ ^[:space:]*$ ]] && continue
	[[ $line =~ ^\[END\] ]] && break

	## if it finds a "host-header", check if the header contains the hosts we are
	## syncing
	if [[ $line =~ ^\[hosts\] ]] 
	then
		unset arg_l arg_r
		eval "hosts=($line)"
		for i in ${!hosts[@]}
		do
			[ "${hosts[$i]}" == "$name_l" ] && arg_l=$i
			[ "${hosts[$i]}" == "$name_r" ] && arg_r=$i
		done
	## if the last host-header contained both of the hosts we are syncing, then
	## start the actual syncing
	elif [ -v arg_r ] && [ -v arg_l ]
	then
		# if the paths have alternate aliases, use those
		eval "args=($line)"
		alias_l=${args[0]}
		[ "${args[$arg_l]}" == % ] || alias_l=${args[$arg_l]}
		alias_r=${args[0]}
		[ "${args[$arg_r]}" == % ] || alias_r=${args[$arg_r]}
		if [ -d "${alias_l}" ]
		then
			alias_l=${alias_l/%\/}/
			alias_r=${alias_r/%\/}/
		fi

		# sync the files from the remote to the local
		tput bold; tput setaf 4; echo "Syncing '$remote:$alias_r' to '$alias_l'"
		tput sgr0
		find "$alias_l" -newer "$last_l" | fix ${#alias_l} > "$filter"
		rsync "$remote:$alias_r" "$alias_l" --mkpath -uaPz -f ". $filter" $ropts
		# sync the files from the local to the remote
		tput bold; tput setaf 3; echo "Syncing '$alias_l' to '$remote:$alias_r'"
		tput sgr0
		# not exactly sure if this works w/automatic auth
		sshm "find '$alias_r' -newer '$last_r' | cut -b -${#alias_r} --complement | 
			xargs -rd'\n' printf 'P /%s\n'" > "$filter" 
		rsync "$alias_l" "$remote:$alias_r" --mkpath -uaPz -f ". $filter" $ropts
	fi
done 3< "$cfg_l/config"

if [ -v $3 ]
then
	tput bold; tput setaf 2; echo Touching lastfiles...; tput sgr0
	touch "$last_l"
	sshm "touch '$last_r'"
fi
