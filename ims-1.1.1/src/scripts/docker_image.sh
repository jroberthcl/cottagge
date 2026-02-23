#!/bin/bash


DIRPWD=$(realpath $(pwd))
DIRCMD=$(realpath $(dirname $0))

DIRHELM=$(dirname $DIRCMD)

#Enabled default
export DYNAMIC_ENABLED=y
export EXTPLUGINS_ENABLED=y
export YUM_UPDATE_ENABLED=y
export ROOT_ENABLED=n

## functions

function checkEnabled {
   ARG=$1
   if [[ $ARG = +* ]]
   then
        shift
        LIST_ENABLED=$(echo $ARG | cut -c2- | tr ',' ' ')
        for enabled in $LIST_ENABLED
        do
          case $enabled in
                ssh)    export SSH_ENABLED=y
                        ;;
                vnc)    export VNC_ENABLED=y
                        ;;
                extplugins)    export EXTPLUGINS_ENABLED=y
                        ;;
                dynamic) export DYNAMIC_ENABLED=y
                        ;;
                yumupdate) export YUM_UPDATE_ENABLED=y
                        ;;
                *)      :
                        ;;
          esac
        done
        return 0;
   elif [[ $ARG = -* ]]
   then
        shift
        LIST_DISABLED=$(echo $ARG | cut -c2- | tr ',' ' ')
        for enabled in $LIST_DISABLED
        do
          case $enabled in
                ssh)    export SSH_ENABLED=n
                        ;;
                vnc)    export VNC_ENABLED=n
                        ;;
                extplugins)    export EXTPLUGINS_ENABLED=y
                        ;;
                dynamic) export DYNAMIC_ENABLED=n
                        ;;
                *)      :
                        ;;
          esac
        done
        return 0;
   else
        return 1;
        return 1;
   fi
}

# Defaults:
EIUM_SERVICENAME=$(basename $DIRPWD)
IMAGEDESTINATION_DEF=iumx_${EIUM_SERVICENAME}
REGISTRY_DST_NAMESPACE_DEF="eium"
REGISTRY_DST_DEF="docker-registry.cn.hpecorp.net"
IMAGE_DST_DEF=${REGISTRY_DST_DEF}/${REGISTRY_DST_NAMESPACE_DEF}/${IMAGEDESTINATION_DEF}

PROGRAM_NAME=$0
checkEnabled $1 && shift ; EXPORT_IMAGE=$1
checkEnabled $2 && shift ; PUSH_IMAGE=$2
checkEnabled $3 && shift ; IMAGE_SOURCE=$3
IMAGE_DST_TAG_DEF=${IMAGE_SOURCE##*:}
checkEnabled $5 && shift ; IMAGE_DST_TAG=${5-$IMAGE_DST_TAG_DEF}
checkEnabled $4 && shift ; IMAGE_DST=${4-${IMAGE_DST_DEF}:${IMAGE_DST_TAG}}
checkEnabled $6 && shift ;

IMAGE_SOURCE_ONLY=${IMAGE_SOURCE##*/}
IMAGE_DST_ONLY=${IMAGE_DST##*/}
REGISTRY_DST_ONLY=$(echo ${IMAGE_DST} | cut -d "/" -f 1)
JAR=$(which jar)


CCMD=$(basename $PROGRAM_NAME | cut -d "_" -f1)

if [ "$CCMD" = "podman" ]
then
        CCMD_PUSH_OPTS="--format=v2s2"
        #CCMD_BUILD="buildah build-using-dockerfile"
        CCMD_BUILD="${CCMD} build"
else
        CCMD_PUSH_OPTS=""
        CCMD_BUILD="${CCMD} build"
fi


echo
echo "======================================================================================================="
echo "Building dedicated image for eIUM microservice \"${EIUM_SERVICENAME}\" (2024)"
echo "======================================================================================================="

if [ $# -eq 0 ]
then
        echo ""
        echo "Usage: $0 [+ssh,vnc,extplugins,dynamic] <export(y/n)> <push(y/n) <source_image> <destionation_image>"
        echo ""
        echo "       Example standalone:"
        echo "                $0 N Y hub.docker.hpecorp.net:443/ctg-did/eium-standalone-sf-ubi:10.13 hub.docker.hpecorp.net/mpc-eium/eiumx_custom:10.13"
        echo "                $0 N Y mpc-docker.gre.hpecorp.net:443/eium/standalone-sf:10.6 hub.docker.hpecorp.net/mpc-eium/eoc:10.6"
        echo "                $0 N Y mpc-docker.gre.hpecorp.net:443/eium/standalone-sf:10.6 104578014729.dkr.ecr.us-east-2.amazonaws.com/chf/cgw-eoc:10.6"
        echo "                $0 N Y 104578014729.dkr.ecr.us-east-2.amazonaws.com/eium/standalone-sf:10.6 104578014729.dkr.ecr.us-east-2.amazonaws.com/chf/cgw-eoc:10.6"
        echo ""
        echo "       Argument description:"
        echo "                param #1 [optional] +ssh,vnc,extplugins,dynamic install sshd, vncserver,extract plugins or dynamic script (not support installation)"
        echo "                param #2 export image to disk [y/n]"
        echo "                param #3 push image to local [y/n] (potentially it already on local registry storage"
        echo "                param #4 image to pull. Example. hub.docker.hpecorp.net/cms-di-solutions/eium-sf-standard:10.5.2_RC5a"
        echo "                param #5 image to push. Example. docker-registry.cn.hpecorp.net/eium/eiumx_classic:10.5.2_RC5a"
        echo " "
        echo "       NOTE(*): If source or destination container registry requires login it should do before execute this command"
        echo " "
        echo "       NOTE(**): There are three container registry and repository evolved here:"
        echo "          - CR source image registry:  hub.docker.hpecorp.net/cms-di-solutions/eium-sf-standard:10.5.2_RC5a"
        echo "          - CR local repository:       localhost/eiumx_classic:10.5.2_RC5a"
        echo "          - CR destination registry:   docker-registry.cn.hpecorp.net/eium/eiumx_classic:10.5.2_RC5a"
        echo " "
        echo "       NOTE(***): export VNC_PASSWD=xxxxx; before execute $0 with +vnc"
        echo " "
        exit 1
fi

EIUM_DOCKER_DIR=$DIRHELM/tmp

if [ -f /usr/bin/oc ]
then
  OC_PRESENT=y
  OC=oc
else
  OC_PRESENT=n
  OC=kubectl
fi

echo "[INFO] Processing"
echo "[INFO]  FROM: ${IMAGE_SOURCE}"
echo "[INFO]   +    App.jar"
echo "[INFO]  TO:   ${IMAGE_DST}"
echo "[INFO]  "
echo "[INFO] CCMD=$CCMD"
echo "[INFO] CCMD_PUSH_OPTS=$CCMD_PUSH_OPTS"
echo "[INFO] EIUM_SERVICENAME=$EIUM_SERVICENAME"
echo "[INFO] EXPORT_IMAGE=$EXPORT_IMAGE"
echo "[INFO] PUSH_IMAGE=$PUSH_IMAGE"
echo "[INFO] IMAGE_SOURCE=$IMAGE_SOURCE"
echo "[INFO] IMAGE_SOURCE_ONLY=${IMAGE_SOURCE_ONLY}"
echo "[INFO] IMAGE_DST=${IMAGE_DST}"
echo "[INFO] IMAGE_DST_TAG=${IMAGE_DST_TAG}"
echo "[INFO] IMAGE_DST_ONLY=${IMAGE_DST_ONLY}"
FILE_IMG=$(echo $IMAGE_DST_ONLY | tr ':' '_')
echo "[INFO] FILE_IMG=$FILE_IMG"
echo "[INFO] $CCMD save $IMAGE_DST_ONLY -o ./images/${FILE_IMG}.img.gz"

echo "[INFO] List options enabled:"
LIST_OPTIONS="SSH VNC EXTPLUGINS DYNAMIC"
for option in $LIST_OPTIONS
do
        result=$(eval echo \${${option}"_ENABLED"})
        if [ "$result" = "y" ]
        then
                printf "[INFO] %s\n" "  * $option : $result"
        fi
done

if [ "$VNC_ENABLED" = "y" ]
then
  echo "[INFO] VNC_PASSWD=${VNC_PASSWD}"
fi


mkdir -p $EIUM_DOCKER_DIR/eium-repo
mkdir -p $EIUM_DOCKER_DIR/license



for IUMDIR in $(find . -type d -name eium)
do

  cd $IUMDIR
  YAMLFILES=$(ls *.yaml 2>/dev/null)
  NYAMLFILES=$(ls *.yaml 2>/dev/null |wc -l)

  if [ $NYAMLFILES -ne 0 ]
  then
    for YAMLFILE in $YAMLFILES
    do
      DIR=$(basename $YAMLFILE .yaml)
      APPJAR=${DIR}.jar
      echo "[INFO] Rebuild updated $APPJAR for image at the directory /eium/mnt/package.d/${APPJAR}"
         if [ -d "$DIR" ]
         then
           $JAR -cvf $APPJAR $YAMLFILE $DIR >/dev/null
           cp $APPJAR $EIUM_DOCKER_DIR/eium-repo
         else
           echo "[WARN] [*] Directory $DIR not found"
         fi
    done
  else
        echo "[WARN] [*] Directory $IUMDIR doesn't include \*.yaml"
  fi
  cd $DIRPWD
done

#echo "[INFO] Prepare license for image at the directory /eium/mnt/conf.d/license/license.conf"
#cp -r license $EIUM_DOCKER_DIR/


if [ "$DYNAMIC_ENABLED" = "y" ]
then
  echo "[INFO] Copy scripts (eg. dynamic_environment.sh)"
  if [ ! -d $EIUM_DOCKER_DIR/scripts ]
  then
    mkdir -p $EIUM_DOCKER_DIR/scripts
  fi
  for dir in $(ls -d $DIRHELM/eium/*/scripts 2>/dev/null)
  do
    cp -r  $dir $EIUM_DOCKER_DIR/
  done
  NFOUND=$(ls $EIUM_DOCKER_DIR/scripts/*sh| wc -l)
  if [ $NFOUND -eq 0 ]
  then
    echo "#!/bin/bash" > $EIUM_DOCKER_DIR/scripts/dummy.sh
  fi
fi


echo "[INFO] Prepare Dockerfile"
echo "FROM $IMAGE_SOURCE" > $EIUM_DOCKER_DIR/Dockerfile
if [ "$VNC_ENABLED" = "y" ]
then
  echo "ENV VNC_PASSWD=${VNC_PASSWD}" >> $EIUM_DOCKER_DIR/Dockerfile
fi

if [ -d ./eium/docker ]
then
  cp -r ./eium/docker $EIUM_DOCKER_DIR/
  echo "[INFO] Override docker eium scripts"
  echo "COPY docker/ /var/opt/docker/" >> $EIUM_DOCKER_DIR/Dockerfile
  echo "RUN chmod a+rx /var/opt/docker/*.sh" >> $EIUM_DOCKER_DIR/Dockerfile
fi

#echo "COPY eium-repo/ /eium/mnt/conf.d/" >> $EIUM_DOCKER_DIR/Dockerfile
echo "COPY eium-repo/ /eium/mnt/package.d/" >> $EIUM_DOCKER_DIR/Dockerfile
#echo "CMD mkdir -p /eium/mnt/conf.d/license" >> $EIUM_DOCKER_DIR/Dockerfile
#echo "COPY license/license.config /eium/mnt/conf.d/license/license.config" >> $EIUM_DOCKER_DIR/Dockerfile

if [ "$DYNAMIC_ENABLED" = "y" ]
then
  echo "USER 0" >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "WORKDIR /var/opt/ " >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "RUN mkdir -p /var/opt/scripts" >> $EIUM_DOCKER_DIR/Dockerfile
  echo "COPY scripts scripts/ " >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "RUN chmod 777 /var/opt/scripts/*.sh" >> $EIUM_DOCKER_DIR/Dockerfile
  echo "USER 10001" >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "[INFO] Add dynamice_environment variables"
fi

if [ "$SSH_ENABLED" = "y" ]
then
  echo "USER 0" >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "RUN yum install -y openssh-server openssh-clients" >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "USER 10001" >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "[INFO] Add on k8s the startup sshd -D -p 10022 and port 10022"
fi

if [ "$VNC_ENABLED" = "y" ]
then
  echo "USER 0" >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "RUN yum install -y tigervnc-server"  >> $EIUM_DOCKER_DIR/Dockerfile
  echo "RUN printf \"${VNC_PASSWD}\n${VNC_PASSWD}\n\n\" | vncpasswd "  >> $EIUM_DOCKER_DIR/Dockerfile
  echo "USER 10001" >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "[INFO] Add on k8s the startup /usr/bin/vncserver 1 -geometry 1280x1024\" and port 5901"
fi

if [ "$YUM_UPDATE_ENABLED" = "y" ]
then
  echo "[INFO] Yum update base image. started"
  echo "USER 0" >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "# Update base image with latest patches " >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "RUN yum update -y" >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "USER 10001" >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "[INFO] Yum update base image. end"
fi

if [ "$EXTPLUGINS_ENABLED" = "y" ]
then
  echo "mkdir -p $EIUM_DOCKER_DIR/plugins"
  mkdir -p $EIUM_DOCKER_DIR/plugins

  echo "cd $EIUM_DOCKER_DIR/plugins"
  cd $EIUM_DOCKER_DIR/plugins
  for plugin in $(ls $DIRHELM/eium/*/plugins/com.*zip 2>/dev/null)
  do
     echo "jar -xvf $plugin"
     jar -xf $plugin
  done
  cd -
  if [ -f $DIRHELM/eium/*/plugins/voltdbclient.jar ]
  then
    echo "cp $DIRHELM/eium/*/plugins/voltdbclient.jar $EIUM_DOCKER_DIR/plugins/"
    cp -r $DIRHELM/eium/*/plugins/voltdbclient.jar $EIUM_DOCKER_DIR/plugins/
  fi

  echo "USER 0" >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "WORKDIR /opt/SIU/ " >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "COPY plugins plugins/ " >>  $EIUM_DOCKER_DIR/Dockerfile
  echo "[INFO] Copy and extracted all plugins"
fi


if [ "$ROOT_ENABLED" = "y" ]
then
  echo "USER 0" >>  $EIUM_DOCKER_DIR/Dockerfile
fi


echo "[INFO] Building image $CCMD"
cd $EIUM_DOCKER_DIR

echo ${CCMD_BUILD} -t $IMAGE_DST_ONLY . | sed -e 's/^/  /g'
${CCMD_BUILD} -t $IMAGE_DST_ONLY . | sed -e 's/^/  /g'

echo ${CCMD} tag $IMAGE_DST_ONLY $IMAGE_DST | sed -e 's/^/  /g'
${CCMD} tag $IMAGE_DST_ONLY $IMAGE_DST | sed -e 's/^/  /g'

cd - 1>/dev/null

if [ "$PUSH_IMAGE" = "y" -o "$PUSH_IMAGE" = "Y" ]
then
  echo ""
  echo "[INFO] ${CCMD} push"
  if [ "$OC_PRESENT" = "y" ]
  then
    $CCMD login $REGISTRY_DST_ONLY
    echo $CCMD push $CCMD_PUSH_OPTS $IMAGE_DST | sed -e 's/^/  /g'
    $CCMD push $CCMD_PUSH_OPTS $IMAGE_DST 2>&1 | sed -e 's/^/  /g'
  else
    $CCMD push $CCMD_PUSH_OPTS $IMAGE_DST 2>&1 | sed -e 's/^/  /g'
  fi
fi

if [ "$EXPORT_IMAGE" = "y" -o "$EXPORT_IMAGE" = "Y" ]
then
  echo ""
  echo "[INFO] ${CCMD} save image \"$IMAGE_DST_ONLY\" to \"./images/${FILE_IMG}.img.gz\""
  if [ -d ./images ]
  then
        rm -fr ./images/*
  else
        mkdir -p ./images
  fi
  $CCMD save $IMAGE_DST_ONLY -o ./images/${FILE_IMG}.img
  gzip ./images/${FILE_IMG}.img
fi

