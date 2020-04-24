#!/usr/bin/env bash
# TODO:
# • Add support for networks, not just hosts.
printUsage() {
	echo "Usage:"
	echo "$0 [-d] [-h] [-f file] [-I] \"<project>\""
	echo "Default output is pretty-print JSON to STDOUT, suitable for output redirection."
	echo -e "\t-d\tIncrease debug level, up to twice."
	echo -e "\t-h\tPrint this usage information."
	echo -e "\t-f file\tAccept input from <file>."
	echo -e "\t-I\tAccept input from STDIN."
	echo -e "\tproject\tQuote-delimited project name, used in any new object names."
	echo ""
	echo "Example:"
	echo "$0 -f newObjects.txt \"My New Objects\""
	echo ""
	echo "Note: Input should be one object per line. For example:"
	echo "10.20.30.40"
	echo "10.20.30.40-10.20.30.50"
	echo "10.20.30.0/24"
	echo "192.168.30.40,10.20.30.40"
	echo "TCP 8080"
	echo "IP 12"
	echo "TCP 80,TCP 443"
	}

debug1() {
	if [ "${debugLevel}" -ge 1 ]; then
		printf "DEBUG1: %s\n" "$*" >&2
		fi
	}

debug2() {
	if [ "${debugLevel}" -ge 2 ]; then
		printf "DEBUG2: %s\n" "$*" >&2
		fi
	}



if [ $# -eq 0 ]; then
	printUsage
	exit 1
	fi

declare -i debugLevel=0
inputFile=""
readFromSTDIN=false

rawObjectList=()
dedupedObjectList=()

serviceGroupList=()
rawServiceList=()
fqdnList=()
networkGroupList=()
addressRangeList=()
networkList=()
hostList=()

tcpServiceList=()
udpServiceList=()
ipServiceList=()

while getopts ":dhf:I" options; do
	case "$options" in
	d) # Increase debug level.
		debugLevel+=1
		;;
	h) # Print usage information.
		printUsage
		exit 0
		;;
	f) # Accept input from <file>.
		inputFile="${OPTARG}"
		;;
	I) # Accept input from STDIN.
		readFromSTDIN=true
		;;
	\?) # Handle invalid options.
		echo "ERROR: Invalid option: -$OPTARG" >&2
		echo ""
		printUsage
		exit 1
		;;
	:)
		echo "ERROR: Option -$OPTARG requires an argument." >&2
		echo ""
		printUsage
		exit 1
		;;
	esac
	done
shift "$((OPTIND-1))" # Remove all the options getopts has handled.
debug1 "Debug level set to ${debugLevel}."

projectName="$1"
if [ "${projectName}" == "" ]; then
	echo "ERROR: No project name provided." >&2
	printUsage
	exit 1
	fi
debug1 "Project name we are using for new object names: ${projectName}"

if [ $readFromSTDIN ]; then
	debug1 "Reading from STDIN."
	while read LINE; do
		debug2 "New item: ${LINE}"
		rawObjectList+=("$LINE")
		done
	fi

if [ "${inputFile}" != "" ]; then
	debug1 "Reading from file: ${inputFile}"
	while read LINE; do
		debug2 "New item: ${LINE}"
		rawObjectList+=("$LINE")
		done < "${inputFile}"
	fi

IFS=$'\n' dedupedObjectList=($(sort <<< "${rawObjectList[*]}" | uniq)); unset IFS
unset rawObjectList
debug2 "Deduplicated object list: ${dedupedObjectList[*]}"

for item in "${dedupedObjectList[@]}"; do
	if $(echo "${item}" | egrep ",[a-zA-Z]" > /dev/null); then
		serviceGroupList+=("$item")
	elif $(echo "${item}" | egrep "^[a-zA-Z]" > /dev/null); then
		echo "$item looks like a service."
		rawServiceList+=("$item")
	elif $(echo "${item}" | grep "," > /dev/null); then
		networkGroupList+=("$item")
	elif $(echo "${item}" | egrep "^\." > /dev/null); then
		fqdnList+=("$item")
	elif $(echo "${item}" | grep "-" > /dev/null); then
		addressRangeList+=("$item")
	elif $(echo "${item}" | grep "/" > /dev/null); then
		networkList+=("$item")
	else
		hostList+=("$item")
		fi
	done

for item in "${rawServiceList[@]}"; do
	if $(echo "${item}" | egrep "^TCP" >/dev/null); then
		tcpServiceList+=("$item")
	elif $(echo "${item}" | egrep "^UDP" >/dev/null); then
		udpServiceList+=("$item")
	elif $(echo "${item}" | egrep "^IP" >/dev/null); then
		ipServiceList+=("$item")
	else
		echo "ERROR: Unhandled service: $item" >&2
		fi
	done
unset rawServiceList


# We now have a set of lists per object type we will create. Having the
# lists separated will let us build the group members before the
# groups. Next, we will connect to the managements and iterate through
# the objects. For each one, we will see if the object already exists.
# If it does, we ignore it and move on to the next. If it doesn't, we
# build it.
# 
# Building groups will be more complicated. Right now, I think the best
# bet is to break the group up into its constituent members, make a new
# list of their UUIDs, then build the group with that list.
