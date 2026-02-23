#!/bin/bash

CONTAINER_NAME=$1
MAX_NUM_MYSQL=$2
FORCE=$3
FILEOUT=/var/opt/SIU/dynamic_environment.conf

echo "[INFO] ==================================================================="
echo "[INFO] Dynamic environment script configuration to $FILEOUT"
echo "[INFO] ==================================================================="

#if [ ! -f $FILEOUT ]
#then
   echo "[INFO] Created file $FILEOUT"
   > $FILEOUT
#fi

######################################
# DYNAMIC ARGS
######################################
echo "[INFO] Dynamic arguments"
for var in $DYNAMIC_ARGUMENTS
do
  variable=$(echo $var | cut -d= -f1 | tr -d ' ')
  value=$(echo $var | cut -d= -f2- | tr '\n' ' ' | tr -d '\t')
  value=$(eval echo $value)

  if [ "$variable" != "" ]
  then
    #echo export $variable="$value"
    eval $variable="$value"
    export $variable="$value"

    NFOUND=$(grep ^$variable= $FILEOUT 2>/dev/null | wc -l)
    if [[ $NFOUND -eq 0 ]]||[[ "$FORCE" = "-y" ]]
    then
	grep -v "^$variable=" $FILEOUT > ${FILEOUT}.tmp
	mv ${FILEOUT}.tmp ${FILEOUT}
	printf "%s=%s\n" "$variable" "$value" >> $FILEOUT
	printf "  [W] %s=%s\n" $variable $value
    else
	#echo "[INFO] $var wasn't overrite, using values from $FILEOUT"
	grep ^$variable= $FILEOUT | sed -e 's/^/  \[R\] /g'
    fi
  fi
done


#############################
# BASIC VARIABLES
#############################
echo "[INFO] Basic variables"

if [[ "$CONTAINER_NAME" = "" ]] || [[ "$CONTAINER_NAME" = "none" ]] || [[ "$CONTAINER_NAME" = "by_hostname" ]]
then
	CONTAINER_NAME=$(hostname)
fi
export CONTAINER_NAME
echo "CONTAINER_NAME=$CONTAINER_NAME" >> $FILEOUT

if [[ $CONTAINER_NAME =~ -([0-9]+)$ ]]
then
  export CONTAINER_INDEX=${BASH_REMATCH[1]}
else
  export CONTAINER_INDEX=0
fi
echo "CONTAINER_INDEX=$CONTAINER_INDEX" >> $FILEOUT


if [ "$MAX_NUM_MYSQL" != "" ]
then
	export DB_INDEX=$((${CONTAINER_INDEX} % $MAX_NUM_MYSQL))
else
	export DB_INDEX=0
fi
echo "DB_INDEX=$DB_INDEX" >> $FILEOUT


#############################
# CONTAINED_INDEX
#############################
NFOUND=$(grep ^CONTAINER_INDEX= $FILEOUT 2>/dev/null | wc -l)

if [[ $NFOUND -eq 0 ]]||[[ "$FORCE" = "-y" ]]
then
	grep -v "^CONTAINER_INDEX=" $FILEOUT > ${FILEOUT}.tmp
	mv ${FILEOUT}.tmp ${FILEOUT}

	echo "CONTAINER_INDEX=$CONTAINER_INDEX" >> $FILEOUT
	echo "  [W] CONTAINER_INDEX=$CONTAINER_INDEX"
else
	#echo "[INFO] CONTAINER_INDEX not overrite, using previous values in $FILEOUT"
	grep ^CONTAINER_INDEX= $FILEOUT | sed -e 's/^/  \[R\] /g'
fi


#############################
# DB_INDEX
#############################
NFOUND=$(grep ^DB_INDEX= $FILEOUT 2>/dev/null | wc -l)

if [[ $NFOUND -eq 0 ]]||[[ "$FORCE" = "-y" ]]
then
	grep -v "^DB_INDEX=" $FILEOUT > ${FILEOUT}.tmp
	mv ${FILEOUT}.tmp ${FILEOUT}

	echo "DB_INDEX=$DB_INDEX" >> $FILEOUT
	echo "  [W] DB_INDEX=$DB_INDEX"
else
	#echo "[INFO] DB_INDEX not overrite, using previous values in $FILEOUT"
	grep ^DB_INDEX= $FILEOUT | sed -e 's/^/  \[R\] /g'
fi
export DB_INDEX

######################################
# DYNAMIC ENVIRONMENT replacement
######################################
echo "[INFO] Dynamic variables"
for var in $DYNAMIC_ENVIRONMENT
do
  variable=$(echo $var | cut -d= -f1)
  value=$(echo $var | cut -d= -f2-)
  value=$(eval echo $value)

  if [[ "$variable" = MKDIR* ]]
  then
    value=$(echo "$value" | tr ',' ' ')
  fi

  if [ "$variable" != "" ]
  then
    #echo "variable=:$variable:"
    #echo "value=:$value:"
    export $variable="$value"

    NFOUND=$(grep ^$variable= $FILEOUT 2>/dev/null | wc -l)
    if [[ $NFOUND -eq 0 ]]||[[ "$FORCE" = "-y" ]]
    then
	grep -v "^$variable=" $FILEOUT > ${FILEOUT}.tmp
	mv ${FILEOUT}.tmp ${FILEOUT}
	printf "%s=\"%s\"\n" "$variable" "$value" >> $FILEOUT
	printf "  [W] %s=\"%s\"\n" "$variable" "$value"
    else
	#echo "[INFO] $var wasn't overrite, using values from $FILEOUT"
	grep ^$variable= $FILEOUT | sed -e 's/^/  \[R\] /g'
    fi
  fi
done
