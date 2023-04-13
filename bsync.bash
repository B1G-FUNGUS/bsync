#!/bin/bash
# to make sure all relative paths are relative to home
cd

# read and slash pathnames 
c=0
while read line
do
	[[ $line =~ ^# ]] || [[ $line =~ ^[:space]*$ ]] && continue
	[[ $line =~ ^\[END\] ]] && break

	if [[ $line =~ ^\[hosts\] ]]
	then
		unset arg_r
		unset arg_l
		# hostnames can't include special chars, but aliases can
		eval "hosts=($line)" 
		for i in ${!hosts[@]}
		do
			[ "${hosts[$i]}" == "$HOSTNAME" ] && arg_l=$i
			[ "${hosts[$i]}" == "$1" ] && arg_r=$i
		done
	elif [ -v arg_r ] && [ -v arg_l ]
	then
		eval "args=($line)"
		index[$c]=${args[0]}
		alias_l[$c]=${index[$c]}
		[ "${args[$arg_l]}" == % ] || alias_l[$c]=${args[$arg_l]}
		alias_r[$c]=${index[$c]}
		[ "${args[$arg_r]}" == % ] || alias_r[$c]=${args[$arg_r]}

		if [ -d "${alias_l[$c]}" ] 
		then
			index[$c]=${index[$c]/%\/}/
			alias_l[$c]=${alias_l[$c]/%\/}/
			alias_r[$c]=${alias_r[$c]/%\/}/
		fi
		((c++))
	fi
done < "${BSYNC_CFG:=${XDG_CONFIG_HOME:-~/.config}/bsync}/config"

# for each index, get full list (local), dealias
# for each index, get old list (local), dealias
for i in ${!index[@]}
do
	now_l[$i]=$'\n'$(find "${alias_l[$i]}")
	old_l[$i]=$'\n'$(find "${alias_l[$i]}" ! -newer "$BSYNC_CFG/last-$1")
	if [ "${alias_l[$i]}" != "${index[$i]}" ]
	then
		now_l[$i]=${now_l[$i]//$'\n'"${alias_l[$i]}"/$'\n'"${index[$i]}"}
		old_l[$i]=${old_l[$i]//$'\n'"${alias_l[$i]}"/$'\n'"${index[$i]}"}
	fi
done

# for each index, get full list (remote), dealias
# for each index, get full list (remote) @A, dealias
statement=$(ssh "$1" \
	'lastfile=${BSYNC_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/bsync}/last-'$HOSTNAME'
	index=('${index[@]@Q}')
	alias_r=('${alias_r[@]@Q}')

	for i in ${!index[@]}
	do
		now_r[$i]="'$'\n''"$(find "${alias_r[$i]}")
		old_r[$i]="'$'\n''"$(find "${alias_r[$i]}" ! -newer "$lastfile")
		if [ "${alias_l[$i]}" != "${index[$i]}" ]
		then
			now_r[$i]=${now_r[$i]//"'$'\n''""${alias_r[$i]}"/"'$'\n''""${index[$i]}"}
			old_r[$i]=${old_r[$i]//"'$'\n''""${alias_r[$i]}"/"'$'\n''""${index[$i]}"}
		fi
	done

	echo ${now_r[@]@A}
	echo ${old_r[@]@A}')
eval "$statement"

confirm() {
	read -p 'Continue?[y/N]' confirm
	[[ "$confirm" =~ ^y[e]*[s]*$ ]] || exit 0
}

# for each index
	# get diff between remote_full and local_full
	# separate into remote_unique and local_unique
	# comm between local_unique and local_old
	# prompt for delete
	# comm between remote_unique and remote_old
	# prompt for delete
	# sync aliases biderectionally
for i in ${!index[@]}
do
	diff=$(diff <(echo "${now_l[$i]}" | sort) <(echo "${now_r[$i]}" | sort))
	uniq_l=$(echo "$diff" | sed -n 's/^< //p')
	uniq_r=$(echo "$diff" | sed -n 's/^> //p')

	del_l=$(comm -12 <(echo "$uniq_l" | sort) <(echo "${old_l[$i]}" | sort))
	if [ -n "$del_l" ]
	then
		echo The following files will be deleted locally:$'\n'"$del_l"
		confirm
		del_l=${del_l//$'\n'"${index[$i]}"/$'\n'"${alias_l[$i]}"}
		echo "$del_l" | tac | xargs -d'\n' rm -dv
	fi

	del_r=$(comm -12 <(echo "$uniq_r" | sort) <(echo "${old_r[$i]}" | sort))
	if [ -n "$del_r" ]
	then
		echo The following files will be deleted remotely:$'\n'"$del_r"
		confirm
		del_r=${del_r//$'\n'"${index[$i]}"/$'\n'"${alias_r[$i]}"}
		echo "$del_r" | tac | ssh "$1" "xargs -d'\n' rm -dv"
	fi
	
	rsync --mkpath -uaPz "${alias_l[$i]}" "$1:${alias_r[$i]}"
	rsync --mkpath -uaPz "$1:${alias_r[$i]}" "${alias_l[$i]}" 
done
date=$(date)
touch "$BSYNC_CFG/last-$1" -d "$date"
ssh "$1" 'touch "${BSYNC_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/bsync}/last-'$HOSTNAME'" -d "'$date'"'
