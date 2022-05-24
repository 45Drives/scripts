#!/usr/bin/env bash

# read from file if provided, else from stdin
if [[ -f $1 ]]; then
	exec 0<"$1"
fi

print_red() {
	printf "\e[31;1m$1\e[0m"
}

print_yellow() {
	printf "\e[33;1m$1\e[0m"
}

print_orange() {
	printf "\e[33m$1\e[0m"
}

print_purple() {
	printf "\e[35;1m$1\e[0m"
}

colour_errors() {
	perl -pne "s/(err(?:or)?:)/$(print_red '\\1')/gi;s/(warn(?:ing)?:)/$(print_orange '\\1')/gi;s/(^|\\033\[0m)(.+?)(?=\\033|$)/\1$(print_yellow '\\2')/gi"
}

exec 2> >(colour_errors)

run_and_prefix_stderr() {
	$@ 2> >(perl -pne "s/^(?!\s*$)/$(print_red $1:) /" >&2)
}

generate_lookup_paths() {
	echo $PATH | perl -pne "s/(?=:|$)/\/$1\1/g;s/:/\n/g"
}

report_missing_from_system() {
	local result
	local unformatted
	echo Error: $1 is not installed on system! >&2
	echo 'Possible install candidate(s):' >&2
	if [[ "$OS" == "rhel" ]]; then
		run_and_prefix_stderr dnf provides $(generate_lookup_paths $1) |
			perl -ne 'print $_ =~ s/^(.+?)-[\d.]+-\d+\.el.*\n/\1: /r if $_ =~ /-[\d.]+-\d+\.el.*/; print $_ =~ s/^Filename\s*:\s*(.*)\n/\1\n/r if $_ =~ /^Filename/' |
			perl -pne "s/(^[^:]+|$1)/$(print_purple '\\1')/g" |
			sort -u >&2
	else # debian
		unformatted=$(printf "^%s$\n" $(generate_lookup_paths $1) | apt-file search -x -f - 2>/dev/null)
		result=$?
		[[ -n $unformatted ]] && echo $unformatted | perl -pne "s/(^[^:]+|$1)/$(print_purple '\\1')/g" >&2
		[[ $result != '0' ]] && echo Error: No Matches found >&2
	fi
	return 0
}

OS=$(awk -F= '/^ID_LIKE/{print $2}' /etc/os-release | perl -pne 's/.*(rhel|debian).*/\1/')
[[ "$OS" != "rhel" && "$OS" != "debian" ]] && echo Error: unsupported OS >&2 && exit 1

EXE_PATHS=()

FAIL_FLAG=0

# iterate through each program name
while read -r line; do
	[[ -z "$line" ]] && continue
	# get resolved path(s) (/bin and /usr/bin)
	path=( $(which -a $line) )
	result=$?
	[[ $result != 0 ]] && report_missing_from_system $line >&2 && FAIL_FLAG=$result && continue
	# append path(s) to array
	EXE_PATHS+=( "${path[@]}" )
done

[[ "${#EXE_PATHS[@]}" == "0" ]] && echo Error: no executables to query! >&2 && exit 1

# search for packages providing said programs, removing duplicates
if [[ "$OS" == "rhel" ]]; then
	PACKAGES=$(run_and_prefix_stderr rpm -qf "${EXE_PATHS[@]}" --queryformat='%{NAME}\n' | sort -u)
else
	PACKAGES=$(run_and_prefix_stderr dpkg-query -S --no-pager "${EXE_PATHS[@]}" 2> >(sed '/no path found matching pattern/d' >&2) | cut -d: -f1 | sort -u)
fi

[[ $FAIL_FLAG != 0 ]] && echo 'Error: some dependencies were not installed on this system. Some packages may be missing.' >&2

printf "%s\n" "${PACKAGES[@]}"
echo Packages found: >&2
printf "%s\n" "${PACKAGES[@]}" >&2

exit $FAIL_FLAG
