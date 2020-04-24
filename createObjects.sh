#!/usr/bin/env bash
# TODO:
# • Add support for networks, not just hosts.
printUsage() {
	echo "Usage:"
	echo "$0 [-d] [-h] [-f file] [-I] [-g | -a | -c \"CMA\"] \"<project>\""
	echo "Default output is pretty-print JSON to STDOUT, suitable for output redirection."
	echo -e "\t-d\tIncrease debug level, up to twice."
	echo -e "\t-h\tPrint this usage information."
	echo -e "\t-f file\tAccept input from <file>."
	echo -e "\t-I\tAccept input from STDIN."
	echo -e "\t-g\tOn an MDS, build global objects."
	echo -e "\t-a\tOn an MDS, build objects on all CMAs, but not globally."
	echo -e "\t-c CMA\tOn an MDS, build objects on the named CMA."
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
	echo ".duckduckgo.com"
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

buildGlobalObjects() {
	debug1 "Entering buildGlobalObjects."
	echo "ERROR: Building global objects is not yet implemented." >&2
	exit 2
	}

buildOnAllCMAs() {
	debug1 "Entering buildOnAllCMAs."
	mgmt_cli login read-only true -r true > sessionFile.txt
	MDSDomains=( $(mgmt_cli -s sessionFile.txt --format json show domains | jq -c ".objects[].name" | sed 's/"//g') )
	mgmt_cli -s sessionFile.txt logout>/dev/null
	/bin/rm sessionFile.txt
	for CMA in "${MDSDomains[@]}"; do
		buildOnCMA "${CMA}"
		done
	}

buildOnCMA() {
	debug1 "Entering buildOnCMA for the CMA named \"${mdsBuildOnCMA}\"."
	echo "ERROR: Building objects on a CMA is not yet implemented." >&2
	exit 2
	}

buildOnSmartCenter() {
	debug1 "Entering buildOnSmartCenter."
	echo "ERROR: Building objects on a SmartCenter is not yet implemented." >&2
	exit 2
	}



########################################################################
## Execution begins here.
########################################################################

if [ $# -eq 0 ]; then
	printUsage
	exit 1
	fi

declare -i debugLevel=0
inputFile=""
readFromSTDIN=false
mdsBuildGlobal=false
mdsBuildOnAllCMAs=false
mdsBuildOnCMA=""
declare -i mdsOptCount=0

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

while getopts ":dhf:Igac:" options; do
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
	g)
		mdsBuildGlobal=true
		mdsOptCount+=1
		;;
	a)
		mdsBuildOnAllCMAs=true
		mdsOptCount+=1
		;;
	c)
		mdsBuildOnCMA="${OPTARG}"
		mdsOptCount+=1
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

if [ "${mdsOptCount}" -gt 1 ]; then
	echo "ERROR: You may only specify one of -g, -a, or -c." >&2
	exit 1
	fi

########################################################################
## Done reading and validating command line options. Next, we read the
## data, either from STDIN or from the specified file.
########################################################################

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

########################################################################
## Now that we have the raw data, time to split it up into the different
## types of objects we will handle later.
########################################################################

IFS=$'\n' dedupedObjectList=($(sort <<< "${rawObjectList[*]}" | uniq)); unset IFS
unset rawObjectList
debug2 "Deduplicated object list: ${dedupedObjectList[*]}"

debug1 "Splitting objects."
for item in "${dedupedObjectList[@]}"; do
	if $(echo "${item}" | egrep ",[a-zA-Z]" > /dev/null); then
		debug2 "$item looks like a service group."
		serviceGroupList+=("$item")
	elif $(echo "${item}" | egrep "^[a-zA-Z]" > /dev/null); then
		debug2 "$item looks like a service."
		rawServiceList+=("$item")
	elif $(echo "${item}" | grep "," > /dev/null); then
		debug2 "$item looks like a network group."
		networkGroupList+=("$item")
	elif $(echo "${item}" | egrep "^\." > /dev/null); then
		debug2 "$item looks like a fully-qualified domain name."
		fqdnList+=("$item")
	elif $(echo "${item}" | grep "-" > /dev/null); then
		debug2 "$item looks like an address range."
		addressRangeList+=("$item")
	elif $(echo "${item}" | grep "/" > /dev/null); then
		debug2 "$item looks like a network."
		networkList+=("$item")
	else
		debug2 "$item looks like a host."
		hostList+=("$item")
		fi
	done

debug1 "Further splitting services."
for item in "${rawServiceList[@]}"; do
	if $(echo "${item}" | egrep "^TCP" >/dev/null); then
		port="$(echo "${item}" | cut -d' ' -f2)"
		debug2 "$item looks like a TCP service covering port(s) ${port}."
		tcpServiceList+=("${port}")
	elif $(echo "${item}" | egrep "^UDP" >/dev/null); then
		port="$(echo "${item}" | cut -d' ' -f2)"
		debug2 "$item looks like a UDP service covering port(s) ${port}."
		udpServiceList+=("${port}")
	elif $(echo "${item}" | egrep "^IP" >/dev/null); then
		protocol="$(echo "${item}" | cut -d' ' -f2)"
		debug2 "$item looks like a service covering IP protocol ${protocol}."
		ipServiceList+=("${protocol}")
	else
		echo "WARNING: Unhandled service: $item" >&2
		fi
	done
unset rawServiceList

########################################################################
## We now have a set of lists per object type we will create. Having the
## lists separated will let us build the group members before the
## groups. Next, we will connect to the managements and iterate through
## the objects. For each one, we will see if the object already exists.
## If it does, we ignore it and move on to the next. If it doesn't, we
## build it.
## 
## Building groups will be more complicated. Right now, I think the best
## bet is to break the group up into its constituent members, make a new
## list of their UUIDs, then build the group with that list.
########################################################################

if [ "${mdsOptCount}" -eq 0 ]; then
	buildOnSmartCenter
elif [[ "${mdsBuildGlobal}" == true ]]; then
	buildGlobalObjects
elif [[ "${mdsBuildOnAllCMAs}" == true ]]; then
	buildOnAllCMAs
elif [ "${mdsBuildOnCMA}" != "" ]; then
	buildOnCMA "${mdsBuildOnCMA}"
else
	echo "ERROR: Something went wrong determining where to build the objects." >&2
	exit 1
	fi
