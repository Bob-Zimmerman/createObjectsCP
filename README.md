# createObjectsCP
A script for mass creation of simple objects on a Check Point management. This is a building block for future tools.

## NOTE: This is not yet functional.
```Usage:
./createObjects.sh [-d] [-h] [-f file] [-I] [-g | -a | -c "CMA"] "<project>"
	-d	Increase debug level, up to twice.
	-h	Print this usage information.
	-f file	Accept input from <file>.
	-I	Accept input from STDIN.
	-g	On an MDS, build global objects.
	-a	On an MDS, build objects on all CMAs, but not globally.
	-c CMA	On an MDS, build objects on the named CMA.
	project	Quote-delimited project name, used in any new object names.

Example:
./createObjects.sh -f newObjects.txt "My New Objects"

Note: Input should be one object per line. For example:
10.20.30.40
10.20.30.40-10.20.30.50
10.20.30.0/24
192.168.30.40,10.20.30.40
TCP 8080
IP 12
TCP 80,TCP 443
.duckduckgo.com
```
