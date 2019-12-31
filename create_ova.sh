#!/bin/bash 
#
# Packing script for creating yaml based OVA.
#
#
# Copyright (c) 2015 by cisco Systems, Inc.
# All rights reserved
#
#
# History:
# 1.0       -      Initial version


# UALG set to 0: do not sign
UALG=0;
ALG=$UALG

VER=v1.0
SYS=$(/bin/uname -s)
#
# Set extention to mf if sha1 or none
#
EXT=mf
CMDS="cut tr du tar bzip2 shasum"

#
#If total directory size exceeds this, compress large files to reduce total size
#
MAX_TOTAL_SIZE=600 

#
#If MAX_TOTAL_SIZE is exceeded, compress each file larger than this threshold.
#
MAX_FILE_SIZE_M=10 
((MAX_FILE_SIZE_K=MAX_FILE_SIZE_M*1024))
MAX_FILE_NAME=80

#
# Get the package name from the package.yaml file
#
PACKAGE_FILE=package.yaml

function show_help () {
    echo "Usage: $0 [<options>] <directory>"
    echo
    echo "Options:
          -mts or -max_total_size <num> - (default ${MAX_TOTAL_SIZE})
            Specify the maximum directory size before compression is considered.
          -mfs or -max_file_size <num>  - (default ${MAX_FILE_SIZE_M}) If 
            max_total_size is exceeded, compress each file larger than this 
            threshold.
            Together -mts and -mfs provide a heuristic to calculate whether
            or not to compress large files. If total directory size
            exceeds -max_total_size, compress files greater than -max_file_size
            Specifying '-max_total_size 0' will force compression on all files
            greater than -max_file_size
            Setting -max_total_size to a very high value will enforce zero
            compression

           Example: '$0 Test' - Use SHA1, and create OVA file
           Example: '$0 -mts 500 -mfs 20 Test' - Use SHA1,
            compress files greater than 20M if
            total directory size of 'Test' is greater than 500M"
    echo
    exit 1
}

function compute_sha () {

    #
    # Run through all the files in the directory, calculating the
    # SHA and adding them to the manifest file
    #
    echo "Running SHA$ALG over all files in '$PWD' and
    creating manifest file '$PACKAGE.$EXT', please wait..."
    echo
    let COUNT=0
    for i in $( ls ); do
        let COUNT=COUNT+1
        
        SKIP_FILE=0
        
        #
        # Omit files of .mf/.mf2/.cert/.env extensions
        # This needs to change as more methods get added
        if echo "$i" | grep -q '.mf$'; then
            SKIP_FILE=1
        elif echo "$i" | grep -q '.mf2$'; then
            SKIP_FILE=1
        elif echo "$i" | grep -q '.cert$'; then
            SKIP_FILE=1
        elif echo "$i" | grep -q '.env$'; then
            SKIP_FILE=1
        fi

        if [[ $SKIP_FILE = 1 ]]; then
            echo "Skipping $i"
            continue
        fi

        SHA=$(shasum -a $ALG $i | sed "s/$i//")

        if [[ $COUNT = 1 ]]; then
            echo "SHA$ALG($i)= $SHA" > $PACKAGE.$EXT
        else
            echo "SHA$ALG($i)= $SHA" >> $PACKAGE.$EXT
        fi
    done

    echo "Done creating '$PACKAGE.$EXT' file"
}

echo "$(basename $0) $VER($SYS) - Create a virtual-service OVA package"
echo

###################
# Sanity checking
###################

#
# No arguments - always need a directory...
#
if [[ "$#" = 0 ]]; then
    show_help;
fi

#
# Read user options
#
while [[ "$#" != 0 ]];
do
    case $1 in
	-mts | -max_total_size )
	    MAX_TOTAL_SIZE=$2;
	    ;;
	-mfs | -max_file_size )
	    MAX_FILE_SIZE_M=$2;
	    ((MAX_FILE_SIZE_K=MAX_FILE_SIZE_M*1024))
	    ;;
	-h | -help )
	    show_help;
	    ;;
	-* )
	    echo "Unknown option $1"
	    show_help;
	    ;;
	* )
	    DIR=$1
	    ;;
    esac
    shift
done

echo -e "User inputs:
  Compress=(files > '${MAX_FILE_SIZE_M}M' if total 
            file size > '${MAX_TOTAL_SIZE}M')
  Directory=$DIR"

echo ""

#
# Commands lookup
#
for i in $CMDS
do
   type -P $i &> /dev/null && continue || 
        { echo "$i command not found."; exit 1; }
done

if [[ ! -d "$DIR" ]]; then
    echo "Error: directory '$DIR' does not exist."
    echo
    exit 1
fi

cd $DIR

#
# Remove any autogened files
#
rm -f *.mf *.mf2 *.ova *.cert *.env

if [ -f $PACKAGE_FILE ];
then
    PACKAGE=$(grep " name:" $PACKAGE_FILE | cut -d ":" -f 2)
    echo "Package name : $PACKAGE"
else 
    echo "Error: YAML package file '$PACKAGE_FILE' does not exist."
    echo
    exit 1
fi
      

if [[ $UALG = 0 ]] || [[ "$UALG" = "1" ]]; then
    echo " Generating SHA1 on files..."
    ALG=1
    EXT=mf
    compute_sha
    echo " ...Done Generating SHA1 on files"
fi

# 
# Calculate total directory size to see if we need to compress large files.
#
TOTAL_SIZE=$(du -sh -m . | cut -d "." -f1 | tr -d ' \t')
LARGE_FILES=$(find . -type f -size +${MAX_FILE_SIZE_K}k)

if [[ "$LARGE_FILES" ]]; then
    if ((TOTAL_SIZE > MAX_TOTAL_SIZE)); then
	echo "Note: total directory size '${TOTAL_SIZE}M' is greater than "
        echo "'${MAX_TOTAL_SIZE}M', compress the following files which are "
        echo "greater than '${MAX_FILE_SIZE_M}M' with bzip2:"
	for i in ${LARGE_FILES}; do
	    ls -lh $i | awk '{ print $9 ": " $5 }'
	    bzip2 $i
	done
	echo
	echo "New file sizes are:"
	for i in ${LARGE_FILES}; do
	    ls -lh ${i}.bz2 | awk '{ print $9 ": " $5 }'
	done
	echo
    else
        # Reset LARGE_FILES because although some were detected the total file
	# size wasn't breached so no compression occurred & no cleanup is needed
	echo "Note: total directory size '${TOTAL_SIZE}M' is not greater than"
        echo " '${MAX_TOTAL_SIZE}M', files will not be compressed."
	echo
	LARGE_FILES=
    fi
fi

# The package is now signed
echo "Creating '$PACKAGE.ova' please wait..."
tar -cvf $PACKAGE.ova *

echo
echo "'$PWD/$PACKAGE.ova' created"
echo
echo "Manifest Contents:"
cat *.$EXT

#
# Uncompress any files that were compressed
#
echo
if  [[ "$LARGE_FILES" ]]; then
    echo "Uncompressing:
$LARGE_FILES"
    for i in ${LARGE_FILES}; do
	bzip2 -d ${i}.bz2
    done
fi
