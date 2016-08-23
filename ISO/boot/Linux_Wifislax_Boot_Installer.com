#!/bin/sh
# This script was generated using Makeself 2.2.0

umask 077

CRCsum="1905609867"
MD5="b3749cd6a2f38aa005219d9b70b07846"
TMPROOT=${TMPDIR:=/tmp}

label="Wifislax Bootloader Installer"
script=".wifislax_bootloader_installer/bootinst.com;/bin/bash"
scriptargs=""
licensetxt=""
targetdir="."
filesizes="491520"
keep="y"
quiet="n"

print_cmd_arg=""
if type printf > /dev/null; then
    print_cmd="printf"
elif test -x /usr/ucb/echo; then
    print_cmd="/usr/ucb/echo"
else
    print_cmd="echo"
fi

unset CDPATH

MS_Printf()
{
    $print_cmd $print_cmd_arg "$1"
}

MS_PrintLicense()
{
  if test x"$licensetxt" != x; then
    echo $licensetxt
    while true
    do
      MS_Printf "Please type y to accept, n otherwise: "
      read yn
      if test x"$yn" = xn; then
        keep=n
 	eval $finish; exit 1        
        break;    
      elif test x"$yn" = xy; then
        break;
      fi
    done
  fi
}

MS_diskspace()
{
	(
	if test -d /usr/xpg4/bin; then
		PATH=/usr/xpg4/bin:$PATH
	fi
	df -kP "$1" | tail -1 | awk '{ if ($4 ~ /%/) {print $3} else {print $4} }'
	)
}

MS_dd()
{
    blocks=`expr $3 / 1024`
    bytes=`expr $3 % 1024`
    dd if="$1" ibs=$2 skip=1 obs=1024 conv=sync 2> /dev/null | \
    { test $blocks -gt 0 && dd ibs=1024 obs=1024 count=$blocks ; \
      test $bytes  -gt 0 && dd ibs=1 obs=1024 count=$bytes ; } 2> /dev/null
}

MS_dd_Progress()
{
    if test "$noprogress" = "y"; then
        MS_dd $@
        return $?
    fi
    file="$1"
    offset=$2
    length=$3
    pos=0
    bsize=4194304
    while test $bsize -gt $length; do
        bsize=`expr $bsize / 4`
    done
    blocks=`expr $length / $bsize`
    bytes=`expr $length % $bsize`
    (
        dd bs=$offset count=0 skip=1 2>/dev/null
        pos=`expr $pos \+ $bsize`
        MS_Printf "     0%% " 1>&2
        if test $blocks -gt 0; then
            while test $pos -le $length; do
                dd bs=$bsize count=1 2>/dev/null
                pcent=`expr $length / 100`
                pcent=`expr $pos / $pcent`
                if test $pcent -lt 100; then
                    MS_Printf "\b\b\b\b\b\b\b" 1>&2
                    if test $pcent -lt 10; then
                        MS_Printf "    $pcent%% " 1>&2
                    else
                        MS_Printf "   $pcent%% " 1>&2
                    fi
                fi
                pos=`expr $pos \+ $bsize`
            done
        fi
        if test $bytes -gt 0; then
            dd bs=$bytes count=1 2>/dev/null
        fi
        MS_Printf "\b\b\b\b\b\b\b" 1>&2
        MS_Printf " 100%%  " 1>&2
    ) < "$file"
}

MS_Help()
{
    cat << EOH >&2
Makeself version 2.2.0
 1) Getting help or info about $0 :
  $0 --help   Print this message
  $0 --info   Print embedded info : title, default target directory, embedded script ...
  $0 --lsm    Print embedded lsm entry (or no LSM)
  $0 --list   Print the list of files in the archive
  $0 --check  Checks integrity of the archive
 
 2) Running $0 :
  $0 [options] [--] [additional arguments to embedded script]
  with following options (in that order)
  --confirm             Ask before running embedded script
  --quiet		Do not print anything except error messages
  --noexec              Do not run embedded script
  --keep                Do not erase target directory after running
			the embedded script
  --noprogress          Do not show the progress during the decompression
  --nox11               Do not spawn an xterm
  --nochown             Do not give the extracted files to the current user
  --target dir          Extract directly to a target directory
                        directory path can be either absolute or relative
  --tar arg1 [arg2 ...] Access the contents of the archive through the tar command
  --                    Following arguments will be passed to the embedded script
EOH
}

MS_Check()
{
    OLD_PATH="$PATH"
    PATH=${GUESS_MD5_PATH:-"$OLD_PATH:/bin:/usr/bin:/sbin:/usr/local/ssl/bin:/usr/local/bin:/opt/openssl/bin"}
	MD5_ARG=""
    MD5_PATH=`exec <&- 2>&-; which md5sum || type md5sum`
    test -x "$MD5_PATH" || MD5_PATH=`exec <&- 2>&-; which md5 || type md5`
	test -x "$MD5_PATH" || MD5_PATH=`exec <&- 2>&-; which digest || type digest`
    PATH="$OLD_PATH"

    if test "$quiet" = "n";then
    	MS_Printf "Verifying archive integrity..."
    fi
    offset=`head -n 502 "$1" | wc -c | tr -d " "`
    verb=$2
    i=1
    for s in $filesizes
    do
		crc=`echo $CRCsum | cut -d" " -f$i`
		if test -x "$MD5_PATH"; then
			if test `basename $MD5_PATH` = digest; then
				MD5_ARG="-a md5"
			fi
			md5=`echo $MD5 | cut -d" " -f$i`
			if test $md5 = "00000000000000000000000000000000"; then
				test x$verb = xy && echo " $1 does not contain an embedded MD5 checksum." >&2
			else
				md5sum=`MS_dd "$1" $offset $s | eval "$MD5_PATH $MD5_ARG" | cut -b-32`;
				if test "$md5sum" != "$md5"; then
					echo "Error in MD5 checksums: $md5sum is different from $md5" >&2
					exit 2
				else
					test x$verb = xy && MS_Printf " MD5 checksums are OK." >&2
				fi
				crc="0000000000"; verb=n
			fi
		fi
		if test $crc = "0000000000"; then
			test x$verb = xy && echo " $1 does not contain a CRC checksum." >&2
		else
			sum1=`MS_dd "$1" $offset $s | CMD_ENV=xpg4 cksum | awk '{print $1}'`
			if test "$sum1" = "$crc"; then
				test x$verb = xy && MS_Printf " CRC checksums are OK." >&2
			else
				echo "Error in checksums: $sum1 is different from $crc" >&2
				exit 2;
			fi
		fi
		i=`expr $i + 1`
		offset=`expr $offset + $s`
    done
    if test "$quiet" = "n";then
    	echo " All good."
    fi
}

UnTAR()
{
    if test "$quiet" = "n"; then
    	tar $1vf - 2>&1 || { echo Extraction failed. > /dev/tty; kill -15 $$; }
    else

    	tar $1f - 2>&1 || { echo Extraction failed. > /dev/tty; kill -15 $$; }
    fi
}

finish=true
xterm_loop=
noprogress=n
nox11=n
copy=none
ownership=y
verbose=n

initargs="$@"

while true
do
    case "$1" in
    -h | --help)
	MS_Help
	exit 0
	;;
    -q | --quiet)
	quiet=y
	noprogress=y
	shift
	;;
    --info)
	echo Identification: "$label"
	echo Target directory: "$targetdir"
	echo Uncompressed size: 492 KB
	echo Compression: none
	echo Date of packaging: Fri May 27 17:23:54 CEST 2016
	echo Built with Makeself version 2.2.0 on linux-gnu
	echo Build command was: "/usr/bin/makeself.sh \\
    \"--notemp\" \\
    \"--nocomp\" \\
    \"--target\" \\
    \".\" \\
    \"./\" \\
    \"/root/Desktop/Linux_Wifislax_Boot_Installer.com\" \\
    \"Wifislax Bootloader Installer\" \\
    \".wifislax_bootloader_installer/bootinst.com;/bin/bash\""
	if test x$script != x; then
	    echo Script run after extraction:
	    echo "    " $script $scriptargs
	fi
	if test x"" = xcopy; then
		echo "Archive will copy itself to a temporary location"
	fi
	if test x"y" = xy; then
	    echo "directory $targetdir is permanent"
	else
	    echo "$targetdir will be removed after extraction"
	fi
	exit 0
	;;
    --dumpconf)
	echo LABEL=\"$label\"
	echo SCRIPT=\"$script\"
	echo SCRIPTARGS=\"$scriptargs\"
	echo archdirname=\".\"
	echo KEEP=y
	echo COMPRESS=none
	echo filesizes=\"$filesizes\"
	echo CRCsum=\"$CRCsum\"
	echo MD5sum=\"$MD5\"
	echo OLDUSIZE=492
	echo OLDSKIP=503
	exit 0
	;;
    --lsm)
cat << EOLSM
No LSM.
EOLSM
	exit 0
	;;
    --list)
	echo Target directory: $targetdir
	offset=`head -n 502 "$0" | wc -c | tr -d " "`
	for s in $filesizes
	do
	    MS_dd "$0" $offset $s | eval "cat" | UnTAR t
	    offset=`expr $offset + $s`
	done
	exit 0
	;;
	--tar)
	offset=`head -n 502 "$0" | wc -c | tr -d " "`
	arg1="$2"
    if ! shift 2; then MS_Help; exit 1; fi
	for s in $filesizes
	do
	    MS_dd "$0" $offset $s | eval "cat" | tar "$arg1" - $*
	    offset=`expr $offset + $s`
	done
	exit 0
	;;
    --check)
	MS_Check "$0" y
	exit 0
	;;
    --confirm)
	verbose=y
	shift
	;;
	--noexec)
	script=""
	shift
	;;
    --keep)
	keep=y
	shift
	;;
    --target)
	keep=y
	targetdir=${2:-.}
    if ! shift 2; then MS_Help; exit 1; fi
	;;
    --noprogress)
	noprogress=y
	shift
	;;
    --nox11)
	nox11=y
	shift
	;;
    --nochown)
	ownership=n
	shift
	;;
    --xwin)
	finish="echo Press Return to close this window...; read junk"
	xterm_loop=1
	shift
	;;
    --phase2)
	copy=phase2
	shift
	;;
    --)
	shift
	break ;;
    -*)
	echo Unrecognized flag : "$1" >&2
	MS_Help
	exit 1
	;;
    *)
	break ;;
    esac
done

if test "$quiet" = "y" -a "$verbose" = "y";then
	echo Cannot be verbose and quiet at the same time. >&2
	exit 1
fi

MS_PrintLicense

case "$copy" in
copy)
    tmpdir=$TMPROOT/makeself.$RANDOM.`date +"%y%m%d%H%M%S"`.$$
    mkdir "$tmpdir" || {
	echo "Could not create temporary directory $tmpdir" >&2
	exit 1
    }
    SCRIPT_COPY="$tmpdir/makeself"
    echo "Copying to a temporary location..." >&2
    cp "$0" "$SCRIPT_COPY"
    chmod +x "$SCRIPT_COPY"
    cd "$TMPROOT"
    exec "$SCRIPT_COPY" --phase2 -- $initargs
    ;;
phase2)
    finish="$finish ; rm -rf `dirname $0`"
    ;;
esac

if test "$nox11" = "n"; then
    if tty -s; then                 # Do we have a terminal?
	:
    else
        if test x"$DISPLAY" != x -a x"$xterm_loop" = x; then  # No, but do we have X?
            if xset q > /dev/null 2>&1; then # Check for valid DISPLAY variable
                GUESS_XTERMS="xterm rxvt dtterm eterm Eterm kvt konsole aterm"
                for a in $GUESS_XTERMS; do
                    if type $a >/dev/null 2>&1; then
                        XTERM=$a
                        break
                    fi
                done
                chmod a+x $0 || echo Please add execution rights on $0
                if test `echo "$0" | cut -c1` = "/"; then # Spawn a terminal!
                    exec $XTERM -title "$label" -e "$0" --xwin "$initargs"
                else
                    exec $XTERM -title "$label" -e "./$0" --xwin "$initargs"
                fi
            fi
        fi
    fi
fi

if test "$targetdir" = "."; then
    tmpdir="."
else
    if test "$keep" = y; then
	if test "$quiet" = "n";then
	    echo "Creating directory $targetdir" >&2
	fi
	tmpdir="$targetdir"
	dashp="-p"
    else
	tmpdir="$TMPROOT/selfgz$$$RANDOM"
	dashp=""
    fi
    mkdir $dashp $tmpdir || {
	echo 'Cannot create target directory' $tmpdir >&2
	echo 'You should try option --target dir' >&2
	eval $finish
	exit 1
    }
fi

location="`pwd`"
if test x$SETUP_NOCHECK != x1; then
    MS_Check "$0"
fi
offset=`head -n 502 "$0" | wc -c | tr -d " "`

if test x"$verbose" = xy; then
	MS_Printf "About to extract 492 KB in $tmpdir ... Proceed ? [Y/n] "
	read yn
	if test x"$yn" = xn; then
		eval $finish; exit 1
	fi
fi

if test "$quiet" = "n";then
	MS_Printf "Uncompressing $label"
fi
res=3
if test "$keep" = n; then
    trap 'echo Signal caught, cleaning up >&2; cd $TMPROOT; /bin/rm -rf $tmpdir; eval $finish; exit 15' 1 2 3 15
fi

leftspace=`MS_diskspace $tmpdir`
if test -n "$leftspace"; then
    if test "$leftspace" -lt 492; then
        echo
        echo "Not enough space left in "`dirname $tmpdir`" ($leftspace KB) to decompress $0 (492 KB)" >&2
        if test "$keep" = n; then
            echo "Consider setting TMPDIR to a directory with more free space."
        fi
        eval $finish; exit 1
    fi
fi

for s in $filesizes
do
    if MS_dd_Progress "$0" $offset $s | eval "cat" | ( cd "$tmpdir"; UnTAR x ) 1>/dev/null; then
		if test x"$ownership" = xy; then
			(PATH=/usr/xpg4/bin:$PATH; cd "$tmpdir"; chown -R `id -u` .;  chgrp -R `id -g` .)
		fi
    else
		echo >&2
		echo "Unable to decompress $0" >&2
		eval $finish; exit 1
    fi
    offset=`expr $offset + $s`
done
if test "$quiet" = "n";then
	echo
fi

cd "$tmpdir"
res=0
if test x"$script" != x; then
    if test x"$verbose" = xy; then
		MS_Printf "OK to execute: $script $scriptargs $* ? [Y/n] "
		read yn
		if test x"$yn" = x -o x"$yn" = xy -o x"$yn" = xY; then
			eval $script $scriptargs $*; res=$?;
		fi
    else
		eval $script $scriptargs $*; res=$?
    fi
    if test $res -ne 0; then
		test x"$verbose" = xy && echo "The program '$script' returned an error code ($res)" >&2
    fi
fi
if test "$keep" = n; then
    cd $TMPROOT
    /bin/rm -rf $tmpdir
fi
eval $finish; exit $res
./                                                                                                  0000755 0000000 0000000 00000000000 12722063107 007711  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ./.wifislax_bootloader_installer/                                                                   0000700 0000000 0000000 00000000000 12722063147 016076  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ./.wifislax_bootloader_installer/bootinst.com                                                       0000644 0000000 0000000 00000006560 12722063143 020454  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "Not running as root"
    exit
fi

# Colores
CIERRE=${CIERRE:-"[0m"}
ROJO=${ROJO:-"[1;31m"}
VERDE=${VERDE:-"[1;32m"}
CYAN=${CYAN:-"[1;36m"}
AMARILLO=${AMARILLO:-"[1;33m"}
BLANCO=${BLANCO:-"[1;37m"}
ROSA=${ROSA:-"[1;35m"}

chmod 0777 /tmp &> /dev/null
set -e
TARGET=""
MBR=""
TEMPINSTALL=`pwd`
EXECUTABLES="$TEMPINSTALL/.wifislax_bootloader_installer"

# Funcion que limpia
f_exitmode() {
   rm -Rf $EXECUTABLES &>/dev/null
   exit 1
}

trap f_exitmode SIGHUP SIGINT

if [ $(uname -m) = x86_64 ]; then
LILOLOADER=lilo64.com
SYSLINUXLOADER=syslinux64.com
else
LILOLOADER=lilo32.com
SYSLINUXLOADER=syslinux32.com
fi

# Find out which partition or disk are we using
MYMNT=$(cd -P $(dirname $0) ; pwd)
while [ "$MYMNT" != "" -a "$MYMNT" != "." -a "$MYMNT" != "/" ]; do
   TARGET=$(egrep "[^[:space:]]+[[:space:]]+$MYMNT[[:space:]]+" /proc/mounts | cut -d " " -f 1)
   if [ "$TARGET" != "" ]; then break; fi
   MYMNT=$(dirname "$MYMNT")
done

if [ "$TARGET" = "" ]; then
   echo $ROJO
   echo "No encuentro el dispositivo."
   echo "Este seguro de ejecutar este script en un dispositivo montado."
   echo $CIERRE
   exit 1
fi

if [ "$(cat /proc/mounts | grep "^$TARGET" | grep noexec)" ]; then
   echo "El disco $TARGET esta montado con el parametro noexec, intentando remontar..."
   mount -o remount,exec "$TARGET"
   sleep 3
fi

MBR=$(echo "$TARGET" | sed -r "s/[0-9]+\$//g")
NUM=${TARGET:${#MBR}}
TMP="/tmp/$$"
mkdir -p "$TMP"
cd "$MYMNT"
cp -f $EXECUTABLES/$LILOLOADER "$TMP"
cp -f $EXECUTABLES/$SYSLINUXLOADER "$TMP"
chmod +x "$TMP"/*

clear
echo $VERDE
echo '                                                  
__        _____ _____ ___ ____  _        _   __  __
\ \      / |_ _|  ___|_ _/ ___|| |      / \  \ \/ /
 \ \ /\ / / | || |_   | |\___ \| |     / _ \  \  / 
  \ V  V /  | ||  _|  | | ___) | |___ / ___ \ /  \ 
   \_/\_/  |___|_|   |___|____/|_____/_/   \_/_/\_\'
echo 
echo "          $ROSA <<< $AMARILLO Bootloader Installer $ROSA >>>"
echo $CIERRE                                                  
echo "Este instalador hara $TARGET booteable para Wifislax."
if [ "$MBR" != "$TARGET" ]; then
   echo $AMARILLO
   echo "Alerta!"
   echo $CIERRE
   echo "El master boot record (MBR) de ${VERDE}$MBR${CIERRE} sera sobreescrito."
   echo "Solo Wifislax sera booteable en este dispositivo."
fi
echo
echo "Presiona ${CYAN}ENTER${CIERRE} para continuar, o ${ROJO}Ctrl+C${CIERRE} para salir..."
read junk
clear

echo "Flushing filesystem buffers, this may take a while..."
sync

# setup MBR if the device is not in superfloppy format
if [ "$MBR" != "$TARGET" ]; then
   echo "Instalando ${CYAN}MBR${CIERRE} en ${VERDE}$MBR${CIERRE}..."
   "$TMP"/$LILOLOADER -S /dev/null -M $MBR ext # this must be here to support -A for extended partitions
   echo "Activando particion ${VERDE}$TARGET${CIERRE}..."
   "$TMP"/$LILOLOADER -S /dev/null -A $MBR $NUM
   echo "Actualizando ${CYAN}MBR${CIERRE} en ${VERDE}$MBR${CIERRE}..." # this must be here because LILO mbr is bad. mbr.bin is from syslinux
   cat $EXECUTABLES/mbr.bin > $MBR
fi

echo "Instalado ${CYAN}MBR${CIERRE} en ${VERDE}$TARGET${CIERRE}..."
chmod +t /tmp
"$TMP"/$SYSLINUXLOADER -i -s -f -d boot/syslinux $TARGET
rm -rf "$TMP" 2>/dev/null
rm -rf $EXECUTABLES 2>/dev/null
echo "El disco ${VERDE}$TARGET${CIERRE} es booteable ahora. Instalacion terminada."
echo
echo "Presiona ${AMARILLO}ENTER${CIERRE} para salir..."
read junk                                                                                                                                                ./.wifislax_bootloader_installer/lilo64.com                                                         0000644 0000000 0000000 00000524220 12706232442 017724  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ELF          >    p=@     @       ��         @ 8 	 @         @       @ @     @ @     �      �                   8      8@     8@                                          @       @     �	     �	                        b     b     ��      h�                    @     @b     @b     �      �                   T      T@     T@                            P�td   <�     <�A     <�A                        Q�td                                                  R�td        b     b     �      �             /lib64/ld-linux-x86-64.so.2          GNU                   a   c      I   %   _       3           C              Y              @          ]       1       Z          	   b   \       B   !   0       N   >       .   X   S       K      8           ;   A                 T   D   J       4   U   =           6       M       Q   a       L   $      ^      [   :   ?       7           R   H           W                   `   E                  G                                                                                                                                                                                           '                      (   
      *           /   )                   5                 <                       "   ,                      O   F   -       V               P   2   #   &      9   +                           �                     g                     3                     _                     6                     �                     �                     N                      X                     P                     �                      J                     0                     &                       �    ��b                                 �                                           w    Рb            �                     $                     B                                           Q                     �                     �                     �                      �                     ,                                          8                     �                                                               |                                          `                      �                     G                     �                     }                     �                                          $                     �                     �                     �                                          �                     +                     �                     s                       �                     A                     V                     �                     �                     E                                          �     0 @                                   �                     �                      �                     �                     M                     n                     �                     �    ��@     �       g                     �                      �                     '                     +                     �                     *                     @                     �                       �                     *                                          o                     8                     �                     �                     /                     �                                          @                     �                     �                       �                     	                     �                     %                                           Y                     u    �b             libdevmapper.so.1.02 dm_task_destroy _ITM_deregisterTMCloneTable dm_task_run dm_task_set_major dm_get_next_target __gmon_start__ dm_task_set_minor _Jv_RegisterClasses dm_task_get_driver_version dm_task_create _ITM_registerTMCloneTable libc.so.6 chroot fflush strcpy readdir sprintf _IO_putc srand fopen strncmp strrchr perror closedir strncpy unlink putchar realloc fstatfs stdin memchr strspn strdup strtol feof fdatasync fgets ungetc getchar warn strstr __errno_location fseek chdir read memcmp ctime stdout fputc fputs lseek fclose strtoul malloc getpass strcat strcasecmp realpath remove opendir __ctype_b_loc getenv sscanf stderr ioctl readlink strncasecmp creat strtoull fileno rename atoi lseek64 strchr getline __ctype_toupper_loc memmove uname access _IO_getc strcmp strerror __libc_start_main write vfprintf free __cxa_atexit __xstat __fxstat __xmknod Base GLIBC_2.2.5 GLIBC_2.3                                                                                                                     ��    _        �          ui	   d     ii   p      �b                   �b        4           �b        N           �b        [           ��b                   Рb                   �b        b           b                    b                   (b                   0b                   8b                   @b                   Hb                   Pb                   Xb        	           `b        
           hb                   pb                   xb                   �b                   �b                   �b                   �b                   �b                   �b                   �b                   �b                   �b                   �b                   �b                   �b                   �b                   �b                   �b                   �b                     b        !           b        "           b        #           b        $            b        %           (b        &           0b        '           8b        (           @b        )           Hb        *           Pb        +           Xb        ,           `b        -           hb        .           pb        /           xb        0           �b        1           �b        2           �b        3           �b        5           �b        6           �b        7           �b        8           �b        9           �b        :           �b        ;           �b        <           �b        =           �b        >           �b        ?           �b        @           �b        A            b        B           b        C           b        D           b        F            b        G           (b        H           0b        I           8b        J           @b        K           Hb        L           Pb        M           Xb        O           `b        P           hb        Q           pb        R           xb        S           �b        T           �b        U           �b        V           �b        W           �b        X           �b        Y           �b        Z           �b        \           �b        ]           �b        ^           �b        _           �b        `           �b        a           H��H�]�! H��t��  �"  �3 H���            �5R�! �%T�! @ �%R�! h    ������%J�! h   ������%B�! h   ������%:�! h   �����%2�! h   �����%*�! h   �����%"�! h   �����%�! h   �p����%�! h   �`����%
�! h	   �P����%�! h
   �@����%��! h   �0����%��! h   � ����%��! h   �����%��! h   � ����%��! h   ������%��! h   ������%��! h   ������%��! h   ������%��! h   �����%��! h   �����%��! h   �����%��! h   �����%��! h   �p����%��! h   �`����%��! h   �P����%��! h   �@����%z�! h   �0����%r�! h   � ����%j�! h   �����%b�! h   � ����%Z�! h   ������%R�! h    ������%J�! h!   ������%B�! h"   ������%:�! h#   �����%2�! h$   �����%*�! h%   �����%"�! h&   �����%�! h'   �p����%�! h(   �`����%
�! h)   �P����%�! h*   �@����%��! h+   �0����%��! h,   � ����%��! h-   �����%��! h.   � ����%��! h/   ������%��! h0   ������%��! h1   ������%��! h2   ������%��! h3   �����%��! h4   �����%��! h5   �����%��! h6   �����%��! h7   �p����%��! h8   �`����%��! h9   �P����%��! h:   �@����%z�! h;   �0����%r�! h<   � ����%j�! h=   �����%b�! h>   � ����%Z�! h?   ������%R�! h@   ������%J�! hA   ������%B�! hB   ������%:�! hC   �����%2�! hD   �����%*�! hE   �����%"�! hF   �����%�! hG   �p����%�! hH   �`����%
�! hI   �P����%�! hJ   �@����%��! hK   �0����%��! hL   � ����%��! hM   �����%��! hN   � ����%��! hO   ������%��! hP   ������%��! hQ   ������%��! hR   ������%��! hS   �����%��! hT   �����%��! hU   �����%��! hV   �����%��! hW   �p����%��! hX   �`����%��! hY   �P����%��! f�        ��t��t ��tP��1����A �<�  �v�A ød�A ø��A �AWAVI��AUATD�o�US�0 @ H��x  H�~" H�Ѿ" VA H��"     ���"     ���"     ���" ����H���" H�H�D$8��, ����VA u�6,A ��, ��t��VA 1�蛙  ��!b E1�E1����  �D$4    �D$0    �D$H    �D$,    �D$(    H�D$@    H�D$    H�D$    H�D$    H�D$     E����	  I�WI�_�:-��	  �J��VA H�T$XA�m��ΈL$O�L$P�q���H���L$PH�T$Xt%�z tL�z�AA����I�_M���	  D���(�ο�VA H�T$P�-���H��tH�T$P�z �V	  E1��D$O��A<9�D	  ���$ŸeA L�|$�j  ���(  H�C�8-�  H����H�D$@�  1�L���'`A �  1�L���R�A �  1�1Ҿ�VA ��!b ���  ��"    �  L�=�" ��  1�L����VA �M  1�L����A �>  ���"    L�=|" ��  1�L���6tA �  ���"    �  �e�" �  �r�"    �  1�L����VA ��   ��L�=}�" H�D$ W�A �e  H�C�8-H�D$ �&  H�����H  ��" �<  ���" �0  1�L���VA �   ����  H�C�8-��  H����H�D$@��  ���"    ��  �=   L���i���H��I��t!L�h�  1�L����!b L��M���~�  �  ��VA L���������u1�1Ҿ�VA ��!b �U�  �  ��VA L���������u1�1Ҿ�VA �վ:A L��������u�4�"    �R  1�1�L�����"    �:  L�+A�} tI�����>���  L�kH���,M��u01�L��H��������  I���  L��L�����������u���  1�L��H����L�kL�{H��H��H���L��L���L��H��H���螗  �.�A H��I�������1�L���WA �����1�L���WA ������o�"    �m  �D$H   H�;� tH�GH�D$�F  ���9  H�C�8-H�D$�'  H�����!  H��x tL�x���tH�S���0<	wH����I���M��t
L����  ���" ��y�܃"    ����҃" �=˃"  ��   H��x" H���" �   1�1ҾWA ��!b �`�  H��f�"    �x+��   �R�" �����{1�L���WA ������  ��  �I�" �Z1�L���%WA �����D$(   �AL�|$�:M���D$0   �-H�D$ W�A �"M���D$4   �A�@tA �L�|$�D$,   I��A���������$�   �� �  �� �  ��  �ZA ��!b �Y�  ��u�Fw  �=��"  ��  �=��"  tH��w" H�o�" ��VA ��!b ��  ��UA ��!b �x�" ��  ��UA ��!b �����  ��!b �VA �N�" ���  �C�" ��" �ZA �ȃ�������=�"  �s  �" �" u�fZA 1���  �Ձ"    �=�"  t�ZA 1��ԓ  H�=�" H��t
H�t$ ��  �|$, ��  M����  ��!b �VA ��  H����UA t��!b �VA ��  H��L���#*  1���  ��$�  1�    �� @��u���Ã�9Y�" ��	  ;-)�" ��	  �=L�"  ��
  �'`A ��!b �-�  H��$p  H��萲  ��$p  <���	  ��$|  H�|$hA��  �
   �@�  H�D$h�J�����\A H��1��{�����\A �������$�   ��\A i��  �Ɵ  ��A��������љ���ʉ�1��=�����$�   f����y	  �	]A ������$�   �VA �L�A �J]A HD�1��������$�   �$VA �@tA �a]A HD�1��������$�  ��]A u��]A �$�����$�  �(VA �@tA H�޿�]A HD�1�������$�  �H���]A HD�1�������$�   �!^A HE�1�H���i�����$�  �-VA �Z^A HE�1��L�����$�  @�7VA �2VA �q^A HD�1��*�����$�   @����  ��^A �o���f��$�    ��  ��^A �V���f��$p  ����  �R_A �<����==" ~��$�  ��_A 1��������_A ����H��$r  H��$p  L��$v  E1�H�D$�; ��  A��H��6A��u�D���������$l  H��$p  �����  迓  9��'���H�=�s" �V���H�5w�" �idA �����   ����H�|$ uZ�4WA ����H��H�D$uF��NA �" ����WA �����H�|$ �D$(�L$4��D$0��������   H�|$8�I  H�D$�8 t���UA �9WA ����H�|$H��}" �������y�V����8�O���H�t$H�¿JWA �-  ��~A �C�����yH�t$�XWA 1�誏  ��A �$������=��������8� ����yWA H��1�諎  �|$0 tH�t$@L����  �=~}"  �|$( ��   1��@tA �   �   ��WA ������=K}"  t��WA �;������WA ��WA 1�������|$( t�="}"  ��  ��WA �
����}" ��~;��t7H��$p  ������u&H��$p  H��$t  �LYA H���   H��1��e����
   ������|$( t�=�|" �L  �Q  �B  �=�|"  ~H��q" H�^�" �6�  �G|" �hYA �P��������1�H�|$ t*H�|$��YA ������tH�|$��YA 1�������@�Ń=�{"  tH�=oq" � ��t��t
H�|$�  �|$4 tH�t$@L���1�  H�=�" E1��o�  ��A��x��!b �2�  A�ľWA ��!b �_�  �=�{"  �    H�{" ��{" ��~���y{"     ~D�濤YA 1��,�����u��t
H�|$�  H��$�   D���� ���t��������8����H�5?�" H�¿�YA �  ��$�    tH�5!�" ��YA ��tH�5�" ��YA 1����  1���$�   $����" �(����ZA ��!b ���  H��t�ZA ��!b ���  H�����  ��z" �=�z"  ������z"     � �����u%�۾�UA u�Ҿ�UA �VA HD�RZA 1��q�  �Kz" �Mz"     �gz"     ��u�4z"    ���u�Gz"    1��#���1����������WA ��!b �'�  H��H�D$H��u�'`A ��!b ��  �T$HH��H�����  �2����%WA ��!b ���  H��H��t8�0��[A �e���H��t
��y"    �3��[A �I���H��t
�jy"    �=cy"  u� �=�y"  t<�=�y"  u	�=[y"  t*�=�y" ~!�=Iy"  �VA �LZA ��[A HD�1��C�  �6tA ��!b �F�  H����/  �y" ����  �VA ��!b ��UA ��  H��t�VA ��!b ��  H��H��$�   1�H���N  H��$p  �   ��A���N���H=   t�1����8�*���H��H�¿�[A �
  H��$p  �   D������H=   t������8�����H��H�¿�[A ��   �   �   D���O���H��������8����H��H�¿�[A �   H��$�   �    D������H�� t�����8����H��H�¿\A �j�   H�� ���D�������H���\����8�U���H��H�¿+\A �8H��$p  �   D���C���H=   �C����"����8����H��H�¿A\A 1��È  �۾�UA u�ҾVA �VA HD�V\A 1��$����zw" �-Pw" �(���<�u��$q  ���<�\A �������$q  ��H��$p  �   )�Hc�H�H��Hc��Z�����$p  ���\A ���������i��  �#]A �Ɵ  ��A��������љ���ʉ�1������`�����^A 1��u����a����R�A ��!b ��  H����$�   u�_A �J����O�����'_A 1����4����9���H��$r  �q_A 1������:���f��$p  ���P���H��$r  �s_A 1�������7���f�S2�@tA A���A A���A ���A �-�A ��_A ��@LDȀ�H��LD�E��HEȃ=v"  HN�1������= v" ~h�s/�S0�K.D�C-@��@��`tB1�@��`u�C1����_A ¸�UA ��ѺVA ��D�@�� HDЁ�   1��<������_A 1��.����
   ������=�u"  �����f�k2f�� t
��_A �b���f�� t
�`A �Q���f��y
�,`A �B���@�ŀu�L`A �2����@���SVA �@VA HD�\`A 1�����@���fVA �2VA HD�}`A 1�����f�� �lVA �=�A HD�`A 1�A���r���fA����   @����`A t*1���`A �P����s4f���twf���u�aA ���`A �������`A ���aA 1�����f�� �aA t�.aA �`����s$��u�JaA �O�����baA 1������@�� t
��aA �1���Mc�Mk�6B���  B���  B���  B���  H��H��H��H��H	�H��$�   H	�H��H��B���  H	�H�� H	���P  ����aA �  H�t$t�   D������H��t
��aA �����t$x�D$tH��$�   H�� H	��P  ����aA t8H��$p  �   D�������H=   t
�bA �����f��$p  ��t�CbA �9����H��$r  �SbA 1�������T$z�|$y�D${�t$|H��H��H��H��H	�H��$�   H	�H��H���t$}H	�H�� H	���O  ���gbA tLH��$p  �   D���*���H=   t
��bA � �����$p   tH��$p  ��bA 1��*����
��bA �~���fE���������$�   ��$�   ��$�   ��$�   H��H��H��H��H	�H��$�   H	�H��H����$�   H	�H�� H	��0O  ���Q  H��$p  �   D���m���H=   t
��bA �c���H�|$�   �cA ������u(��$x  ��$w  �cA ��$v  D��$y  �>�   �cA L���i�����t2��$x  ��$w  �;cA ��$v  D��$y  1������v���D��$�  H��$p  I�I�o2A�7@��tOA�W��tF���u/@���u)A�w@���u�lcA �������cA 1�����I��뺿�cA 1�I��������u @��������U�M�dA D�E1�H���¾  �c����οPdA �����������  �=�p" A��~�k�" �ƿydA 1��-����p  �=�p" ~�=\�"  t�5hp" ��dA 1������]A ��!b A����O�  H��t�]A ��!b �;�  H��藃  A�ž�VA ��!b �!�  H��t��VA ��!b ��  H���i�  �þ�VA ��!b ��UA ���  �VA ��!b I�����  H��t�VA ��!b ���  H�ž'`A ��!b ��  E��E���L��H��H���8�  E��t$��+b ��  ��+b ���  ��t��dA 1��b�  ��  ����dA �������dA ������ڮ  �&�  �r�  ��  �=Jo" ~�No  �=�"  t�  �x�=(o"  uM�=#o"  t
�eA �����WA ��!b ���  H��t	1Ҿ   ��WA ��!b ���  1�1�H��路  �"�w�  �=�n"  t
�&eA �����TeA �����=�n" ~�n  �5cn" ��t@��~��eA 1��*������eA 1������=Qn"  �zVA �qVA ��eA HD�1������H��x  1�[]A\A]A^A_��    1�I��^H��H���PTI���OA H��`OA H�Ǡ"@ �����fD  H�=c" H�c" UH)�H��H��vH��! H��t	]��fD  ]�@ f.�     H�=�b" H�5�b" UH)�H��H��H��H��?H�H��tH���! H��t]��f�     ]�@ f.�     �=�b"  ubUH���! H��b" H��ATSH���! L�%��! H)�H��H��H9�s@ H��H�ub" A��H�jb" H9�r�����[A\]�Mb" �� H�=��! H�? u�.���fD  H�1�! H��t�UH����]����S�/   H������H�PH��H�=��" ��PA HE�1�H������H�=��" H�ٺ@tA ��PA 1�����H�=g�" �@tA �,QA 1��n���H�=O�" �@tA �hQA 1��V���H�=7�" �@tA ��QA 1��>���H�=�" H�ٺ@tA ��QA 1��#���H�=�" H�ٺ@tA �RA 1�����H�=�" H�ٺ@tA �MRA 1������H�=Ρ" H�ٺ@tA ��RA 1������H�=��" H�ٺ@tA ��RA 1�����H�=��" H�ٺ@tA ��RA 1�����H�=}�" H�ٺ@tA �6SA 1�����H�=b�" H�ٺ@tA �`SA 1��f���H�=G�" H�ٺ@tA ��SA 1��K����   ����P�=Qk" �>  �5-^" ������b �3�  ��t9�^" ���b ����p���  �п�SA ����f��������	�1������5�A" ������b ��  ��t9��A" ���b ����p���  �п�SA ����f��������	�1��?����5I" ����d^b �  ��t9�0" �d^b ����p��s  �п�SA ����f��������	�1�������5��! ����D8b �=  ��t9���! �D8b ����p��!  �п�SA ����f��������	�1������5%�! �����-b ��~  ��t9��! ��-b ����p���~  �п�SA ����f��������	�1��I����5�! ����$6b �~  ��t9���! �$6b ����p��}~  �п�SA ����f��������	�1�������5��! ����4b �G~  ��t9���! �4b ����p��+~  �п�SA ����f��������	�1�������SA ������UA 1������UA ������   �   �)UA 1��o����   �   �   �?UA 1��T�������gUA 1��E���jj�   jj�   ��UA A�   A�   �   1������   �6   ��UA 1�H��(�����SHc�H����!  ��u�޿�gA �Zy  ��!�������!�[�Hc�H��H��H����H��H�� ���  �� ���	ʃ�t!S���!  ��!Ѕ�u�޿�gA 1���x  [�SHc�H���o!  ��u�޿�gA ��x  ��!؃�����[�AWAV�'`A AUAT��!b US��A H��  菺  H��H��$�   HE�H��H��\" �� ��yH�޿�gA ��   �=cg" ~��$�   ��$�   �hA 1������H��$�   H��H�� H��% ������  	Ѓ�	t$��!b �WA �	�  1�H���7hA �\
  �  �=�f"  uH�6\" �8/u�x u�jhA 1��x  �6g  ��$�   H��$@  �   �V  ��A��yH�5�[" ��hA 1��w  H��$�  �y  H��$�   D��H��H��[" ��
 ���)  ��$�   % �  = `  t
H�޿�hA �H��$�   H�T$�	�D����" 1��)�����yH�޿�hA �z����=f" ~�T$�t$��hA 1������|$ t�iA 1��w  �|$Y�+iA v�H�T$h1��	H�D���������yH�5[" �RiA �����=�e" ~�T$l�t$h�piA 1��6����T$D�D$h��u �|$ZuE��u�|$lZ�A��u�|$l tD�L$l�L$��iA H�5�Z" 1��gv  �|$x��iA �N����=2e"  u(�=e"  u�= e"  ��d"    u�jA 1���v  �WA ��!b ���  H��H�ú   tW�;�A H���3������   tA�;jA H���������   t+�@jA H���������   t�IjA H���������҃����" ��$�   1��d�"    �nd"    �T�" �   �2�"     ������Y"     0���	��Y"     ��	�H�H^" �[" H��]" H���-  ;tH�R����tH��]" �=d" ~<P��$�   �MjA PD��$�   1�D��$�   ��$�   ��$�   ��$�   �h���ZY��$�   ;�$�   v%�=�c"  ��jA �����1���jA �u  ��$�   �D$�ۚ"     E1�E1��$   E1�1�;l$��  H�T$1��	�D��l$�O�����y�����8������H�ƿ%kA �$  �T$ �D$$���  �щ���0�����	�	=c" ��Y" ~��FkA 1������5�Y" ��u�fkA 1��7X" ��t  �!  H��$�  �   ��R  �D$,tH��$�  ��kA 1��D�����W" ��  �5sY" H�|$0����   �+  �    �Cu  �=xb" H��[" ~�AY" �t$0��kA 1������H��[" �D$0�= Y" �B�D$<�:�B�D$4�B�D$8�B�D$@�BHc�" ��u�v[" �-`�" +j[" �<� �b ������b t
�ʗ"    �<$ t;������t2E��Hc��" tD94���b ����!$�H�A�   D�4���b I�ċT$0;��" Hcd�" }�t�" �[" �=�a" ����b H��Z" H�z[" H�s[" H�Q~!�=:�"  t����b �q��kA 1��������H��$�  H��$�  ��  H��H�L$����H�L$1�Ƅ$�   H���jE  H��uH��$�  �t  Hc��" ��H��H�͠�b u#H�LZ" �L$<�H�L$4�H�L$8�H�L$@�H���" ���8���H��$@  ��R  Hce�" D�<$����b     �� �b     t�=V�" u�J�"    �Lc%�Y" ��U"     1�E1�D;-�" ��   ���" �P���w����b     �P��uK� �" ��u����b     �.��u/�� �b ����������b t������b ��� ����b �/U" �=8�" tG�=��" t�=��" u5��� �b �������t恍��b    �D9���b u�� �b �/�����u�A��H���-����=ܖ" ��T"     ��   �=Ŗ" ��  ��  H��$�   ��� ��yH�޿�hA ������$�   % �  = `  ��   ��$�   H�޿(lA 1��p  ������t����b    HcJT" ���" 9� �b �.  Hc-0T" H��L��E�!T" ��q  H��b H���G����; �>����=���H� H��DP tH����,   H������H��I��t�  I��1��   H��������������H�������=O^" ~��$�   H�޿ElA 1��������E1��5���Hc~S" ��" �� �b D;5ړ" Ic�������$�   �����B�<� �b A��I������A9�u�Hc6S" H��$�   �,� �b Hc� �b H9������H�޿elA �����=~]"  �������$�   H�޿�lA 1��&��������=^�" u�i]" H��V" �x y	�F�" �P�p�F��57�" ��v��lA 1��Xn  �=?]"  t��lA 1�������=�\" u!���" ����vH�5[R" �#mA 1���n  B����b �V��tH�^V"     �    �o  ��$�   H�FV" �@��������0ɀ�	��	ʉH��V" H��V" H�P����H�Ę  ��[]A\A]A^A_�AWAVAUATUSR�=9\" E�1�A���A���=i\"  u/�WA ��!b A�   �L�  H��H��u�WA ��!b �5�  H��E1�=2\" 1�A����=��" �  ��   ��" �nA ��t���nA t���nA �7�A HE�0nA 1�1��w���9��" ~�H�ݠ�b �4���b �CnA 1�H���Q����؅�tl�=�["  u'�4���b H�<ݠ�b E��E��E��D��ED�H���ߤ  �=x["  H�4ݠ�b �@tA �#nA �{nA HD�1�H�������;�" A��|��W  �=<["  t��؟  �=�Z"  t
�&eA �����VnA �����d����% [" ��=["  t$衟  �=�Z"  t
�&eA �������nA ������H�=$P" A�����E1�D��H��1��"�  �=�Z"  H�5 P" �@tA �#nA ��nA HD�1��6������" ����  ��u1ۃ=�O"  u�  1ۃ�A�@tA ��   A�@tA ��   Hc� �b �<���b  I��u�2Z" Lc5�S" �=4Z" ~Ic�H�4ݠ�b �oA ����b 1������=	Z"  u$B�4���b H�<ݠ�b E��A�   D��H���C�  �=�Y"  H�4ݠ�b �#nA ��nA ID�1�H���X����%�Y" �9O" �O����   ����b ��tH��9[�" ��   <�L�4ݠ�b u	�=ِ" uM�=lY"  u�4���b E��A�   D��H��L��謢  �=EY"  H�4ݠ�b �#nA �{nA ID�1������뎾WA ��!b ��  �*nA H���-nA HD�M��L��L��/oA 1���j  �T���X[]A\A]A^A_�AUATUSH��H���" ��~�   �0pA 1���i  1�I���   H��I��1��   1�9�~$����b D����b ��H����Hc���D��	���1�H��t:��sA��I��A�E��=7�"  t�=RX" ~A�4��PpA 1��������H�����=2X" ~��npA 1�����H��H��[]A\A]�AUATI��USHc�RD�%�Q" ���   D���������y��pA ��   �@tA D��H�������H��t
��pA �h  �=�Q" � �������pA u�L���`�b �/  ��u
��pA �h  �=lQ" �Ӻ   Hc��U���H��x�X[]A\A]�AWAV1�AUATH���USH��H��H��(  ��pA H��H��H���  �R  1�I��H�߾   �o�����A��y�s����8�l���H��H�¿�A �*1Ҿ   �������H��y�G����8�@���H��H�¿ qA 1���g  H�t$ �   D��M���)���H=   t�����8����H��H�¿qA ��A�< uI�����M��t]A���tI�����tA� �E1�H��$  H�l$ H�D$L��H��������tH��6H;l$u�L���RqA 1��Kg  M��tA� 1�1�D�������H���'���A�} H�t$�   D�����f%��f�D$������x:��t�&qA 1���f  I���1�L��@��L��L���D��H��H���������H��y�����8����H��H�¿qA �����L��L��@���Hc�H��H9�u�D��������y������8�����H��H�¿EqA ����H��(  []A\A]A^A_�ATU��  SH��H��  �=�����y�����8�}���H��H�¿kqA ��   L��$�   ������1���   L���   H�޿`�b fǄ$�   mk��)  �=��"  �yN" ��N" �!�" tP��H���!�  ���xqA u9�=�T" ~�$�5�" ��qA 1��*���Hcߋ" H;$t�=ދ" t	��qA 1��i�   �=HN" �   L���s���H=   t�����8����H��H�¿qA 1��Ge  ��fǄ$�     u����b �   �`�b �	,  ��u
��qA �e  H�Đ  []A\�AVAUI��ATU���SI����  H��H��   ��h  ��M" 1��   ���  ������1҉߾   I������H����pA x#H��ߺ   ����1�H=   �   t��pA �ed  ��I����   ��tL���`�b �K+  ��u܉޿rA �Wd  1�L��`�b �,+  ��u
�7rA �:d  �=!S" ~'�=�L" H���y�  ����qA x��t$0�erA 1������=�L" 1�L�������I9ſrA �`���H�Đ   []A\A]A^�H��tYATD�%�L" 1�USH��H��D������H9�t��rA 1��c  �    H��D������H�� t��rA 1��c  [�`�b ]A\��`�b �?*  SH���   �e  ���SH�@    �PH�+L" H��tH�B�H�!L" H�L" [�ATU1�SI���   H���-�K" �����������pA x�   L���H�������H=   t
��pA ��b  H�T$�޿`�b �)  ��u
��rA ��b  H�|$�I���H��[]A\�H��K"     H��K"     �AUATA��USI����1�H��9�}KA�t H�T$L����	�T)  ��tH�|$������!���b ������==Q" ~�޿�rA 1������H���H��[]A\A]ÿ��b ����AWAV1�AUAT��   USH��(  �=�P"  H�\$ H�|$H�����  �=�P" H�-�J" E�A��A��H��t9�~H�m����E1�A�  1�E1�H��u3�=�P" �;  A���@tA �oVA HD�D����rA 1������  H�}H��t�D�E�GD��1�1ҁ�   ��uOA�� tIA��@u�w1�D9���u5���G�G�)�@D�}�R  �WA9��E  ���G�G�6  ��tj�E`t9�E�u �����E��	�	��u��G�����G��	��	�9��%�u �1ҁ� � �% � �9�u�U �E��9�����A��   ��t��D������9�u�UD9����  D��H������L�=LI" M��u�!sA 1��U`  E1�E1�1�A�   �=.O" I�GH�D$��   A�GA�w�3sA A�OA���`<`DD�1������=�N"  u	�=�N"  tAA�WA�G��UA �ZsA ����	�A�	�D����	=�N"  ��rA HE�1��=����
   �ӿ��E��tH�t$1��u���Hc�H�F
H=   v@H޿   �Y����=HH" �   H���s���H=   t
��pA �9_  ��   1�H���1�A�HcŹ   H؉A�W�PA�G�U�Ճ�`<`tA�OL���T$A��(���L�|$E1��T$M���������tV�=�G" �   H������H=   t;�t���1��1������L$A�ƈEH�GH�D$�ξ��H�D$H��L$H�E�.���H��(  D��[]A\A]A^A_�AWAV�F�AUATI��USA��M��M��1�H��H�=NG" �D$H������   �D$1���@��H�o)�9�~�bsA 1��7^  E��tqD�GA��`u��81�A�� tA��@t	�G��F" �|F" �w��	��w��	��7��	�A��u	A�I���/D��A��pA�E��E�EI��A�u���I��A�D$��GA�D$��T$H��踽��H��T$�2�����t,A��u	A�    �E��t�   1�L���
�   1�L���H����[]A\A]A^A_�AUATI��US�Չ�H��  �=(L"  ~
�zsA ����A�|$Hc�1�H��	����H����sA x=�=�E" �   1�E1��¾��H���A��A9�}YA�|$�   H���3�����y
��sA �\  =�  Hcй   H�)�1�H���=|E" �   H��觽�������sA �����  t��sA 1��\  H�ع   �`�b H�H����������H��  H��[]A\A]�AVAUATUI��S��H��   �=)K"  ~
��sA �����=�D" �   1�E1�I���ݽ��H�Ņ�tU�   ��   L���L��N�A��Hc�)Ӂ�   �I��t	)�Hc�1��=�D" �   L���ϼ������tA �[  ���  t��sA 1��[  H��   �`�b H�H��D��������H��   H��[]A\A]A^�ATUSH���   �=ı! u�=��! @���! ��   ���!    ���! @   1ۉ�H�|$�������   �
:  ��tzH��$�   1��   �A�����A��xUH�t$�   ��1��G���H��uH�T$�  D��1�込���Љ���D��迼����tH�|$����;  ��t�t���H�|$��;  ���! ��H���   []A\�AWAV��UA AUATI��USH���  H��t&�ľ��H��I��u/觺���8蠿��L��H�¿�A �D�1tA 虾��H��I���   L�5&C" H��$�   �z����   M��1tA H��IE��WtA 1��Z  �
   H���k���H��t�  �#   H���V���H��t�  I���H��>tA �ݻ��L��H��H��1��H��H��L�H9�uL��   H���2���H��u��v�    �=[  H��H�HH�@L�KL�CH��PH�C�AtA H��P1��6�����ZY�/���D�{H�@B" M��H�6B" H�Ct�ptA 1��.Y  �B"    �s���L���=�����UA ��tA �9~"     �T���H��H���?  H��$�   H�ھ   �s���H��uH��������  H��$�   �   ��tA Ƅ$�   �b�����u�H��$�   H�ھ   �)���H��ttH�L$(H�T$H��$�   1���tA �F�����u�H�|$(�UA ������u�Hc�}" �=8G" �t$�4���b ~��tA 1�跹���a}" �����V}" �r���H���8���H�t$H��tA �I�  ��uL�	   苸��H��H��t:H���������t.H�t$�    H���5�����tH�|$臼��H�߉�@" �)���H���  []A\A]A^A_Ë�|" 1�9�~H��9<���b u�   �1��H��H�� H���� ������  	����  vQ��  1���tA �X  1�Z�Hc���@b ����E��ATU�    SH��   ��X  H�5@" H�ǹ   ��qA ��b �@����H���ژ  H��H��H���.�  ��y�%����8����H��H�¿QuA 1���V  �D$% �  = `  tH���tA �   H��?" H�|$(D� I1�����H�L��u�H�D$(� b ��ܕ  � b 謖  �uA � b �E�  ���H��t
H���aX  �SH�;?" H���H�@H��t�9u�H��#uA 1��"V  H�S��b H�?" �o�  H�Đ   []A\�AWAV�]aA AUAT��!b USH��   �ŗ  ��b H���6�  ��b ��  H�t$H����  ��y5���A ��b �%�  ����  �����8�ܺ��H��H�¿HuA 1��U  �D$(% �  = `  tH��]uA ��   H�|$8�������tH�|$8H��@��H��0�	�������Ѕ�uƿ    ��V  I��H�D$8�~uA ��b H��A�$H�� H��% ������  	���  ��uA ��b I���ϖ  ��uA ��b I��轖  ��uA ��b I��論  ��uA ��b H�D$藖  H��tt���  w[H��Hc��V  ��@b ��t9�tH�uA 1��}T  ��@b �����t3��߃�t)=�   t"��H���uA 1��KT  ��  �
vA 1��:T  ���M��tL���:V  M��A�D$��M������t��tA�D$����A�D$�����%��t�JvA �cL����U  L��A�D$��U  A�D$���A ��b �D�  ��t=M��A�D$    �rvA u#M����M�����uH�|$ uA����!��vA 1��S  H�|$ t�H�|$�U  A��H�b<" E�D$A�D$    H��H��t�
A9$uH���vA ����H�R���="B" I�D$L�%<" ~&A�L$PH��A�D$��vA PA�$1�E�L$舴��ZY��b �X�  ��b �(�  �]aA ��!b 貒  H�Ĩ   []A\A]A^A_�USH��H���   H��;" H9G��   �=�! H�/dev/lvm�D$ H�D$���t耴���sH�|$1�1�诶�����ŉը! yH�t$�wA �!H�T$�Ǿ���1��4�����yH�t$�4wA 1��9R  �t$�VwA f��	v)�������sH�|$1���0  ���q�! H�sy�|wA 1���Q  H�5;" �=R�! 1�H�ھ0���ó����y���A �5�����wA �Q  H���   []�USH��H���   �GH;�:" ��   H�|$��xA �   �=�! ���t�t���H�|$1�1�覵�����ŉȧ! yH�t$��wA �!H�T$�Ǿ u�1��+�����yH�t$��wA 1��0Q  �t$��v��u�|$ u�L$�T$�#xA 1��Q  ��������sH�|$(1���/  ���K�! y�s�ZxA 1���P  �CH��9" �=*�! 1�H�ھ�u�蟲����y���A �����|xA �P  H���   []�AWAVA��AUATA��USH��H���   �=d?" ~��xA 1�����Mc�L��L��H��H�� ���  % ���	�uD���xA ��  A��  u�CyA 1��  E���Z  H�|$8�   D����.  ��WA����   ��H��  ��/w^��,��  ��w0���  ���v  w���y  �F  ����  �����!�/  ��"�F  ��$�=  �  ��9w��8�1  �%  ��<��  ��?�v  ��A�w  ��  ��wL��x�Z  ��ew��d�L  ��[��  ��]���p��  w��h�*  �  ��r�  �  ���   w���   �  �  ���   ��  w���   ��  �\  ���������9  �H  ��W�E   �E   �E   �E    �E ������   ��H��  ��/w^��,��  ��w0���  ���
  w���  ��  ���^  �����!��  ��"��   ��$��   �  ��9w��8��  �   ��<��  ��?�
  ��A�  �y  ��wH��x��  ��ew��d��  ��[vx��]���p�q  w��h��  �:  ��r��  �,  ���   w���   ��   �:  ���   ��   w���   �   ��  ����������   ��  A���I��A��A�� A	�1�A����t�����B�� �   E���E ��  H�T$1��  D����������X  �D$�E�D$
�E�D$	�  A���I���m���A�� A��A	�A��E��B�� �   �E �.  H�T$1��  D��蔮������   �D$	��yA ����  �  �>zA �k����pzA �a�����zA �W�����zA �M���D��{A 1��XL  A���I�������A�� A��A	�A��E��B�� �   �E ��  H�T$1��  D���������x\�D$	��{A ���  �xA���I���w���A�� A��A	�A��E��B�� �   �E �8  H�T$1��  D��螭����y������8����D��H�¿�yA 1��K  �D$	����   ��{A �K  A���HcÊ�@b ����   ����   <?�����<uwI�������A�� A��A	�A��E��B�� �   �E ��   H�T$1��  D����������Y����D$	�:{A ���w����T$�U�T$
�U�EH�D$�E�{<�����<�z����Că�v�C���v���   ��wD��"|A �G���D�|A �:���E��u1�={9" ~{��|A �g����o�D$ �E    �E�D$$�E�D$�EH�|$8�+  ��A��D�m �D��H�T$� ���D���E 1�������y��m����8�f���D��H�¿�yA �s���H���   []A\A]A^A_�AUATUS��QH��2" H��H��t9] ��  H�m��=�2"  u(H��Lc�H��tD�m L���7���!�A9��u  H�m��Hc�H��H����H��H�� ���  % ���	Ѓ�W��   ��ArH����@�� 	����)��$tDv=��7��   ��0��   H����@�� 	���u�����������  1��  ��uH����1�@�� 	�����   ��w*��uH����@�� 	���붃��i�����u��룃�t�s
�   �   ��!��v����-�^��9v���<��w��-�����p�O���w!��ew��d������[�f�����]�<��h� =�   w =�   ������r�����r���xr������=�   �����=�   �l��������} u�޿�|A 1��#H  �E����q���������Z[]A\A]�AWAVHc�AUATUSH��H��H��!  �5m" �T$H��H�� H��% ����L$���  	�1�9��}<�<���b H��9�u�L��$�  ;�l" }H��0" H����  ;X�2  H� ��=k6" ~�T$�޿�A 1�����Hc�H��H����H��H�� ���  % ���	ȃ�:umH��$�  H��$�  H��$�  Ǆ$�      Ǆ$�  �   �F���H��$�  �9�����$�  +�$�  ��A =�   t1���F  H��$�  H�]0Hc�H��H�� H��% ������  	Ѓ�uu9H��$�  ��$�  HǄ$�      Ǆ$�      �������$�  H��H�E0Hc�E1�H��H����H��H�� ���  % ���	ȃ�	��  H��D��H��$�   0Ҿ�A 1�A	�D���4���H��$�   1��   �P�����A��yDH��$�   D���A 1�����H��$�   1��   ������A��yH��$�   ��hA �"  H�T$X1��	�D��衧����yH��$�   ��hA ��   �|$X �iA ������|$\Y�+iA �����H��$�  1��	H�D���T�����yH��$�   �RiA �   �T$XD��$�  ��u&�|$\ZuE��u
��$�  Z�A��u
��$�   t D��$�  �L$\H��$�   ��iA 1��E  ��$�  ��A ����E1�9(k" �k" H��$�  �	�D�牄$�  A��1�褦����yH��$�   �%�A 1��D  ��$�  ��$�  D��Ё��  ��0�����	�	��o���Lc�L��������|$ �$��t�<$ t�3  H�E-" I��M����  A9tM�v��E1��A�   A�V��u�<$ t�޿�|A 1��D  A�F���tC��t?A�~�t8E��u31�A�~���   �  E�>L���[���!�A9�t�M�vM��u�A�   �|$ u$L��I�� H��A�� ���%�  A	�A���~  �T$��H��������|$ t
��H���ѷ  D�e 舷  A���|$��G  A9��>  M���&  A�~��  A�F�   ���t�E A�F���t�E��A�Ft���t�EA�F���t�EA�F���tE��u�E�|$�t�D$�E �|$ u#�=�1" ��  �U �޿_�A 1��O����  �M��t�} t�} u�UD�E�޿��A 1��B  ��   ~�   �޿��A �'u�   ��A 1��EC  �M��@~�@   �޿D�A 1��XB  u�@   �|�A 1��C  �=�0"  u+�M�E��ș�}���=�  ~�   �޿ЁA 1���B  �=�0" ~;�E�MA�   �U �޿<�A ���DE�1��j����M�U�@tA �w�A 1��S���E��D�m$u�} ���V-  �  �}f" �E �  H��$�   ������|   H��$�  H��$�  �   ����Ƅ$�   1��  L���H��$�  �   L���H�����I��y茡���8��t[耦��L��H�¿�|A �z��$�  /H��$�  t�/   跢��H�xH��H��$�  HD�H��$�  L��H)�H��   �j���H��$�  L���ڣ��H��u#�����8�	���H��$�  H�¿-}A 1��@  H��$�  �   L������E�������   Ƅ$�   ����H��H�$u
�[}A ����Lc�H�<$L��L��H��H�� % ������  	�訠����u
��}A �J���I��H�<$��A�� D	��#�����t�H�<$�&�����u
��}A �����   �A  I�ƉXH�@    H��(" H�D$    1�I�L�5�(" H�<$H�t$L�L$PL�D$HH�L$@H�T$8財��H�|$HH�D$H����  ��UA �E�����t
�~A �����(   �)A  I��H�D$8�=f(" L�|$PM�EI�EH�D$@I�EYL�D$�̤��I�H� L�D$�DPt<I�W�DPt0A�:u)I�W�DPtI�W�DPtH�L$0H�T$,�6~A �>L�D$�s���I�H� �DPt8�:   L���H���H��t&L�D$H�L$0H�T$,�w~A 1�L��腢�����  �    L���@���H��H�D$uL���D~A �����H�D$��~A L���  H�T$P1��m���H�t$XL����  ��u^�D$p% �  = `  tL�濉~A ����H��$�   H��H����H��H�� ���  �� ���	ʉT$,H����H��0�	ЉD$0��   H�T$P��~A L��1�������UA L���-���H��I��uL���~A ����H�¾   L���H���H��uH�t$P� A �����H�L$0H�T$,1��3A L���[�����t^H�T$41��9A L���B�����tL��<A ����HcD$4H��H��H���҉�H��H��H�� ���  0��� ���	�	�D$0�L$,L���@���H�D$I�U�}~A H�x�  1��Ԡ����tH�t$P�D~A �>����D$,I�V��D$0��I�U A�E D�M�nH�|$ �����H�<$�,���H��$�   ��  ��u
�jA ����HcË5�a" H��H�E0H�� H��% ������  	�1�9��������<���b H��9�u�����H�@1�H��t��X H� ��=+%"  uI���c���E1��f����u �7�A 1���<  M�����������H�Ĩ!  []A\A]A^A_�AVAUA��ATUH��S�:   H��H��A���H��   �y���H��t"I���  H��A 1��<  I�|$�=  A��1�D��H���՟�����Cy�ٛ���8�Ҡ��H��H�¿�A �'H�t$�����  ��y谛���8詠��H��H�¿�YA 1��Q;  �D$(% �  �� ����� ���tH���A 1��+;  = �  uH�t$�H�t$8D��H�s(�   H��������T$(1��� �  �� �  u�D$���C�C     t6�{H�T$1��   谜����y'�����8� ���H��H�¿�A 1��z;  �C   �)�t$��t���  t�%�A 1��:  ��   ����C�CH�Ġ   []A\A]A^�USH��H��H��   �=;)" ~�B�A 1��ś��H��H���z�  ��y�q����8�j���H��H�¿QuA �   �D$% �  �� ����� ���tH���A 1���9  = �  uH�$�H�D$(H��H�C(H�� H��% ������  	Ѓ�u	�C    �41��   H���ٝ�����Cy�ݙ���8�֞��H��H�¿�A 1��~9  �s(1Ƀ��H���f����D$�C$    �C    �C   % �  = �  �����C�CH�Ę   []�SH�����t�����C    [�AVAUA��ATUI��SH��H�Ā�  t���  �U�A SD��   ��}����} �D$��   �}H�t$�p���H�|$sIeRu=�}1��   ��@葚����u���A 1��8  �=�'" ~�u���A 1�����H�|$bS4Ru^�}1��   ��@�I��������A u��=A'" ~�u�׃A 1��ș���}萘������A u��='" ~�u��A 1�蟙���}H�T$1��   ������y
��A ��7  D�t$E����  H�U(H��H����H��H�� ���  % ���	ȃ�:u3�D$H�|$H�T$�D$�����H�E0H9D$�,�A ������D$�D$H�M(�}H��H����H��H�� ���  % ���	Ѓ�uuT�|$�L$�D$    Hc�H�|$H�|$�����D$�S�A H;E0�����D��   �]�\$����}��   D��A�   �\$�Hc�A�����Hc�I��H�� I��% ���A���  D	�E1��ߋ=	\" �D9�~FF����b I��D9�u�L��" L��H���  9p�  H� ��F����b I��D9�t�D9��H9�tH;u0���A ������]ӋI%" �M ��u�=%"  ��   ����� ��@	�1Ƀ=["  t�}$��у�	ȉ�A�$��A�D$�ҰD�A�D$����A�D$������A�D$tQ�u��~6�M��~/�ؙ�����=�  ~ ��" �P����" ��A 1��6  ���� ~�޿9�A �  �=�$" A�   ��  �=O$"  A�L$��UA �uA��rA A��D��u�A LD�1������N  ��A�L$A�$A�D$ tM�} u�u ���A �   �ؙ�}����A�$��}����}��A�T$��}=�  ��~��  �ƿ��A ��U���t9��޿�A 1���4  �=�#" ~'�uP��A�$E�D$D��A�ٿ'�A P1��?���ZYA�\$��A�D$��A�   A$�   �e�A 1��4  H�pLc�H��H��tL�@M9�wM��LXM9�r$H� ��1�H��tH�NHNH�u0���A 1��C4  Hcp PHc�D)�I��H�� I��% ���A���  D	�E1�����H��D��[]A\A]A^�ATUH��SH��   H�t$�H�t$ �:�  1҅���   �t$ �   ���H��1�����H�D$P�   H�  H�H��H9�}nA��H�T$H��A��	D���w�����tK�D$8D$uA�D$	8D$u7�D$
8D$u-�D$8D$u#�D$8D$u�}1�Ic�����H��H��H��?�H���x����   H�İ   ��[]A\�AWAVAUATI��USH��H��8  �=�!"  ~!H��1����A 耔��L����6  �
   ����1�L�濠�b ������ �b ��A��� �  ��y�����8� ���L��H���+  H�t$0�   D������H=   t�֒���8�ϗ��L��H�¿qA 1��w2  ��$!  �   H��D���Eں0   諔��H��0u�H�|$�   ���A E1�������uf�|$���  �=!" ~���@tA �oVA HDЉ޿ņA 1�腓����?~�?   ��A �qH�M" �   1����b H�  H�H�����,����sH�}-����E��A��t�D$u ��   A�   A9�~GL��,�A 1��1  �t$���  t�A�A 1��v1  A��f�M2 �   A)�Ek�A���  DN迠�b �����=3 " ~!A���@tA �oVA HD�D���r�A 1�訒�����A ��b ��r  H��H��u���A ��!b ��r  H��H����  E��u���A 1���0  �=�"  ~!H�޿��A 1��M���H����4  �
   �ې��1�H�޿��b ����� �b �����  ��y�א���8�Е��H��H�¿�YA �����H��" �E$����H��" �   1����b H�  H�H��������H�}(1������="" ��~���oVA �@tA HDЉ޿ˇA 1�藑����A ��!b �}q  ��t#���A ��!b �jq  ��u�=�" ~W���A �KA�A�� p  ~1f�M2 ���A ��!b �6q  ��t�?�A 1��}0  ��=�"  ���=�" ~
��A �q������b �L����f�M2A�   �H���H��8  []A\A]A^A_�AUATI��USH��AP�=6"  H��~H��1�H���,�A 跐���   H��b �#����-   H��舐��H��I��t(H���  �1  I�}���1  )���yH�G�A 1���.  �+   H���K���H��I��tH���  ��0  I�}����0  �H���0  �ø   �މ¿��b �����I�|$-�<   �d���=  ��~H��,�A 1��q.  ���b �2����=N" ~&Y���޸@tA []A\A]�oVA �r�A HD�1�龏��X[]A\A]�AUAT�U�A US� b H����o  H�t$1�H��H��蛒��=�   H��A��
H�D$�8 tH��_�A 1��g  ��b �7m  ��b �n  �=jA ��b �o  H��I��u���A 1��vg  H�t$1�L���/���=�   H��
H�D$�8 tL��_�A 1��Dg  ��	���   A���S" 1�A��D��	�9�~=��  �b 9���u��޿��A 1��6-  @��H��A9�u��։�޿��A 1��-  ��u�   ��A 1���f  �=�" ~��޿�A 1��n���HcS" D	�Pf��  �b �S" �U�A � b �l  H��[]A\A]�AUATA��USH��H��H  H�t$�ܿ  ��y�ӌ���8�̑��H��H�¿QuA 1��t,  �D$ % �  = �  uH�\$�H�\$0H���������tE���tI����!��˃�v<1�E1�=" ~gE��@tA �]A HEȺ2�A E��HE�H��9�A 1�脍���9!�H��$�   �����A�   ��
  H��$0  ��-  H��$�   H���  �E��    HE�H��H  []A\A]�AWAV�u�A AUATI��USH��H��I��H��  H��LD�E1�H��tHL�:E��t?1�H���H���H��H��H��w(�B��t<:u�>���H� E1�B���P���wD�`=1۾��A � b �l  H��A��u��u�   H���U���H�Ã=�"  ~-�@tA H�ۺ��A H��HD�A���A HE�H��A 1��U���E��t ���b H���Z���H�ۿ��A �?  �h  1�H��b ����H�t$��A����  ��y�Ɋ���8���H��H�¿�YA �{  �=W"  u�|$81��r  �gH�|$@   ~\1�H���A �+  H�|$@�  ~BH��$�  �   D���r���H=   u%H��$�  �   ���A 賊����u
�/�A ��*  1Ҿ�  D��見��H��y�����8����H��H���  H�t$�   D��������t%��y�����8����H��H���  H��V�A �f�|$U�tH��s�A 1��  ���A � b ��j  ���A �ſ b �4k  ��tH��t���A 1��;)  ��u3H��u.���A ��!b �j  ���A �ſ�!b ��j  ��t
H����A u�uXH����   H����*  �ō@���	wD�}0��D�A 1�D��D���)  �E���v��v��{�A 1��(  ���u�   �����N" ������N" ~�   ��A 1��Nb  �=g" ~4������A tH��$�   ���A ��1��]���H��$�   ���A 1��ɉ���wN" �ȃ�~�P�Hc�f�� �b Hc�f�� �b ����f�eN" ��@���f�-\N" H��$�  1���  D�=�! H��H���A�� 
  H��$�   ��   �vL���A ��'  H�۾�-b D��H���u8�=�"  �x" �5�" ��$�  ��$�  �  ���A 1������  1�1�H��衋����A��y襇���8螌��H��H�¿�A �Z1Ҿ�  ������H��y�y����8�r���H��H�¿ qA �.H�u�@   D���d���H��@t�I����8�B���H��H�¿qA 1���&  �=�" H��1�1�@�p@��t9xtA��A���A��t*@��t%�@b���t
��A �g���f��$�  �   �@�H��H��H��@u��ɿ;�A �;���D���k����5E" E��DD�=O" @��$�  D��$�  ~A��@���V�A 1������HcnL" A���  � �b �2   ���b ��	fǄ  �b   Hc�K" ����b     ��$�  H��H��󤹂   H���~D�cH��$�   D��$�  �����A�   ����E1�A9�tH��A��H��   �n������	�e�������   1����b �����A�t$I�~-�L������b �2����=N" ~A�t$D�⿂�A 1��І��H�Ĩ  []A\A]A^A_Ã=W"  u0H��   ���A H���a�  �����5" �/" H�Ę   ��Ë" ���S1�H�Ǿ/   �\���H��H��t�����[�AWAVI��AUATI��USH��H���   �=�" �L$~H�ֿ��A 1��&���H��L�|$8�Ʌ��H��H��u�̄���8�ŉ��H��H�¿��A 1��m$  1�H���م��� /I��H�@H�D$H�D$@H�D$ HcD$H�D$(H��莇��H��H����   L�rH�|$H�T$L���܄��H�t$ H���O�  ��H�T$x�I�|$H�t$@�$   �A�D$ % �  = `  uH�D$(I9D$0u��   = @  u��z.t��ɍA L���i������k����ύA L���T������V���H�D$@M��H�D$M��tH�t$I�~��&  ���.���M�6���L$H�|$8H��L������������H���k����   �H���\���A�E  1�H���   []A\A]A^A_�ATUI��SH��" ��H��t$H�;L��賅����u9ktW�ҍA ��"  H�[�׃=�" ~��L���A 1��P����   �r$  L��H���$  H�H�A" �kH�7" H�C[]A\�ATUI��S��A ��A ��H��H�=p" ��HE�����H�=~" H��L�⾻_A 1��,���H�=e" �����H�I" H�t$H��H�D$    H�$    �������y
�   �-�����u����2H�<$~���߀�Nt1���Y��tH���z���������p����   H����[]A\ËG����   USH����H��D�OH�=�" D�L$�8���H�=�" �,���HcD$H�=�" ��A I����H��I��I��H��A�� H�� ���  A	�H�% ���	�1��%����   �#�A ������t��tH�5G" �H�A �����1��6���H��[]�AVAUA��ATU��SH��H��  �=�" ~�V�A 1��s����`�b H� H����   ;huH�0H��$�   荁��ǃ�       �2H���̓=�" ~H��$�   �꿗�A 1�����H��$�   ���  A���uD�+�  H��$�   1�D��蟄������x  蠀��H�=E" �H��$�   ���A 1��������|���H��$�   H�¿�A 1��   H�t$��~A �V�  ��y�M����8�F����p�A H��1���  H��$�   ��~A H�D$    蜀��H�|$H��H�������1҅����   uGL�sE1�H��$�   D��~�A 1�蝄��H��$�   L���Ͳ  ��x)A��A��3u̿+�A 1��n  H��$�   ���B��������H��$�   Hcվ�a  諲  ��y!����8�{���H��$�   H�¿��A �����H��$�   L���V�  ���S����I���8�B���H��$�   H�¿QuA �����H��$�   ��   H���   �H�Ġ  []A\A]A^�SH���?���t+觀����y"��~���8����H���   H�¿EqA 1��  ���    t7�=i" ~H���   �S0�O�A 1�����H���   ��~��H���   ��  H���   [�T~��AV���  AUATU��SI�����   H��    H��$   A��L��A��A�   ��~��A	�H��$    �$  D�������H��$   ��tA 蹂��H��$   D��H��1��Ă��D��H��D	�����A��u��˃��u�H��    []A\A]A^�AUATI��US��H��0  �_��aA��A��E��D�D$A���+�����t^D�D$��H��$  �ىھu�A �����1��@���H��$  H��$   ��}�����A H�������H��$  ���A ����I���H��$   L���}����tA H���ʁ�����  �   ����A	�H��$   H�|$��1������D��H�|$	�������u�D��L������H��0  []A\A]�ATUSH��   �-l" ��~	�E��_" �4������   t���A �<����  �͐A ��ېA �&����  ��A �����[   ��A �   �����[   ���A �}����Z   ���A �n����Z   ��A �_����Y   ��A �P����Y   ��A �A����X   �#�A �2����X   �,�A �#����9   �5�A �����9   �>�A �����8   �G�A ������8   �P�A ������>�����A ����A HE���H��1��`�����H���ˁ� 	  �+������u�������u�   �Y�A ������"   �b�A 1������"   �k�A A���A �q����!   �t�A �b����!   �}�A �S����������A ����IE�H��1�������   H����������uϾ   ���A �����   ���A �����   ���A ������   ���A ������-b	" H��   []A\�AWAVAUATA��US�WA H����!b ��H��  M��H�T$�\  H��u%�WA ��!b �\  H��uH����   H��E1��H��u	H��A�   H�t$ H���9�  ���@  �D$8% �  = @  uDH�߾�A �|�����@tA H��$�   HD�A��'`A H�ھ��A 1��~��H��$�   ��   =    uH�|$H  u�  = �  ��   H�޿��A 1��f  H��$�   H��$�   ��'`A �w�A 1�E1��F~��1�1�H���j}��A�ǃ� xE��t
D���{���+E��x&1�=�"  �  L��H�޿�A 1��}z����  Hce" 1���9�~H��9�\�b u���  =�   ��   �P����  �,�`�b �*" ��   H��$�   H���ay��H�|$H�É�I�A 1��}���/   H���z��H���.   HD�H���
z��H��I��tWM�wH�t$L���{��������1�H���L���H���uH�t$L����x�������A� u
H�t$L�����A L�����A H����|��H�t$H����|�������=�"  ��   ��  H����|����A��y�x���8��|��H��H�¿kqA �0H�t$�   ���x��H=   t��w���8��|��H��H�¿qA 1��u  �=\"  tH��L��9�A 1���x��H�t$ D��裪  ��y�w���8�|��H��H�¿�YA 봋l$x�3�="  tVH��L��R�A 1��x���B�=�"  t9H��L��
�A ��D����x����y�,w���8�%|��H��H�¿EqA �S������1�H�ĸ  []A\A]A^A_�AUATA��USHc�H��A��H��H��  ������uH���
����Ѕ�t��A 1��v  A��H�|$����҃��F���H��$�   �   �ǉ��x��H=   t/H�=�:" H��$�   ���A 1���x��H��$�   ���A 1��  A����   H��$�   1���1�A�ؒA ������$h  ������	�������f9�$f  u$	�9�uf;�$l  ufǄ$l    fǄ$f    f��$l   D��$h  u
fǄ$l  �Ƀ=o"  u81�1����>w��H��t���A 1��g  H��$�   ��  ���Yv��H=�  u�H�|$�����x����$h  H�ĸ  []A\A]�1������US��H��   �=/�!  uw1��*x��H�t$��A ��! �5�  ��uL�D$(% �  =    u<1�1���A �y������~(H�t$�   ���w��H��u���v���D$1��! �=��! �
w���ع  ����Z��t��y���ˉ��! ����! H�Ĩ   []�AWAVAUATUS����H��  �=9"  ���!    t�=#" ~,�ډ�&�A 1��u�����A ��!b �U  ��t�1���  �E����  Hc��s������  ��!�Lc�B�<� �b  �k  B�<� �b  �\  H�|$�   ������1�1���A���lu��H��y��s���8��x����H�¿N�A �3H��$   �   D����u��H=   t�s���8�x����H�¿o�A 1��O  D��$�  E����   �=!"  �h  H��$   A�ؒA ��1�1������J  A�   E���_  f��$�   D��$�  u
fǄ$�  �Ƀ=�"  tH��$�   D��޿��A 1��Kt���=�"  �8  H�|$�����1�;� �b u	�޿"�A �D;� �b uD��N�A 1��  H��H��@u�B�� �b F�$� �b B�4� �b 9�u'�=D" B�� �b ~e���   �޿ՔA 1��s���OH��$�   �������H��$X  ����������B�� �b L��$�  ��H��$H  @�΀A�ٿ��A 1���  ����   1��������   ����   �ع  ���D�rE��������w��A��A�����w��A��A�����������������A 1��  1�1�D���:s����y�q���8�v����H�¿ޓA �����H��$   �   D���Fr��H=   �|����uq���8�nv����H�¿ �A �����H��  []A\A]A^A_�US���A R��q���=i�!  t?� �b �   H���̓x@ t�1ۋ� �b �� �b ���   1���A H���<r��9�}�X[]�AWAVAUATUSH��  �=��!  t�D$    �O  ��A ��!b ��Q  ���D$u�H�=�!  L��$�  ��  �o�!    L���u2��UA �9WA �t��H��H���! u�s�A ��  �D$   ��  H�D$@    H�D$(    �D$    �D$    �D$    H�=��! ��r����u<H�|$(H��t��o��H�D$(    H�D$@    H�T�! H�t$@H�|$(�}t��H��H�|$(H���0  �o���&  H�|$(H�t$0�
   �t����H��t�H�D$0H9D$(�q�����跷����uB�Eă�v,�E���v$���   u��A 1��  �=����������w��A 1���  H�|$0H�t$8�
   �s��H�|$8H9|$0I�������H�t$0�
   �q���]t��H�H�D$0H��DQ tH��H�D$0���DQ uH��H�D$8H�D$8H���u��  H�\$0�   ��A H���:o����tH��H�\$8H�D$8�8/uH��H�D$8H�D$8� /dev�=A�! �@/~H�L$8D����A 1��o����D��H�|$8���  A��0���H��$�   ��	�Ǆ$�      	��E�  ��A����   H��$@  �����������=��!  H�\$8L��$�  ugH���������~L��������*�A ���@tA HO��%�@tA tL��H�L$����H�L$�����A HM�L��H�޿9�A 1��?  ���! �L��H�޿��A 1��%  ��$�   H��$�  H�D$8tD���A 1���  H�|$8D������D��H��蓵��H�߉�A��膵����D!��H���! D!�H��t6;(u,�x u,�ۻ����u#H�=��!  uH�t$8���A 1��  �H�@��E���������������5��! M��L��1�1�9�}����  ��;iD�H��8�����  1�1��������=��! ?A��~�@   �@   �2�A �	  H��$�  ������!���Hc]�! Hc�I��I��A���  Hk�8���  H��H�� % ���A	�A��uH��@�ŉ�@�� 	�������@�NA���   uH��@�ŉ�@�� 	��������*A���   tA��r��uH��@�ŉ�@�� 	�������	�Hk�8H��$�  ���  D���  H�L$�k  �=Y�! H�L$H���  ~H��$�  D�����A 1���l��H�2�! H����   ;(��   Hc5N�! �HHk�8H��<�  �A���woHcD$��<�  ��<�  ��H��sE�F���Hc�H��$�  Hk�8;��  H�<t����Hk�8H�� ���1���A H��4�  �
  �   H��	D$�&��t"H��$�  ��   �A�A 1��
  H�@�<���H��$�  ����1�H�|$hA����迹��Lc%y�! H�|$h���~  �-g�! Mk�8E��B��$�  t6Hc�H��$�  1�Hk�8H�9�}1E;~ uA�N�D$�������I��8��Hc��D$Hk�8���  �E��! D�c�A�������H�|$8�h���O  ������Hc�H��$�  Mc�Hk�8H背,�  �=��! BƄ ��������H�L$8H��,�  �ڿ��A 1���j���v���H�=��! �~j���=?�! �=6�! ~>�5j�! ���A 1��j���*L��1�;-Q�! }֋S �s���A H�1���H��8�j���ۋ,�! �P���1�E1��xL��E1�A���XD9XL�@8~1H��$�  �   H���   H��L���H��$�  �   L���D9�L��u����Hc�Hk�8���  ��%�  =�   t=�   t��;��! |��5  �=V�! ~�޿˙A 1���i����A ��!b 1���I  ����   ��A 1�A�   ��  뭋|$H�T$H1��	���i������   A���H��$�  �<����=��! ~D�濩�A 1��ki��E����  H�=��!  uHcÿ��A Hk�8H���  1��  �-��! ��;-��! �%���9�����Lc�H��$�  Lc�Mk�8Iƃ=m�! ~Ik�8A�v�b�A ���  1���h��Mk�8H��$�  H��$�  �   B��$�  N�< �������D$����I�� �����hA 1��  �|$H u�|$LYw�y�A 1�A�������  ������|$H�T$h1��	H���h����������|$x��   E1�D;�$�   sx�|$H�T$T�	�1�D�|$TA�   �h���L$\�t$X��A�~�ʁ� ���H��I�Љ���  �� �����H�� L	�A����D��	�H	�H9�DE�A��E��t��=���E1��5��������Lc�Mk�8J��4�   uJ�    ��  B��4�  �@�����@�����@�����@�����H���! H���! H�PJ��4�  Ik�8H���  �z tH���  �B    �Y�A 1��  Mk�81����A ���! J��$�  B��$�  B��$�  �T  Hc�;��! }-�P�   Hk�8L���  Hc�Hk�8L��H���  Hc����1�9�����)������=!�! ~UH��$�  1�;-K�! }�S �s���A H�1���H��8�f���ۿ֛A ��e���|$ u�=��! ~q��A ��e���e�|$ t^H��$�  1���! 9�}ЋS��t:��~�   H����������u�D�cD���v����   ��D��������c��C ��H��8묃|$ ��   E��t��A 1��-  ��! �D$    D�p�H��$�  Ic�Hk�8H�E1�E��~�Ic�H��$�  L��$�  Hk�8E1�Hŋ� ���A9E uz�����A�M����t#1�H��������D��t �   L���	���D�����D��u��AE�Hc�Lk�8B��<�  �ωL$�����L$�   �Ɖ�������D$B��<�  A��I��8E9��j���A��H��8�9����=W�! �=N�! ~A�t$��A 1���d���/H��$�  1�;-f�! }ӋS �s���A H�1���H��8�d����H�5�! D�9�! A�   �:HcD$H��s!���L��$�  ���   A��1�D9�|LA��u`L��H��	D$H�vH��tp�N��~�����%�  ��	tރ���~����   ��A 1��  A;Pt	A9X(D��A����I��8땉Ã� x�H��逿:�A Hk�8���  1��X  �=?�! ~�t$�l�A 1���c��H��$�  �=[�! 1�A�   H��9�}3�p,��~#�x0LcL$���I��r�p0L��H��	t$��H��8�Ƀ=��! ~�t$���A 1��\c��1�E1�A�   D;%��! �4  �{0KHcD$H��s������0L��@�鍕�   H��	D$�=x�! �S0~H�3���A 1���b����C0����H�{ uH�    �  �S�@�����@�����@�����@�����@�����H�#�! H��! H�PH�C�C0H�S�B�����S H��� �b �S�� �b �T��! �B    �P�����! u�   �   �̝A �  Hc��! �V�A Hk�8���  H���  1��r  ��!    A��H��8�����=q�! ~�t$���A 1���a��HcD$�   H��r	���t����|�! 9�����������A 1��
  �D$H�Ę  []A\A]A^A_�SH��H�=�! �c��H���pd���   �e��SH��H���   ��H�t$(H�T$0H�L$8L�D$@L�L$Ht7)D$P)L$`)T$p)�$�   )�$�   )�$�   )�$�   )�$�   H�=��! �+c��H�5L$" �\�A �Za��H��$�   H�=3$" H�T$H���D$   �D$0   H�D$H�D$ H�D$��c��H�5 $" �
   �na���   �Dd��SH���   ��H�t$(H�T$0H�L$8L�D$@L�L$Ht7)D$P)L$`)T$p)�$�   )�$�   )�$�   )�$�   )�$�   �v�! �=��!  lH��H�=��! �Jb��H�5k#" ���A �y`��H��$�   H�=R#" H�T$H���D$   �D$0   H�D$H�D$ H�D$��b��H�5#" �
   �`��H���   [�SHc�H���a��H��u
�ƟA ����H��H��1�H���H��[�QHc��b��H��u
�ƟA �����Z�Q�7c��H��u
�ƟA �����Z�S1�H��H��H�t$��`��H�T$H��t�: tH�޿ԟA 1�����H��[�S1�H��H��H�t$�`��H�T$��H��t?���t9��Tt4��Mt'��St%��H�
��mt
��huk�<���st
��tt�k�<k�
����  vH�޿�A 1��B���H����[�ATU�   S��H���cA H����]����u���b�����A H���&H�{�   �cA �]����t���b����A H��1������D�cA9�t���qb��D��H�ƿ,�A 1�����f�[
f��t)D���Lb����H����A�   A�   �N�A 1�����[]A\�1�H�H9uH�FH9G�����USI�ʋ��E1�E1���L9�t4B�,�   ��A��A����A1�A��E��DE����D1ȃ��u�I������[A�]�H��H�L$�D$    ����H���H��  ��  H����\����~H�H��|�A � 1��S]��H��  �AWAVA��AUATI��USA����D��H��H�?���t*�T$H�<$�a��H�T$I��H� H�<$�Pt.H��I�<$����   �=�!  ��   1�A����)����   1�L���;^����É�t7I�$�
��߀�PuH��I�$���1�A������1�A����)Љ��ŉ�D9�|D9�~H�5k�! D��D�꿃�A 1������I�$�0@��t I�H���Qu���A 1�����H��I�$�=��! ~�޿��A 1��&\��H����[]A\A]A^A_�USH��H���   �=j�!  ~H���ƠA HE���A 1���[��H��H���! t��A H����\������   H�t$@��A �x�  ��y
���A ����H�l$@H��H����H��H�� ���  % ���	Ѓ�	t#H���u�����H!�H��v�t$@��A 1������H�t$@�   ���b �5 " �����<�! H��! �/�!    H�8�! �   1��   H����]������! y��Y���8�^��H��H�¿�A �'H�t$@��赌  ��y�Y���8�^��H��H�¿QuA 1��=����D$X% �  = `  t�e"     �H�D$h�X" H�5��! H�|$1������D$H�|$�:" 躿���=+" ��t������uH�۾ԠA �;�A HE������=B�! �   �@�b �[��H=   t'��X���8��]��H��HD��! H�¿qA H���>����@�b �@�b ��   �H�= �! �>  �   ��	D*�! ��~S�=�!  tJH�5��! 1��W�A ���! ���!     �����1����A ������u1��#]�����! ���!     H���   []�USH��QH����+b ��9  H��uH��A 1������1�H��H���\����u�   �D���A � b � 9  ��t�=��!  x&H�޿��A 1��Y������A ��!b ��8  ��u��1�Z[]�ATU1�SH���I��H���H��H�Y��;r  ��L��1��vr  ��r  D�$�`�b D�d� �=�! ~ H��u�¡A 1��X��D���A 1��X��H��H��u��=��! ~[]A\�
   �W��[]A\�AWAVAUATI��USH��H��H���G  �/   H���^X��H���.  H�X�    H���X��H��tH�޿աA �:�� u� _H�����u�1�H���H���H��H�A�H��H�$wH���H�޿�A 1��N���H�����t��w�H�޿M�A ��Hc��! ���! �D$I��Hk�6E��H��@�b D;l$��   H��H���4V����u
H�޿��A �A�D$3Mc�tH�<$tIk�6��s�b tCH���1�H���H���u2�U��Ik�6H�;H� H��@�b ��9�uH��H�޿��A 1�����A��H��6�n���E��t2��A ��!b �R7  H��tH��H���U����u���!     E1��:D�-��! A��u�   �¢A ��5zN! A9�|��A 1�����A�E���! Mc��6   L��Ik�6H��@�b H���H��H���U����A ��!b ��6  H��tH��H���U����uf�M2 �0�! ��A ��!b �6  H��t1H��H����T����u"Mk�6��! fA��r�b  @�H��H�������H��D��[]A\A]A^A_�AVAUATUS�? u
�%�A �   I��H��� b �9�A ����6  H��I��tH��H��1��>����þ?�A � b ��5  L��H��H�������E3A��tPHc�H���1�Hk�6H��H��@�b �H��H��H�H��v(M��tH��L���H��H��H�H��v�E�A 1������=��!  ��   Mc�1����A Ik�6H��@�b �U��M��tL�濝�A 1���T��Ik�6��s�b u��xHc�Hk�6��s�b t���A 1���T��Ik�6��s�b @u��xHc�Hk�6��s�b @t���A 1��T��Mk�6A��r�b  u��x4Hc�Hk�6��r�b  t$��!b ���A �]4  �����A t���A 1��ST��E��t��t�
   ��R���
���A �S���=��! ~B�M0�U/1�D�M-D�E.�@tA ���A �T���=��!  t� �b �@tA ��A 1���S���=J�!  ~[]A\A]A^�
   �nR��[]A\A]A^�ATU��VA S��!b �4  �R�A H�ſ�!b ��3  H��I��uH���`^b �@8b HE��J���A H�ﻀ�b �CW��H��u3��A H��`^b �,W��H��u�p�A H���W��M��uH��t�@8b ��a  ����J! �=��! 	H��@8b u���A 1��Z���H��`^b u�=�J! u�4�A 1��<���H��@8b u4��J! �P���w&�����A t�Ⱦ7�A ��A HD𿝤A 1������H��[]A\�SH��H��H��H�|$u�=��!  ��   f�CN��f�CL����   �;�A �!Q����t��KNH�|$A�   �L   �   H�9�! �A ������KLH�|$f�CNA�   �   �   �����f�CLH�D$�8 u	�=5�!  tk�K:��H! H�|$E1�1������=�!  f�CFt��3�H! ��KH��H! H�|$E1�1��v����KF��H! H�|$f�CHE1�1��Y���f�CJH��[�USH��H��H�|$u�=��!  ��  H�D$@tA f�F2�   H�|$H��A�   �   H�=�! �A �   ��f��f���A   ��H�����f�C2�C0H�|$A�   �   ��f��f���   ��H�����K4H�|$E1��   f�C0�   �����=�!  f�C4�s0t���   f��f���)���K6��   ��f��E1��   f��H�|$�   �)��F���f�C6�C8�   �{4��f��f��f����f�C2��uf��f���P   �)��f��f���P   �k��)��ω�����PH�|$A�   �   ������S6�KPH�|$E1�f�C8�   ����f�CP�C6�S0���=�   �C4�P��C8���S2���   =�  ~��A 1�����H��[]�SH��H��H�|$u�=��!  ��   H�D$@tA �N:�}F! H�|$H��E1�1�H�e�! <�A �%���H�T$f�C:�: u�=��!  ��   �?F! H�|$E1�1���������K:�#F! H�|$E1�1�f�C<������K@�F! H�|$E1�1�f�C>����H�T$f�C@�: u	�=�!  t9��E! H�|$��E1�1������K@��E! H�|$f�CBE1�1��l���f�CDH��[�US��Q�=	�! ~��1��G�A �N����uH�=v�! H����   Z[]�N���=��!  u�H�=U�! H��t�1�1��P����t
�b�A �)Q��H���! H��t�H�S H�="�! �q�A 1�1��tO���+H�=
�! 1��~�A H���ZO��H��u�H�5��! �
   �N��H�[(�X[]�USH��  �=A�! ~
�ǥA �-M��H�=��! 1�1��P����t
�ǥA �P��H���! H�|$��  �N��H���  �=��! ~H�t$���A 1��vM��H�|$�>   �M��H�|$�<   H���EM��H��H�D$��   �x"��   H����   �{�"��   �C� �0   �H���H��H��u
�ƟA �b���H���! H�E    H�-��! H�E(H�D$H�x�U����=C�! H�E ~H�ƿ��A 1���L��H�{1�H�t$1���O���D H��H�������H�|$�ۿ��A 1��	����=��! ~
�åA ��K��H��  []�H��H��t-1�H����H�эA�1�Hc�H�H�Ʌ�t��� ��H����J���US�@tA Q��N��H��H���1�H���H��H��H�Y�����Hc�1�H��H��t� ��H����Z[]�AUATI��USI��R�?�A � b �6,  H��H��u3�`VA ��+b �,  H��H��u��+b �եA �,  H��H�ÿۥA tl�/   L���K��H�-9�! H�PH��HE�H��t1H�EI9���   H��uH�} H���L����u	L�m��   H�m(�ʿ0   �j���H��H��u�ƟA 1�����H���! H��L�mH�-��! H�E(����H��H�E ���A 1���J���9�A 1���J�������K�A I��1���J������L��H��H����K����t��A �J��H���>���L���6���뭿
   �<I��L���"���H��H������H������L��H��   �X[]A\A]�AVAU1�ATU�6   S� �b H��H��  L��$�   �1���   L���󫹀   H����  �]�A ��b �*  ��u�]�A ��!b ��)  ��u�0�g�A ��b ��)  ��tؿr�A �  �g�A ��!b ��)  ��u�]�A ��b �)  ��t���A � �b �M����]�A ��!b �)  ��uܾg�A ��b �})  ��t���A � �b ��L����g�A ��!b �Y)  ��uܾZA ��b �)  H��H��u�ZA ��!b �)  H��H���@  ���A H����G����u/H���A ��z  ��y
���A �Z���1�� �b ��H���$��   1�H���H���H��H��H��H��H��v�   ���A H����G����u�6H��v�   �ϦA H����G����u�u6�   �֦A H���G����u 1�� �b �gH��H��H�ǾƦA 1���K���uH��H���z  ��x�l$(�C�IL��H�U H� �DPuH��ܦA ��  �=��!  ~H����A 1��H��H��������1�� �b ��G����H�Ǿ��A 1��nK���?�A ��b �=(  H��u�?�A ��!b �)(  H��t'H���H���1��ſ �b �G����H�ǾG�A 1��K���S�A ��b ��'  H��H��u�S�A ��!b ��'  H��H��tmf�K2�W�A H���F����uf�C4���O���A H����E����t���A H����E����uf�C4���%�^�A H����E����uf�C4���H������f�C4��A ��!b �S'  ��A ��b H���A'  H��H��uH��tKH��1�H���H���H��H��H��H��H���  v��  �b�A 1������ �b ��I���.�A H����I���|�A ��b ��&  H��I��tSH��u���A 1�����H���1�� �b H���L��H��H���H��H��H��H�D�H=�  �{���L�� �b �I�����A ��b �p&  H��tH�ƿ �b �@E���=��!  t1�� �b ��E���x� u�@� �=B�! ~� �b ���A 1���E��1�H���� �b �H��H��H��H��H���  v��  �ȧA ������`b �
�x� t'H��L�m M��t3L�� �b �?I��H��t�H= �b uӀx=�  L����A 1��������tA ��b �/%  ��tf�K2���tA ��!b �%  ��u��A ��!b �%  ��u��A � b ��$  ��u!�2�'�A ��!b ��$  ��tؿ1�A 1��O����'�A � b �$  ��u�a�A � b �$  ��tI� b �'�A �$  ���h�A u�� b ��A �}$  �����A u���!b �S`A ��$  H�����A t��S`A � b �$  H��H��t� b �a�A �5$  ����A t7�V����S`A ��!b �$  H��H����   �a�A � b ��#  ����   �}  L�k��   H�=��!  u�$  H��t������S`A � b �($  H��u�S`A ��!b �$  L��H�������=�! ~A��A 1�E1��C��C�t5 1���A I���~C��I��u�
   �B���L��H���o���f�K2� �&�A � b �A#  ��tf�K2 �*�! �-�A � b �!#  ��tf�K2 �
�! f�C2�7�A f% f= �(����c�A � b ��"  ��tf�K2 ����! �'�A � b ��"  ��tH��u�o�A ������'�A ��!b �"  ��u޾�A � b �"  ��tH��u���A ������A ��!b �s"  ��u�� �C2�t�'�A � b �X"  ��uf�K2�H��t,�}  t&�=�"  tH�5�" �ȩA 1��}����g"     ���A � b �"  ��tf�K2  ����A ��!b ��!  ��u�	�A � b ��!  ��tf�K2 ��	�A ��!b ��!  ��u�JbA ��b �"  H��H��tOf�C2��A ��������@I�|$H��f�C2fǄ$�   ����@��Hcz�! H��C�n�! �����H��`�b �&}��L���|��� �b �|��H�Đ  []A\A]A^��@����������SH������H�߾@�b ��   �=�! [�{A��AWAV�@�b AUAT1�USI��H��H��E��H��H  ���!     ���!     �$�@   H��$�   �H��D�L$�tr  ��x��$�   % �  = �  t
H�޿e�A �)L���v����=A" �   �'  �=��! ~L�����A 1������uL�����A 1������:   H��H�K�! �^@��H��I��uH�޿@�b �i?����A H���|C���-H�޿@�b �  �J?����A H���]C��I�vH���QC��A�:�@�b ��w���@�b �o  D�5��! �����=.�!  H��~-H=@8b �B�A tH=`^b �=�A �I�A HD��A 1��?���@�b ���b ��  H���D�5}�! L�s�6{���3L��芁��H��! � �b �   H��L���   �   �c   �@�b � ���=��! ��! LILO~%�H	�oVA �@tA �	�A ��	��HE։�1���>���s�9�A @��f�5��! �  �=C�! ~�i�A 1���>���z���@�b �z��1ҹ   �   �^�b �~���f" 9\" �v
  �=��! t�=�"  t�=E" tf��! @�0" �t4�=�"  u+��A ��!b �G  ��u�" ���H��� �b �>�! �=��! ~,�3�! D�(�! ���A ��" �5�" 1�f�����>��H��$�   �@�b �o  ���ɫA �
  �=C�! H��$  �5��! �5��! ~��A 1��=���N�A ��!b f���! U���  �R�A I�ƿ�!b ��  M��tH�����A ��	  H��@8b f�T�!   u�\�! I��u�(�A 1������C  M���:  �=��!  ~6H��@8b �R�A �N�A HD�L��[�A 1��=��L�������
   �;��H�|$x1�L���t���H��$�   ��A���n  ��y�;���8�@��L��H�¿QuA ��  H��@8b tH��$�   �   ��  H�L$HH�T$ H�t$D���]  ��y�I;���8�B@��L��H�¿qA �  t	����   �=��! ~�L$,D�D$.�n�A �T$(�t$$1��?<���|$ (ub�|$$�  uX�|$(�  uN�T$,�D$.�P����u9H��@8b ���A �"  ����  �=�3! ��  ���A 1��'�����  H��@8b �F�A ��  ��  H��@8b �Y�A ��  ��  H��@8b ��uH�A�   H�H��f�p�! �Iw��H��$�   �   H�|$x1�H�  H�H�����|��1���b �w���=��! ~4���oVA �@tA HEʾV�A H��@8b �]�A ���A HE��1��;��H�|$x�O������A ��!b ��  ��t���! ���A ��!b ��  ��t���! E��y���A 1�A��   ������A ��!b �  H��H���@  ���! ��A ��  �0@��t�b �p:��H��uH���A �����b �E�! �)����:�! �E����   <,uA��b E1�L�}�A�H�A �U  1�H���L���L��L��H��H��Lc�L���>9����D�D$�-  O�l5A��A�}  D�D$u��  H-�b �   ����D�A����    A��A��E!�D��	Ј��! A�V���1  �=�! ~�5}�! ��A 1��9���<$$��]A ��!b �n  ��u���A �����$   ��]A ��!b �J  ���0�A ��!b ����f	H�! �,  ��t�M�A 1��s���f�+�! ��=  ��u"���! �tf��! � �=e�! �t�A ��=U�! ~
���A �A8����A ��!b ��  ��t���A ��!b �  ��uf���!  ��! f	��! �<$��  �D$���! t i$�  ��  �ϯA ���=��  ~
�  ���  A����  f�F�! t0AiĠ  ��  ��������u	f�%�! �=��  ���A ~
�S  ���  f��! ��A ��!b �q  H��H��u1���@�b H��H=   u��_1�H��1��:����A��y�6���8�;��H��H�¿�A 1��?����   �@�b ���8��H=   tH��$�A �5���D���8���p�b H�t$P�
   H���G�A ��!b ��  H��H����  �Z�! u�S�A 1�����A�@�b A�D�b D�m E����   D�b �7��H-�b H�$�<$vD���5�U��t$D�⿐b D����6��H-�b ��I��vD���
���A �  �~�A 1��P���D�eE��t"��:��H� I���PtH������A ��  H��A��v�ٰA 1������D�$$A��I��E	�A��E�fM9��/����=c�!  u��A 1������N�! �=H�!  u�?�! ��������p	Ј-�! �='�!  u��! ��! �=�!  u�
�! ��! �=o�! ���! MENU~)���! ���! �>�A �5��! D���! 1���5�����A ��!b �!  H��H��tf���! u���A 1������1�H���H���H��H��H��%v�%   ���A ������I�b �%   H���n4���I�b 1�H����H��H�ɈM�! ��A ��!b �  H��H��t�0�! u�ֱA 1��u����@�b H������H��@8b u,�50�! �+�! ���=c�! �5�,! ~���A 1���4���<�A ��!b �6  H��H��t���! u��A 1�����H�߾@�b �������A ��!b ��  H��H��t���! u�@�A 1�������@�b H��������@�b 1���  H�׾�A 󫿠!b �  H��t�>�!    �0�!    �=��!  ��   �
   ��2����   �i�A 1��`��������   H��$�   Hc�H9��N���L���k�A 1��a������  �ֿ��A 1��N���A���
   N�t5DD�E��A��A��E	�A���A��D�=��! A�6@���������b �3��H�������L��z�A �����Jɿ��A ��w���7u�������<�! A�~ �ˮA ������i���H��H  []A\A]A^A_Ã=#�!  �����D�! �R��A ��!b �l  H��t:�5��! �@�b 1�9�}f�J2H��6��t�����A t�	���߿�A 1��I���X�R��A ��!b �  H��t:�5��! �@�b 1�9�}f�J2H��6��@tf�ɿ�A y�	���߿6�A 1������X�AVAUA�(�b D�-g�! ATUS1�A9�~_H��`�b �< uH������tCH�؊���tH�����t�  A�@�b H��L����0����tI��6M9�u�H�޿RqA 1�����H���[]A\A]A^�f��! f%� f���u&R���A ��!b ��  ��t�@�b �X�A 1��<���X�US��H��  ����   ��b � �b �@�b �k�����b �f��f�L�! ���b � �b H�ǹ   �@�b �H�ֿ@�b �@   �����  �@�b �����.�! �m���@�b �l��1�1Ҿ   �:�b �q��H�5��! � �b �k�����;  �7���! A�}�A �@�b ������t�=x�!  u�p�! ���! ���%����=��! 1�1��1��H��y+�y/���8�r4��H�5��! H�¿ qA H��HD5`�! �  �=ܽ!  H����   �=l�! �A�@�b ��   �]�! ��  ���A )ȅɉ��&  %��  �@�b ��   Lc�H��I�=�   ���L��L����P��$��D$��T$��P��$�f�T$�PHcҀ<�u#�PHc���THcʀ<�u����Hc�f�=;�!  ~���A �'/����@�b ��   H���=�! ~;Hc=b�! �v���5W�! �¿ֳA 1��/���t$�T$��A 1�f�����r/��Hc='�! �`v����t<Hc=�! �Pv���Ѕ
�! u&H���  �H   ���b �60����t�&�A 1������1���=~�!  uH�=�! �   H���.��H=   t-�-���8�2��H�5��! H�¿qA H��HD5��! 1��J����=��!  t���b �v����8�=��! � /����y)�\�A 1�������[-���8�T2��H�5��! H�¿EqA 묅�]�=��! ������@�b �^  H�5k�! �@�b �I1����y3�\�A 1������-���8��1��H�>�! H���@�b ���A 1������=��! ~
���A �o-��H�=x�! �0��H��  []�Q1�1��h���=��!  u�=��! �K.���
���b 舭���@�b ��]  �=&�! Z�@�b ��,��X�S�@b H��@�|  �@b �L  �`VA ��������   ���A ��b ��  H��u���A ��!b �  H��ta1�H���0����tS���A � b �4  ��t-�=��!  ��   �`VA ��+b �}  ���A H��1��-���b���A ��!b ��  ��u��   H�������`VA ��+b f�L$2�7  �O�A �@b H���%  H��u&H��H������H��H���������+b �~
  H��@[þO�A �@b ��  H��H��H��蜛����US� b H��H�I
  ��b �?
  � b �d�!     ���!     ��
  �եA �������tp1�H��������եA ��+b �|  ���A � b H���j  H��H��u���A ��!b �S  H�þA�A � b �A  H��H��H��H��裞��H��H���������+b �	  H��H[]�AUATA��USH��H��H��  ����f�=��! U�tH��HDM�! ���A H���[�   �cA �B�b �*����uH��HD �! ��A H��������   �cA �F�b �g*����tH��HD��! ��A H��1���H��u"���! H��$�   H��$�   �K�A 1��u.��1�1�H���-����A��y�)���8�.��H��H�¿�A �|  H�t$���\  ��y�q)���8�j.��H��H�¿�YA �P  E��t(���! H9D$`tH��HDE�! H��[�A H���#  �=η!  ~
�ɵA �)����  �@�b D���+��H=�  t��(���8��-��H��H�¿qA ��   �=�! 1�1��U*��H��y'��(���8��-��H��HD��! H�¿ qA H���   �=J�!  ~
��A �6)���=��! ��  �@�b �A)��H=�  t$�t(���8�m-��H��HDj�! H�¿qA H���K�=��!  t���b �;����=�=v�! ��)����y.�\�A 1������ (���8�-��H�5b�! H�¿EqA 1�����1���,��AWAVE��AUATA��US��I��D��H��  E��D�5�! H�|$yD��L���?������   H�|$�@�b ��   �H�|$������@�b H�t$��  H��E����! ��A ��!b �-��! �-m�! D#��! A	��D-V�! fD���! �~  ��u'�=�! ~����A �p(���E�H��� �b �f�! ��@�-c�! f�:�! U���1�)É�D��L���x���fD�5<�! H��  []A\A]A^A_�S�0VA H���#�!    �6)����uH�{�! H�4�! �-��UA H��H���! �*��H��H��! uH�޿*�A �?���[H�=��! �h)��SH��H���   ��H�t$(H�T$0H�L$8L�D$@L�L$Ht7)D$P)L$`)T$p)�$�   )�$�   )�$�   )�$�   )�$�   H�=©! �])��H��$�   H�=v�! H�T$H���D$   �D$0   H�D$H�D$ H�D$�*��H��! H��uH�57�! �
   �'�����! H�=�! �:�A 1��*(���   �`*��AWAVA��AUATI��USI��H��H���+����   L�cM����   L��L��L�D$�>%����L�D$��   M��t��tL��]�A ���uL��w�A 1�����H�{ t.L9C L�濏�A t�1��RZA ����E��uL���$���   �m��u
H�C��b �"��uE��L��tL��L�D$�q���L�D$H�CH�CL�C H��t�����uH�[H��(H��(�����;u�L�5��! L�-��! 1�H��[]A\A]A^A_�AVAUATUSH��   H�=��! I���'����{A��A��t
�$H�l$�H��H�=��! �'�������u���A �
�����A 1�������}uE��uKA��{t(�3)��H�Hc�f�Q u��_tH�5Y�! ���B'���H��L)�H=�  u�ܶA �H�ň]���E  L���g#��H��H���! uL���A �����   H��   []A\A]A^�V���! ��t���!     �yH���! H��t���tH��H�}�! �ZH�=��! �&����uH�=��! �&����\u+H�=��! �u&����$�$   t"H�5��! ���m&���\   ���$��uY������Z�AUATUSH��  �Z����P���v�� u��
u���! ������  ��#u0���! ��uH�=�! ��%���
���!     ��
t���u��j  ��=�ӡA �  ��"H��tE1�H��I�    @��   H��H��H)�H=�  ��   �������u�	�A �-��"��   ��\u^������"����\��t��
t��A 1��~�����
u3�s����� t���	t��t��=�!  t�<�A 1�������! �    �P���w�`�A 번H���X������A 롃�
u[���! E1�����H��H)�H���  aE��u*�P��>wAI��s;�=��!  u����! � H�������>���u����A �A�����	� D�H�ÈC��E1��\A��t��H��닿��A ����1�H��  []A\A]�H�j�! H��u����H�U�!     �SH���3��t@��tr��u"H�[H��(�$H�{H��t� ��H�C    ��ǷA 1��Y���H��(�[�SI�ȹ   H���������tH�޿޷A 1������[�ATUH��SH��D�#A��tEH�{H��t6H���= ����u*H�{H��u
H����A �'E��u����H�C    []A\�H��(�H���A 1��Ŀ��ATUI��SH�d�! H��tH�-P�! H�M�!     �   �����H��H��tv�ӡA H���6"����u��dA �;����H��H��tX�ӡA H���"����t	H�-�! �>����H��H��u�?�A 1������ӡA H����!����uH�޿U�A �   1��   1�=��! ~H��H�޿k�A 1��y ��1�M��H��H��L��������u/A� b I��I�l$�H��t/H�}H��t�H��������tH��(��H�����������   �H�޿��A 1��X���[]A\�ATUH��SH��D�#A��t8H�{H��tH�������uA��t-H��A �A��uH�[H��(H��(�H��̸A 1��+���1�H�{ []A\���ATUH��SH��D�#A��t8H�{H��tH���.����uE��t-H���A �A��uH�[H��(H��(�H���A 1��½��H�C[]A\�ATUSH��  H�5=�! H��$�   �`��H��$�   �1�A �n"��H��$�   �t���H�
�! H��H��H���! H���P  ��t
H�޿6�A �oH��H��L�d$X�P  ��u L;d$X~�=�!  uH��H�޿G�A ����1҃=��!  �ī! ��t6H���! H���n����t�5���8tH�޿��A 1��ۼ����  H���V��tH�8�!     1��   H�=:�! ��UA � !��H��H��! uK�=��!  ��   H�=�! �6�!    ��  �l!����x)���a��H�=��! ���A � ��H���! H�=��!  uH�5��! ���A �V���H���! H��H���lO  ��u�D$$tH�޿��A ����H�}�! H�Đ  []A\�H�F! �b H�C!     �H���! H��t@8xt@:x	tH�@���AVAUA��ATUA��S�Չ�D��H���=:�!  u�    ���A 1��_����=x�! E��@����E��~$���  E�ȉ�D�� �A 1�D�L$����D�L$�ߋ��! ������D��D	���	�	�HcЉ4���b 1�9�~]����b 9�u���  E�ȉ�D��[�A 1�����D��A9�u*A��A��E9�u�����  A����D�濕�A 1��к��H������Y�! H��[]A\A]A^�US1�H��H��H�t$�7��=�   H��w
H�D$�8 tH��ںA 1��L���H����[]�AUATI��USA��QH�-/�! ��H��t#H�} L�������uL���A �=���H�m�ؿ   �߻��L��H������H�E D��D������EÃ�A����EH���! DӈU	H�-��! H�EX[]A\A]�AUATUSH��  �=��!  t�=�! ��   1�1�������A�Ŀ�A x�   H�������H=   H��t
�!�A �g����   H��5�A �-����txH�t$�   �:�A �   �������   ��  �N   H�����A��  H��H��tE�   �?�A H��������t(H�}D��N   H��H)�)�Hc��F��H���Ľ   �$�   ��D$<���   f�|$ t4�<$�tN1�D������1�=��! ��   ��A 1��/���   �D$��<w��D$��t��P�����   �1�D��   �;��H=   �E�A �����D��   H�����H=   �Y�A �����H���  �
   �r�A H�߽   �������M����
   �}�A H���������1����.����   �$���<���������H��  ��[]A\A]�AWAVA��AUATUSHc�H��H��h  �8`�����  H��I���%`���ŉÃ����  D!���  �=v�! ~D��D���A 1�����D!�H�|$8����   �މ$�Ro����VA ��!b �������t�=*�! ����4$H��$�   ��D�e�����E����u
�D$   �A1�1�������H��t�+�A �BH�t$�$   ���B��H��$u�|$LILOu��D$�D$1Ҿ�  �����H��y
�3�A 蔶��H�t$p�ߺ@   �������I�A ��  �J�A x�H�t$�   ������H��u	f�|$U�t
�g�A ��   �=N�! ~��A 1�����H�D$pE1�H�p@�P@�׃�@��t��uE��uD�x�
���A �   H��H9�u��D$   �D$    �GH�t$�   ���E��H����   f�|$U�u}��$�   ����us��$�   �D$�D$E1�9l$dE��t_�D$1҉�B�48H��	H�ƾ  ���H��y�ӼA 1���  H�t$p�@   ������H��@�f�����A �׿�A ��<t�E1��E��Mc�A�ǅ�~?E��t:�|$�   �?   E�9�|$L��H���|p xH��$H  ��'�A 1��Ե��L��H���tt@���������t���   t��<����	�����   ��1�������X  H�����u5E��t0���@tA ���A HEȿP�A D��1��Z���H�5?�! ���A �M��L��t$<H���Lr�DsA�̓�?A��E��A��A��DqA����D$D��D�L���  �DxD9�rA���  �o  D9��f  E��u�A tA����]A tA�����A ���A HDȋ4$A�T$1���A D�L$裴���=��!  D�L$u+L��H�=w�! D��H��� �A D�Dr�Lq1�A��?�n��L��1�H���tx���t$DA��1��t$<�=7�!  ��u+H�=(�! A���TqD�LrD����E�ɾO�A 1�������  ��  ��VA O迠!b I����B�l4s����BD4r������u��!b ��VA �{������~�A �8  �=֡!  t��A 1�谳���.  ��VA ��!b �E�����u܋$H��$_  ��A ���H��$_  ��  �������y�����8����H��$_  H�¿kqA �\H�t$p�@   ���p����uH��$_  ��A �T���H��$_  ��������5����y#�|���8�u��H��$_  H�¿EqA 1������=��!  ~H��$_  �0�A 1�����4$�V�A 1��r��1Ҿ�  �����H������H�t$p�@   ��������u
���A 趱�����A �����H��$�   �ݒ��H��h  []A\A]A^A_�SH�R�! H��t!H�8H�X���H�=:�! �}��H�.�! ��[�ATU��b S������b �����W�A ��b �����z�A I�Ŀ�b ����M��H��t3���H��tH���U�����L���J������A �ÿ@b ���������0H��u���A 1�����H���������A �ÿ@b ��������H���;���[]A\���A �@b �r���P�@b �����Z�@b �����AWAVAUATUSH��  �=)�!  t
�9�!     H�=Q�!  �եA � +b u��+b �)����=,�! H��~�	�! H�ƿ�A 1�����A�A � b ������   H��H���R���H��uH��u�=��!  �  �H�Ã=��!  tH��u
��A �����=��!  t�2�A 1�����H��u�U�A 1��y���H��$�   H����B  ��y�����8����H��H�¿QuA 1��y���L��$�   L����W��H�|$D!�����ƹ   �Jg��L��$�   L����W����$�   �� �  �� `  u��D��tH�޿x�A 1������1�1�H���A����A��y
H�޿��A �1Ҿ�  �����H=�  tH�޿��A 1��ծ��H�t$@�@   D�����H��@t
H�޿��A ��D�����1�H���H���=��! H��D�l�~A�uп��A ���H�T$@1�H�r@�z����H�����H��H9�u���~}H�\$DE1�A��1�;�`���H��I��tTE��A��A���=�!  tH���A 1������ɜ!     �|$E9�A�GA�W	@��u����щ�D���#���A��H��A��u�H��  []A\A]A^A_�AVAU��qA ATU�@b SH���   ����H�t$@H��I����@  ��y�����8����L��H�¿QuA 1��y���H�\$hH����U��H�|$!؃���ƹ   �Ne��H�l$hH����U���ЉËD$X!�% �  = `  u	��t��~L��7�A 1��������b ��!    ���g�����b ���4����2�A ��b �����H��H����   1�H���H���H��H��H��v@�_   H���_��H��I��t3L�p�W�A L��������A��t*�z�A L��������t�E1�E1��E1�V�A 1��=���A�$ L�%1�! M��tI�<$H�������tM�d$�俪�A 1��	���E��A�D$	A�T$t����щ��|$�s@���L����۹A ��b �}�����t3�|$1���   �%����ٹA ��b �V�����t���A 1������ٹA ��b �7�����t�|$��1ɺ�   �������qA �@b �j���H���   []A\A]A^�P�@b ������F�!     �@b Z����P����   ���A ���������   ���A ���������   ���A ��������   �:�A ��������   ���A ��������   ���A ����Y����   ���A �p���AUAT���A USH��H��A�   H��  H���x   HD�H���)��H��u)�X   H�����H��u�2   H��E1����H��A��1��   H��D	%>�! �������y�
���8���H��H�¿
�A �%H����=  ��y�
���8�|��H��H�¿�A 1��$����D$% �  = `  t�=ߘ!  u
H�޿+�A �L�d$(L���tR��H�L!�I9�tH�޿A�A 1��۩��L��$�   �   ��L�����H=   t��	���8����H��H�¿qA �u����WA ��!b E1��r���H��A��u�WA ��!b �Z����L$(D��H��I��L��������=$�!  �$6b �4b ��  L��fǄ$�  U�HE��=�!  �tK�WA ��!b Ǆ$H      fǄ$L    fǄ$F    �����H��t<�   1�H�������$H  �$��$H   u�|$(貓��fǄ$L  �ɉ�$H  1�1����{
��H��t�����8����H��H�¿z�A �i����=w�!  u3�   L����	��H=   t����8���H��H�¿qA �-������G
���=4�!  ��A �@tA ���A H��HE�1��	��1��<��AWAV1�AUATI��US��1�I��I��H��(  M���4����y
L�����A �H��$�   �ǉ��5;  ��yL�����A 1��̧����$�   % �  = `  t
L�����A ��H��$�   H�$Hc$H��H�T$�P����H�T$u
L�����A �H����O���Ѕ$u�H�t$,��$   �	��H��$��A ��  H�|$2�   �cA ������u�|$/u	�۸?   ��۸   D؉�1Ҿ�  ����H���#�A ��  H�t$P��@   �G	��H��@���A �g  H�t$*�   ���'	��H��u	f�|$*U�t
�g�A �=  M��t:1҉ﾸ  �k��H���0�A �  ��   L������H���D�A ��   ��~i��  E1�������@�փ�@��t��uE��u
D�������
���A ��   M��tI�$I�������H��I��H=�  )$AE�u��E1�������   �$    A�   �?H�t$*�   ���3��H����   f�|$*U�ux�D$d����uq�D$h�$��o��E����   �$1҉�D�H��	H�  H��H�D$�
��H��y�ӼA 1��t���H�t$P�@   �����H��@�k�����A �׿�A ��<t�E1��(T$PM��I�EAU tI��H�L$I�L$�A��I���e�����~M��A�E tI�$    �A�   ������H��(  D��[]A\A]A^A_�AWAV�?   AUATUSH��H��H��  �5��! L�D$H��$  ��E�1��{���H��A��uCH��$  1�D9�}H���R�x� t�H�޿W�A 1������H�޿]�A 1�����1��l	��H���^�������uA9�}D��H��~�A 1��0������@��D$tH����A H����   ��   1��   H���3������xH��$  E1�E1�A��   �1�"���8�	��H��H�¿�A 1��ã���=��!  tXA��I��H��E9�~eD9t$�    AD׀{ t�:t�A�v����A 1����J�t�1҉����H��y����A 1��b����   H�މ��Y��H��t����A �݉��5��E��t�=�!  �@tA �#nA ���A HE������$�A ��������AWAV�@b AUATUSH��H�V����@b �&���H�ٵ! �i   H���L���r   H��H�D$�:���k   H��H�D$�(���a   H��H�D$ ����R   H��H�D$(���H�|$ H�D$0��H�|$ ��	�H�|$  ���u$H�|$( u1�H�|$0 �   ��(�! ��  �`VA � +b �����/   H��H�D$�����?�A H��H�ÿ b H��������H��t�?�A � b �����H���	H��HD\$H�=ʹ!  uH���Σ��H���! �9�A � b ������A ��!b I�������=��! H��~H��H�ڿ��A 1����H��t=H��H�������tM��t)H��L�������u�=N�! ~
���A �:��H�-3�! ���A ��b �"���H��I��u���A ��!b ����I�ž�A ��!b �������A H��I�ƿ�b �Q�A LD������H��H��u��A ��!b �����H�ž|�A ��b �����ZA ��b H�$����H��I��u�ZA ��!b ����I��H���! H��H��H�T$8�� ����t!M����   H�T$8L��H��� ������   H�|$ t
H�|$�9��H�|$ tM��X�A IE�� ��H�|$  tL�����H�|$( tHH��uH�<$ ���A tH����H�<$ ��8�tH�<$H��HE��� ���H�$H����A 1��`��H�|$0 tM��u�A IE�� ���=��!  tH�=��! H��HD=��! � ��1����H��H� +b []A\A]A^A_�����P� b �������b ������ b ���!     ���!     ����Z� +b �����=+�! SH��H�=(�! H�5!�! ~H��1�H�����A � ��H�=�! �D   �| ��1�H���ֱ! tH��! @tA � +b �C���� +b ������t��dA 1������=��!  t&H���! H��tH�=��! H��HD�����1����H�޿��A 1�艞��SH�O�! ��A �]���H��u[�!�A �M����K	�S1�H�3�E�A �����H�[H��u�[�US�d�A R1���,b �[�A ����H�3H��t!H�SH�K�k�A H��HD�1�H�� ������X[]�US��1�H��hH�T$H�4$1�
H��H��u��u��}�A 1��R����  H�|$�`�A �~����T$H�|$���A 1������D�D$�D$H�|$ �L$���A D��A��?���   ��1��v��D�D$�D$H�|$@�L$���A D��A��?���   ��1��F���$���u�D$*���tH�|$���A 1��!�����A H�H��H��t�H8�t
N	H��8�u��D$H�H�T$�D$��A P�D$P1�L�L$PL�D$0H�L$$�L���XZH��h[]�AUATUS�   H��  �=n�!  u1ۃ=��!  �Ã=}�! L�D$�    ��H��$  H�T$LN���E1��?�?����t$����A�ĺ@,b ���A 1�A	������1��XH��H��  H��  ���%���HcÃ�u�E��u"�=��! ~�
   L�d$1��#���A�   �<L��$  I��A�|$4 t�D�kHc�H��H��  H��  D��D��������9�}&I�$�ÿ��A ��I��H�I��I�T$���1�������H��  []A\A]Ã=<�!  A��A��uH��H�=&�! ��1����A �0����AWAVA��AUATA��US1�A�ι   ��H��(E��D�͋T$`H�|$��tH�|$��A � ��L�L$D��D���A E��D��1��~����޹�A ��  ���?B v��1�H����1���
��������  v5��  ��1����
   �Ɖ�1�����uH����I�¿R�A 1��������`�A 1�����A� ʚ;��  D9�sA��vD��1���A�����1Ҿ6A A�����b A���b A��  �Ӊ�1��>���D���  1���A��E��t1I��A�}  u���1Ҿi�A A��L��Ӊ�1�����D��1�A��A���ʿo�A 1����b �h���@���}�A u���A 1��Q����
   �����H��([]A\A]A^A_�USQ��
! ����  1�1��N�A ���������y��
!    �   �  1Ҿ   ���1���=   u׺ 
  ���b ������H= 
  u����:����   ���A ���b ��!     ���������t�
!    �   �(  �$�! ��f��v��	!    �   �  �5�! ��z���=z	  v��	!    �   ��   �-Ѭ! ��������b 蔜��9�t��	!    �   �   f�=��! u<���! H�|�! ��b H�i�! ��b <vy<H�P�! ��b tjH�3�! �b �]~[H�m�! �^�! H��b H�4�! H�T�! H��b ��H��! v&H�H��H���! H�HH��! tH��H�ԫ! ��!     ��Z[]�S���$�����u��! 9�|9�`�����A t�����A t�����A ���A HD��ȿ��A ���A HD����u���A ���A 1�������   ������A t��[�AWAVAUATUS���   H��H���h�����t1��Q���A���U�! 9�vH�K�! ��H��H����b �v���   uH�-�! H����b H�M�! �VwA�   �   ��! ��9�s����! 9�w�D�m�J�<� �b  t
J�� �b ��}�H���H�����t�A���  1��
   H�߃��v�E�H�JH�� �b �Bu�����C�y���<u�B�J��ȉ�Bu�z u	f�Bf��uD�bA���O  f�z
��A�@   ��?f����H��DE���E��D�kD�q�����   �4�    ��D�sE��	�A�CA��9s���@�{H�C    ��  ��! ��t?9�w;1�f�=ѩ! ��H�5ө! �������A@��ȅ�H����b H�Ct�@��C �Buf�zU�uf�B�C�B�C�CD�E�uf�=s�! ��   �E�L�<� �b A�GI�W H�� �b ��   A� ��   A�G��   E;ouE;wtv��! ��~l�=��!  t��~^E��A���b uQ1���3�A D�D$L�$衕���K�S���A �s�;���A�OA�W���A A�w�%���L�$D�D$A���b A�GA�GA�G;v��I�GH9�~�E��A���b uA��   u��A 1��"���A��@uZ1�����A �����Ct*�=�!  u=�=�!  �VA �)�A �+�A HE�1������Ă! �! u��S�A 1����A���b H��D��[]A\A]A^A_�ATU1�SH��0D�e��H�t$���W�����uP���   u#�t$�@tA �oVA ���A @��HD�1�����P�D$0��PD�L$)D�D$$�L$ �T$�t$����ZY��A9�u��퀁�   u�H��0[]A\�SH��0�Q���H�t$�ǉ��������u'P�D$0��PD�L$)D�D$$�L$ �T$�t$����ZY��޿��A 1�����H��0[�AWAV�   AUATUSH��x�������t1���������A 1۽   E1�����D���   H�t$D���F�������   D�|$(D��A��D��D�|�0�b}��1҅��   ��A	ԅ�t�T$(1�A9�~1�9T�0@��H��!���!��@tA ��A�0VA ���A D��LE������A HD�D��1�H������H���`�������A �(VA HE���A 1�����E��t
��A �������u
���A ������
   � ���H��x[]A\A]A^A_�ATU�   S�������t1������H���! �h���  u� ,b �;�A 1��������  � ,b �F�A )�1���������T�A ��
1��ځ�   ���������� �   A�ܿ
   �  �������	A)ĸ �  A��$ ������� �  O��<���� |  � |  �}�A 1�����D��D��1������A 1��o�����ى�������A []A\)�1��R���Q���������u'f�=դ! ~H���! �P�Јɣ! f�����! ��ZÃ={! S~
�.�A �f����=��   ��   ��������   �5�! ������b ���8����N�A �X�! �   1��l������ÿ<�A x1Ҿ   �������H=   t
�W�A ����� 
  ���b ��� ���H= 
  u݉�������=�~! ~
�_�A �����$�      1�[�ATUS����A�ă��E���B  �-Σ! 1ۅ���  �=�~! ~
�w�A �t���H���! ��P�p�@���! ���! �����5��! ���! u�}�!    �   �  ��O�   ��  ��u
�   �  �=~! ~
���A �����H��! �xw��@�=�}! �1�! ~
���A �����H�ڢ! �xu?�=�}! 	�@�   DM�D�������ȃ�w�$ŀ�A �   ��   ��   �1�   ��   ����   ����   H�=e�!  t�=\}! ~
���A �H���H�I�! H��tD�8�'�!    t��!    �)f�x4uf�x!Ct
���!    f�x�Vt��! �=�|! ~
���A �����H�-ޡ! �   f�} OuJH�u�   ���A ������u3f�}Ou,f�E��f��uf�}
O�   uf�E1ۃ�f���Ã��=�|! ��~'D���! ���! ���A ���! �5��! 1��������[]A\�S�   ������t1��k�������H��X�A H�4�`�A H��1�������~��u�=`�!  �f�A �A��tA���A �������~2���A ��������A �������t���A �������t
���A �������! ��t<�=�{!  �t/��)�A u���A u�Ⱦ:�A �G�A HD�[��A 1�����[�AWAVAUATUSH��P�=h{!  
�
   ����A��,b H���E1�E1�I�7H��tIH��D��H���H��H��H�Q�HcҀ|�=L�4ME�������uL��A�W�
   �=���1��$I�� 믿8�A ����������
   �����   � ���H��8�/�����t�   �'H�t$��   �d�����u�ߟ! �D$����9�u�H��8�AWAVA��AUATUSH��H��8  �������t����H  �=iz! ~D���Y�A 1������Mc�L����3����t�E1�A��   ����j�! A9�H�t$ D���������tA��uH�&�D$,9Eu�D$(9Eu�D$$9EuA��D��A��뵃=�y! ��  �޿q�A 1��o����  L���\3��H��$�   A!�1�D���i���=�y! ��~H��$   D�����A 1��+���1҉߾�  �]���H=�  ���A uH�t$�   �������H��t���A 1��g����D$1҉߾�  �D$����H=�  ��A u�H�t$H�ߺ@   ����H��@�=�A u�H��$�   �Zk���=y! ~D��_�A 1�����A���E1�E1�D��A��A��tgH�t$ D���}����=�x! ~L�D$8�T$@�   D�濊�A 1��@���H�t$8H�|$H�@   �,�����uA��D��D$@9D$u���t�A��E��됃=mx! �1  A�jA A��A�@tA L��D����IDԿ��A 1�L�D$�����A��t7�=-x! ~"L�D$A��D��D�����A L��ID�1�����A�������D��H�t$ �������M��t;L$$u�E����   ;D$(��   �E�E��A�ċ�w! �w! uPD�k�Mc�A���b u?1��޿�A �y����M�U�[�A �u�����L$$�T$(�b�A �t$,�����A���b �D$ �t$$�L$(A9ĉuACĉM�΅�~1���E�] ���A���$����+���H��8  []A\A]A^A_Ã=�v!  uOR��v!    �C�����x:�,�! <�u�!�! �P���v"��t��v!    ��P���w��wv!    X�S�   ������������y���A �   �����;�ʚ! H���! �P���u���! �޿��A 1������v!     �G����v! �o�A ��t���i�A t���7�A �r�A HD�1����A �����=�u! vF��Hcúv�A H�4���A �1�1ҍC���w���}�A H�4���A �H��t�%�A 1��o���[�
   ����A���b ���b L�ڋB43B H��3B3B����B<H9�u�AWAV1�AUD�5=�! ATD�-8�! UD�%4�! S�-1�! E��,�! D��D��A��A��D��A��H�������b E1�A!���E1�D��B���y�ZD�H��PE��t
A��A�����A�0�b A���b D�ɉ�I��1���1�9���nAJLD����A��D�M9�A��t�։ȉ���A�4�b A���b I��M9�t:A��A��A	�A!�A!���E	�E���   F��ܼ�����A�։��ǉ�C��I��M9�t1E���   A����A1�A1�F����bʉ���A��։��ǉ�C���D�D�D��މ�! [��! �=�! ]��! �5�! A\A]A^A_�Hc�1�H��9�~����b ʉ���b H��������! #Eg���! �������! �ܺ����! vT2���! �������!     �w�!     Ëp�! AVAUI��ATUS��ǃ�?�s�X�! �N�! �@   A��A)�D9�|1Hc�L��D��H����b Mc�D)�M�H���@   �6�������1��ą�tHc�Hc�L��H����b H���[]A\A]A^Ë�! S��?�pH�ƀ��b ���8Hc�~3���b �@   1�H�)�H���@   ������ ����   1�H����H����b �8   1�)�H���8   �����u�! �s�! [��������! �ʉ��! �����AUA�@tA AT@��UA��S���A ��L���A�   PHE͉�f��fA��D��H�����A ��P1��������A��A��ID�   ��f��f��AXH�꿻�A []A\A]��1�������R���A � ����5��! ���A 1������5��! 1���A �z���f�=v�! ~N�q�! ���A �@tA A�   �ȨHE���f��fA��H���@�A ��1��5����5N�! ���A 1��"�����! �5�! �?�A X�����ATUA��S��1��։�H����-b �[�A �����fA9�u��-b �{�A 1�����������-b ���A 1�����1����A ����fA9�u[]A\�;�A �������:�A 1�[]A\����US1�H��  H�=�e! ����Hc�������
tH���  w�H����H���, 蹃��H��  []�AWAVAUATI��US1�H��H�F�.D�~H�|$�
   �l$4�D$�D$8D�|$<�����D�4H�|$$���A A�މD$��1��_�����u;l$A�.�A tA��uD9�A�;�A tL�L$$���! H��p�A ���A L�ݐ�A H�t$�H�1����������I�ń�uD�t$�j�T$�����H�T$H� ����TuH��uE�4$�CA��u��N��H�t$(1�L������H�L$(A��I9�t;�! s�9 t���A D�t$�o���fE�4\L������H��u;l$uD�t$8D9�uD�t$<H��H�������H��H[]A\A]A^A_�AWAVA��AUATI��US�   ��H�� ��E�$��P   ���ƃ�E�D��AQA��E)�D����E��A��Ҹ��A �@tA HD�PAPA��D��H��1����A �T���H�� ������8 I��uA�$�rH�t$1�H��������H�D$I9�tL�8E��t����H� B�<�Pt���A A�$�Z����e���H�T$H� H��<�Pt����D9�~���A A�$�*���fA�$L���M���H��[]A\A]A^A_����! ���! �5��! S�����A �������! ���! ��A �5��! �d�����t*f�=}�!  x �r�! �i�! ��A �5[�! [�6���[�f�=Q�!  x9P�E�! ��A �7�! �5.�! �
����(�! �5#�! ��A Y������0�A �P���AUAT��US1�H��A�պ   H��D�H���I�A ������:����8 I��t0H�t$1�H����������~A9�|
H�D$�8 t���A 1������+L������f�+H��[]A\A]�AUATI��USQ�N   L��^�A 1�1��P��������H�(I��@��t����H� �   ����Yt
1ۃ�N���L��������t�Z��[]A\A]�AWAVI��AUAT1�USA��H��1�I��H��(����#����   L��D������H����  fA�>BM�   ��  H�t$�   D���v���H��t�����  f�D$f��uiH�t$�
   D���K���H��
H��u�1�H�ߋT$��D$A�   f�S�C�D$�Cf�D$f�C����k$�k A�FA+F
�(   �C�7f��(�   �F  H�s�&   D�������H��&�Z����D$A�   ����A �   L���   �   �K���C�������P�=   ���! ���  ��   �@�b 1�Ic�Hc��! 9�}3H��H��D��H�L$�R���H�L$H9������A��u�C ��H����IcV
H��f   H9�t�   1�D������1�&�! �iH�t$�   D�������H���|���f�|$0�   u@I�u�.   D�������H��.�T����D$I�}�   �cA A�E ������t��   H��(��[]A\A]A^A_�SH�=��! 1�H���H��������|��H��H���������A H�������H�=[�! H�\�! 1�1��#������?�! �u�A x'H�==�! 1���  �A   ���������! y
���A �z��H�=�! �  �=��! �H�b �@�b �h�b �	����=si! ��~�ƿ��A 1��������y"�����8����H�5��! H�¿��A 1��Mz���˃�wL�$�@�A H�5��! ���A �0���! ���! ���A H�5u�! ��1��z��H�5d�! ��A 1���y��[�AWAVA��AUATI��USH�͉��   L��H��  �IA�   L�$E1���E��A�������(   H�������Ic־@�b ��H������L�$�0   ��L������Hc5�! 1�D���3���H�t$�   D��������~.Lc�H�t$��L��L�$H�D$�B���L�$L9�uH�L$A�뼅�t�G�A ���������DB��f   D�m1�1���A�D$
D�A�D$�����   L���������(   H��������1�H��  []A\A]A^A_Å�S��t!�5�! �=�! A�H�b �@�b �h�b �����=�! �����=ۘ! �v���H�=ߘ! �
  ��t	�=Sg!  t�=Ng! ![H�=��! �����[H�5��! H�=��! ����[�AWAV�.   AUATUSH��P�����H��uH��j�A �o�A �t�A 1��x���j�A H��H����������  ����H���H����=�f! ~�ƿ��A 1��O�����b ������=�f! ��~�ƿ��A 1��,�����tH����A �  �R�A ��b �j���H��H��tw�/   H��A�[�A ����H��I����   �;/��   H����@ H��1�H���H��H��H��H���H��H�Ѝ|���x��H��H�������H��H�������A�E/H���Y�.   H������H��I��t�  1�H���H���A�a�A H�эy�x��H��H��H�������o�A H������M��tA�E .H��H����A 1��"������A ��������   �=qe!  ~H��L���A 1������H���/�����A ��b �<���� �b H���7����<�A ��b � ���� �b H���������A ��b ����� �b H�������   �K���1������o�A H��������H����  ��A A�   �`���H�����������C�A ����1������ ����Q�A 1��1�������I������I�U H��H� ����Q�5  ��Ctq��L�x  �<  ��T�y  ��W�  �%  ��A 1�������I���H�I��H�����Ht|bE1���B��   L���8����
   �>���E����  �
   �+����   �����1����A �u���f�=��!  x����A 1��_����y�����Nt��Tt�3�Z�b ���A � �`�b ���A �f�=J�!  x�f�b ���A ���������A 1�����A�   �T����   �T�b ��A � ����   �V�b �-�A �����f�=ؓ! A�   ~,�   �X�b �@�A 1���������! �p�b �M�A ����L���(����
   �.���E����  ��������A 1��t��������H�I��H�����D�U�����PtE1���Bt����A 1��@����2�   �   �R�b �]�A �Y����   �   �P�b �n�A �@���A�   �a����������A 1������f�=�!  ���A y���A 1��������A 1�������=���I�Ƌג! H�I�f������   ��C��   DE1���B��   L�������
   ����E����  f�=��!  �g����{�A �����X�����DtJ��Pum�   �   �n�b ���A �j����   �   �l�b ���A �Q����E�f�b ���A ������4f-�y�f��! �%E1���B�^�����Euf�x��޿��A 1������A�   �:������A �Q�������  H���$t���.   H��H�������H�߾j�A �  �����H�߾y�A �T���H��H��u
���A ��q��H�ƿ�A ����1�H��0�A H�������U�! D�e�! ���  ��VA �/�! D�-�! D�5#�! ���  D��A�VA f��! ���  �йVA AWAR1�WVH��ASAV�=�A �-������! H��01��b�A H�������Ȑ! f;��! t��tA H��1������H�޿,   �������! f;��! t��tA H��1������H�޿;   �{����t�! 1��o�A H�������`�! f;W�! t��tA H��1�����H�޿,   �9����6�! f;+�! t��tA H��1��Z���H�޿
   ����H�޿s�A �@���D��! fE��yH�޿��A �%����   A���5ۏ! A�VA ufA��A�@tA E��A��f�! ��i  �йVA PV1����A H����������! f;��! Y^t��tA H��1�����H�޿,   �e����h�! f;]�! t��tA H��1�����H�޿
   �9���H����������A 1���������tcH��A 1������1��=Z^!  @�������=J^!  t9���A �:����-���A 1��\�������t1��z�������A 1������   L���3����
   �9������9����������A 1���n���¿@tA f��fA�����4����¹   A�@tA f��f���D�@�>����¹@tA f��fA����P�=����¹@tA f��fA����P����USH��P�   �7p��H��H���sp��H�H��! H��! H�CZ[]�ATUA�x�b SH���! H��H��t5H�3H���������uH�CI�$H�;�?���H��[]A\�3���L�cH�[��H����A 1��n��SH���! H��t}H�8H�X������y'�(����8�!���H��H��! ��A H�01��n����=�\! ~H�^�! �!�A H�01��'���H�H�! H�8����H�=9�! ����H�-�! �w���[�f.�     @ AWAVA��AUATL�%��  UH�-��  SI��I��L)�H��H�������H��t 1��     L��L��D��A��H��H9�u�H��[]A\A]A^A_Ðf.�     ��f.�     @ H�!�  H��tH�1�����f.�     1�1��w����    H��H���   �����H����   �a����H��H�L$H�T$��H��1�����H��ÐH���  H���t(UH��SH���  H�� H����H�H���u�H��[]�� H������H���            usage: %s [ -C config_file ] -q [ -m map_file ] [ -v N | -v ... ]
 %7s%s [ -C config_file ] [ -b boot_device ] [ -c ] [ -g | -l | -L ]
 %12s[ -F ] [ -i boot_loader ] [ -m map_file ] [ -d delay ]
 %12s[ -v N | -v ... ] [ -t ] [ -s save_file | -S save_file ]
 %12s[ -p ][ -P fix | -P ignore ] [ -r root_dir ] [ -w | -w+ ]
 %7s%s [ -C config_file ] [ -m map_file ] -R [ word ... ]
 %7s%s [ -C config_file ] -I name [ options ]
 %7s%s [ -C config_file ] [ -s save_file ] -u | -U [ boot_device ]
 %7s%s -H				install only to active discs (RAID-1)
 %7s%s -A /dev/XXX [ N ]		inquire/activate a partition
 %7s%s -M /dev/XXX [ mbr | ext ]	install master boot record
 %7s%s -T help 			list additional options
 %7s%s -X				internal compile-time options
 %7s%s -V [ -v ]			version information

 1=0x%x
 2=0x%x
 3=0x%x
 B=0x%x
 C=0x%x
 M=0x%x
 N=0x%x

 
CFLAGS =  -Os -Wall -DHAS_VERSION_H -DHAS_LIBDEVMAPPER_H -DLILO=0xbb920890 -DLCF_BDATA -DLCF_DSECS=3 -DLCF_EVMS -DLCF_IGNORECASE -DLCF_LVM -DLCF_NOKEYBOARD -DLCF_ONE_SHOT -DLCF_PASS160 -DLCF_REISERFS -DLCF_REWRITE_TABLE -DLCF_SOLO_CHAIN -DLCF_VERSION -DLCF_VIRTUAL -DLCF_MDPRAID -DLCF_DEVMAPPER  With  device-mapper 
glibc version %d.%d
 Kernel Headers included from  %d.%d.%d
 Maximum Major Device = %d
 MAX_IMAGES = %d		c=%d, s=%d, i=%d, l=%d, ll=%d, f=%d, d=%d, ld=%d
 IMAGE_DESCR = %d   DESCR_SECTORS = %d

 geometric linear /boot/map LINEAR no linear/lba32 No u No   NOT Non- WILL will not specifying options booting this image won't No s suppress issu /etc/lilo.conf atexit(sync) atexit(purge) AbBCdDEfiImMPrsSTxZ cFglLpqtVXz compact delay install fix fix-table ignore ignore-table force-backup nowarn raid-extra-boot bios-passes-dl ROOT /proc/partitions chroot %s: %s root at %s has no /dev directory chdir /: %s atexit() failed LILO version %d.%d%s  (test mode) 22-November-2015  (released %s)
   * Copyright (C) 1992-1998 Werner Almesberger  (until v20)
  * Copyright (C) 1999-2007 John Coffman  (until v22)
  * Copyright (C) 2009-2015 Joachim Wiedorn  (since v23)
This program comes with ABSOLUTELY NO WARRANTY. This is free software 
distributed under the BSD License (3-clause). Details can be found in 
the file COPYING, which is distributed with this software. Running %s kernel %s on %s
 Only one of '-g', '-l', or '-L' may be specified chrul ebda main: cfg_parse returns %d
 fstat %s: %s %s should be owned by root %s should be writable only for root nodevcache verbose May specify only one of GEOMETRIC, LINEAR or LBA32 Ignoring entry '%s' LBA32 addressing assumed LINEAR is deprecated in favor of LBA32:  LINEAR specifies 24-bit
  disk addresses below the 1024 cylinder limit; LBA32 specifies 32-bit disk
  addresses not subject to cylinder limits on systems with EDD-BIOS extensions;
  use LINEAR only if you are aware of its limitations. YyTt1 NnFf0 COMPACT may conflict with %s on some systems read cmdline %s: %s read descrs %s: %s lseek over zero sector %s: %s read second params %s: %s lseek keytable %s: %s read keytable %s: %s Warning: mapfile created with %s option
 Cannot undo boot sector relocation. Cannot recognize boot sector. Installed:  %s
 Global settings:   Delay before booting: %d.%d seconds
   No command-line timeout   Command-line timeout: %d.%d seconds
   %snattended booting
   %sPC/AT keyboard hardware prescence check
   Always enter boot prompt   Enter boot prompt only on demand   Boot-time BIOS data%s saved
   Boot-time BIOS data auto-suppress write%s bypassed
   Large memory (>15M) is%s used to load initial ramdisk
   %sRAID installation
   Boot device %s be used for the Map file
   Serial line access is disabled   Boot prompt can be accessed from COM%d
   No message for boot prompt   Boot prompt message is %d bytes
   Bitmap file is %d paragraphs (%d bytes)
   No default boot command line   Default boot command line: "%s"
 Serial numbers %08X
 Images: %s%-15s %s%s%s  <dev=0x%02x,%s=%d>  <dev=0x%02x,hd=%d,cyl=%d,sct=%d>     Virtual Boot is disabled     Warn on Virtual boot     NoKeyboard Boot is disabled     No password     Password is required for %s
     Boot command-line %s be locked
     %single-key activation
     VGA mode is taken from boot image     VGA mode:  NORMAL EXTENDED ASK %d (0x%04x)
     Kernel is loaded "low"     Kernel is loaded "high"     No initial RAM disk     Initial RAM disk is %d bytes
        and is too big to fit between 4M-15M     Map sector not found Read on map file failed (access conflict ?) 2     Fallback sector not found Read on map file failed (access conflict ?) 3     No fallback     Fallback: "%s"
     Options sector not found Read on map file failed (access conflict ?) 4     Options: "%s"
     No options Read on map file failed (access conflict ?) 1 LILO     Pre-21 signature (0x%02x,0x%02x,0x%02x,0x%02x)
     Bad signature (0x%02x,0x%02x,0x%02x,0x%02x)
     Master-Boot:  This BIOS drive will always appear as 0x80 (or 0x00)     Boot-As:  This BIOS drive will always appear as 0x%02X
     BIOS drive 0x%02X is mapped to 0x%02X
     BIOS drive 0x%02x, offset 0x%x: 0x%02x -> 0x%02x
     Image data not found Checksum error
 raid_setup returns offset = %08X  ndisk = %d
 raid flags: at bsect_open  0x%02X
 Syntax error No images have been defined. Default image doesn't exist. Writing boot sector. The password crc file has *NOT* been updated. The boot sector and the map file have *NOT* been altered. %d warnings were  One warning was  %sed.
 M$@     �$@     �$@     �$@     �$@     %@     }-@     %@     :%@     }-@     }-@     {%@     �%@     }-@     }-@     �%@     }-@     }&@     ,'@     C$@     R'@     l(@     }-@     K(@     }-@     ](@     }-@     }-@     }-@     }-@     }-@     }-@     }-@     r$@     �$@     �$@     }-@     �$@     %@     }-@     +%@     }-@     }-@     o%@     �%@     }-@     }-@     �%@     n&@     v(@     '@     ;'@     J'@     �'@     (@     <(@     }-@     U(@     is_primary:  Not a valid device  0x%04X master:  Not a valid device  0x%04X is_accessible:  Not a valid device  0x%04X raid_setup: stat("%s") raid_setup: dev=%04X  rdev=%04X
 Not a RAID install, 'raid-extra-boot=' not allowed RAID1 install implied by 'boot=/'
 Unable to open %s Unable to stat %s %s is not a block device Unable to get RAID version on %s RAID_VERSION = %d.%d
 Raid major versions > 0 are not supported Raid versions < 0.90 are not supported Unable to get RAID info on %s GET_ARRAY_INFO version = %d.%d
 Incompatible Raid version information on %s   (RV=%d.%d GAI=%d.%d) Only RAID1 devices are supported as boot devices RAID install requires LBA32 or LINEAR; LBA32 assumed.
 auto mbr-only mbr RAID info:  nr=%d, raid=%d, active=%d, working=%d, failed=%d, spare=%d
 Not all RAID-1 disks are active; use '-H' to install to active disks only Partial RAID-1 install on active disks only; booting is not failsafe
 raid: GET_DISK_INFO: %s, pass=%d md: RAIDset device %d = 0x%04X
 Faulty disk in RAID-1 array; boot with caution!! disk %s marked as faulty, skipping
 RAID scan: geo_get: returns geo->device = 0x%02X for device %04X
 disk->start = %d		raid_offset = %d (%08X)
 %s (%04X) not a block device RAID list: %s is device 0x%04X
 Cannot write to a partition within a RAID set:  %s Warning: device outside of RAID set  %s  0x%04X
 Unusual RAID bios device code: 0x%02X Using BIOS device code 0x%02X for RAID boot blocks
 Boot sector on  %s  will depend upon the BIOS device code
  passed in the DL register being accurate.  Install Master Boot Records
  with the 'lilo -M' command, and activate the RAID1 partitions with the
  'lilo -A' command. MD_MIXED MD_PARALLEL MD_SKEWED  *NOT* Ex Im do_md_install: %s
   offset %08X  %s
 The map file has *NOT* been altered. The Master boot record of  %s  has%s been updated.
 The map file has *NOT* been updated. The boot record of  %s  has%s been updated.
 Specified partition:  %s  raid offset = %08X
 %splicit AUTO does not allow updating the Master Boot Record
  of '%s' on BIOS device code 0x80, the System Master Boot Record.
  You must explicitly specify updating of this boot sector with
  '-x %s' or 'raid-extra-boot = %s' in the
  configuration file. More than %d active RAID1 disks RAID offset entry %d  0x%08X
 RAID device mask 0x%04X
 lseek map file write map file fdatasync map file Hole found in map file (alloc_page) map_patch_first: String is too long lseek %s: %s read %s: %s write %s: %s map_patch_first: Bad write ?!? close %s: %s No image "%s" is defined creat %s: %s map_create: cannot fstat map file map_create:  boot=%04X  map=%04X
 map file must be on the boot RAID partition Hole found in map file (zero sector) Hole found in map file (descr. sector %d) Hole found in map file (default command line) Map file size: %d bytes.
 lseek map file to end map_close: lseek map_close: write Hole found in map file (app. sector) Covering hole at sector %d.
 LBA Compaction removed %d BIOS call%s.
 Empty map section   Mapped AL=0x%02x CX=0x%04x DX=0x%04x , %s=%d Map segment is too big. Calling map_insert_file map_insert_file: file seek map_insert_file: file read map_insert_file: map write Map file positioning error Calling map_insert_data map_insert_data: map write /etc/disktab  	 0x%x 0x%x %d %d %d %d Invalid line in %s:
"%s" DISKTAB and DISK are mutually exclusive /proc/devices Block %d %31s
 device-mapper major = %d
 /dev/mapper/control Major Device (%d) > %d %s is not a valid partition device start Duplicate geometry definition for %s do_disk: stat %s: %s  '%s' is not a whole disk device bios sectors heads cylinders max-partitions Cannot alter 'max-partitions' for known disk  %s disk=%s:  illegal value for max-partitions(%d) Implementation restriction: max-partitions on major device > %d Must specify SECTORS and HEADS together INACCESSIBLE and BIOS are mutually exclusive No geometry variables allowed if INACCESSIBLE Duplicate "disk =" definition for %s do_disk: %s %04X 0x%02X  %d:%d:%d
 can't open LVM char device %s
 LVM_GET_IOP_VERSION failed on %s
 LVM IOP %d not supported for booting
 can't open LVM block device %#x
 LV_BMAP error or ioctl unsupported, can't have image in LVM.
 Can't open EVMS block device %s.
 EVMS_GET_IOCTL_VERSION failed on %s.
 EVMS ioctl version %d.%d.%d does not support booting.
 Can't open EVMS block device %#x
 EVMS_GET_BMAP error or ioctl unsupported. Can't have image on EVMS volume.
 /dev/evms/block_device geo_query_dev: device=%04X
 Trying to map files from unnamed device 0x%04x (NFS/RAID mirror down ?) Trying to map files from your RAM disk. Please check -r option or ROOT environment variable. geo_query_dev FDGETPRM (dev 0x%04x): %s geo_query_dev HDIO_GETGEO (dev 0x%04x): %s HDIO_REQ not supported for your SCSI controller. Please use a DISK section WARNING: SATA partition in the high region (>15): LILO needs the kernel in one of the first 15 SATA partitions. If  you need support for kernel in SATA partitions of the high region  than try grub2 for this purpose!  Sorry, cannot handle device 0x%04x HDIO_REQ not supported for your Disk controller. Please use a DISK section HDIO_REQ not supported for your DAC960/IBM controller. Please use a DISK section HDIO_REQ not supported for your Array controller. Please use a DISK section Linux experimental device 0x%04x needs to be defined.
Check 'man lilo.conf' under 'disk=' and 'max-partitions=' Sorry, don't know how to handle device 0x%04x exit geo_query_dev Device 0x%04X: Configured as inaccessible.
 device-mapper: readlink("%s") failed with: %s device-mapper: realpath("%s") failed with: %s device-mapper: dm_task_create(DM_DEVICE_TABLE) failed device-mapper: dm_task_set_major() or dm_task_set_minor() failed device-mapper: dm_task_run(DM_DEVICE_TABLE) failed device-mapper: only linear boot device supported %02x:%02x %lu device-mapper: parse error in linear params ("%s") %u:%u %lu /dev/%s device-mapper: %s is not a valid block device /sys/block/%s/dev device-mapper: "%s" could not be opened. /sys mounted? device-mapper: read error from "/sys/block/%s/dev" %u:%u %x device-mapper: error getting device from "%s" device-mapper: Error finding real device geo_get: device %04X, all=%d
 This version of LVM does not support boot LVs /dev/md%d /dev/md/%d Only RAID1 devices are supported for boot images GET_DISK_INFO: %s BIOS drive 0x%02x may not be accessible Device 0x%04x: BIOS drive 0x%02x, no geometry.
 Device 0x%04X: Got bad geometry %d/%d/%d
 Device 0x%04X: Maximum number of heads is %d, not %d
 Maximum number of heads = %d (as specified)
   exceeds standard BIOS maximum of 255. Device 0x%04X: Maximum number of sectors is %d, not %d
 Maximum number of heads = %d (as specified)
   exceeds standard BIOS maximum of 63. device 0x%04x exceeds %d cylinder limit.
   Use of the 'lba32' option may help on newer (EDD-BIOS) systems. Device 0x%04x: BIOS drive 0x%02x, %d heads, %d cylinders,
 %15s%d sectors. Partition offset: %d sectors.
 %s:BIOS syntax is no longer supported.
    Please use a DISK section. %s: neither a reg. file nor a block dev. FIGETBSZ %s: %s Incompatible block size: %d
 geo_open_boot: %s
 Internal error: sector > 0 after geo_open_boot Cannot unpack ReiserFS file fd %d: REISERFS_IOC_UNPACK
 Cannot unpack Reiser4 file fd %d: REISER4_IOC_UNPACK
 Cannot perform fdatasync fd %d: fdatasync()
 ioctl FIBMAP LVM boot LV cannot be on multiple PVs
 EVMS boot volume cannot be on multiple disks.
 device-mapper: Sector outside mapped device? (%d: %u/%lu) device-mapper: mapped boot device cannot be on multiple real devices
 LINEAR may generate cylinder# above 1023 at boot-time. Sector address %d too large for LINEAR (try LBA32 instead). fd %d: offset %d -> dev 0x%02x, %s %d
 BIOS device 0x%02x is inaccessible geo_comp_addr: Cylinder number is too big (%d > %d) geo_comp_addr: Cylinder %d beyond end of media (%d) fd %d: offset %d -> dev 0x%02x, head %d, track %d, sector %d
 device-mapper: Mapped device suddenly lost? (%d)   evms_bmap       lvm_bmap Boot image: %s HdrS Setup length is %d sector%s.
 Setup length exceeds %d maximum; kernel setup will overwrite boot loader Kernel %s is too big Can't load kernel at mis-aligned address 0x%08x
 Mapped %d sector%s.
 initrd Kernel doesn't support initial RAM disks Mapping RAM disk %s RAM disk: %d sector%s.
 large-memory small-memory The initial RAM disk will be loaded in the high memory above 16M. The initial RAM disk is TOO BIG to fit in the memory below 15M.
  It will be loaded in the high memory it will be 
  assumed that the BIOS supports memory moves above 16M. The initial RAM disk will be loaded in the low memory below 15M. Boot device: %s, range %s
 Invalid range map-drive Invalid drive specification "%s" TO is required Mapping 0x%02x to 0x%02x already exists Ambiguous mapping 0x%02x to 0x%02x or 0x%02x Too many drive mappings (more than %d)   Mapping BIOS drive 0x%02x to 0x%02x
 (NULL) Name: %s  yields MBR: %s  (with%s primary partition check)
 /boot/chain.b , on  0/0x80 unsafe CHAIN Boot other: %s%s%s, loader %s
 TABLE and UNSAFE are mutually incompatible. 'other = %s' specifies a file that is longer
    than a single sector. This file may actually be an 'image =' Can't get magic number of %s First sector of %s doesn't have a valid boot signature master-boot boot-as 'master-boot' and 'boot-as' are mutually exclusive 'other=' options 'master-boot' and 'boot-as' are mutually exclusive global options Radix error, 'boot-as=%d' taken to mean 'boot-as=0x%x' Illegal BIOS device code specified in 'boot-as=0x%02x'   Swapping BIOS boot drive with %s, as needed
 Chain loader %s is too big Pseudo partition start: %d
 Duplicate entry in partition table Partition entry not found. boot_other:  drive=0x%02x   logical=0x%02x
 Mapped %d (%d+1+1) sectors.
 /dev/.devfsd scan_dir: %s
 opendir %s: %s .udev fd cache_add: LILO internal error Caching device %s (0x%04X)
 [Y/n] [N/y] 

Reference:  disk "%s"  (%d,%d)  %04X

LILO wants to assign a new Volume ID to this disk drive.  However, changing
the Volume ID of a Windows NT, 2000, or XP boot disk is a fatal Windows error.
This caution does not apply to Windows 95 or 98, or to NT data disks.
 
Is the above disk an NT boot disk?  Aborting ...
 lookup_dev:  number=%04X
 stat /dev: %s /tmp/dev.%d mknod %s: %s Created temporary device %s (0x%04X)
 Cannot proceed. Maybe you need to add this to your lilo.conf:
	disk=%s inaccessible
(real error shown below)
 Failed to create a temporary device Removed temporary device %s (0x%04X)
 /dev/ide/host%d/bus%d/target%d/lun0/ part%d disc /dev/loop/%d /dev/loop%d /dev/floppy/0 /dev/floppy/1 /dev/fd0 /dev/fd1 /dev/hdt /dev/hds /dev/hdr /dev/hdq /dev/hdp /dev/hdo /dev/hdn /dev/hdm /dev/hdl /dev/hdk /dev/hdj /dev/hdi /dev/sda /dev/hdh /dev/hdg /dev/hdf /dev/hde /dev/hdd /dev/hdc /dev/hdb /dev/hda %s/%s.%04X make_backup: %s not a directory or regular file %s exists - no %s backup copy made.
 Backup copy of %s has already been made in %s
 Backup copy of %s in %s
 Backup copy of %s in %s (test mode)
 /boot/%s.%04X VolumeID set/get bad device %04X
 VolumeID read error: sector 0 of %s not readable master disk volume ID record volid write error /dev/urandom static-bios-codes registering bios=0x%02X  device=0x%04X
 master boot record seek %04X: %s read master boot record %04X: %s Volume ID generation error Assigning new Volume ID to (%04X) '%s'  ID = %08X
 master boot record2 seek %04X: %s write master boot record %04X: %s register_bios: device code duplicated: %04X register_bios: volume ID serial no. duplicated: %08X Bios device code 0x%02X is being used by two disks
	%s (0x%04X)  and  %s (0x%04X) Using Volume ID %08X on bios %02X
  BIOS   VolumeID   Device   %02X    %08X    %04X
 
    The kernel was compiled with DEVFS_FS, but 'devfs=mount' was omitted
        as a kernel command-line boot parameter; hence, the '/dev' directory
        structure does not reflect DEVFS_FS device names. 
    The kernel was compiled without DEVFS, but the '/dev' directory structure
        implements the DEVFS filesystem. '/proc/partitions' does not exist, disk scan bypassed /proc/partitions references Experimental major device %d. /proc/partitions references Reserved device 255. /dev/ pf_hard_disk_scan: (%d,%d) %s
 '/proc/partitions' does not match '/dev' directory structure.
    Name change: '%s' -> '%s'%s Name change: '%s' -> '%s' '/dev' directory structure is incomplete; device (%d, %d) is missing. bypassing VolumeID scan of drive flagged INACCESSIBLE:  %s More than %d hard disks are listed in '/proc/partitions'.
    Disks beyond the %dth must be marked:
        disk=/dev/XXXX  inaccessible
    in the configuration file (/etc/lilo.conf).
 pf:  dev=%04X  id=%08X  name=%s
 Disks '%s' and '%s' are both assigned 'bios=0x%02X' Hard disk '%s' bios= specification out of the range [0x80..0x%02X] NT partition: %s %d %s
   %04X  %08X  %s
 pf_hard_disk_scan: ndevs=%d
 MDP-RAID detected,   k=%d
 noraid RAID controller present, with "noraid" keyword used.
    Underlying drives individually must be marked INACCESSIBLE. is_mdp:   %04X : %04X
 RAID versions other than 0.90 are not supported is_mdp: returns %d
 (MDP-RAID driver) the kernel does not support underlying
    device inquiries.  Each underlying drive of  %s  must
    individually be marked INACCESSIBLE. (MDP-RAID) underlying device flagged INACCESSIBLE: %s bypassing VolumeID check of underlying MDP-RAID drive:
	%04X  %08X  %s Resolve invalid VolumeIDs Resolve duplicate VolumeIDs Duplicated VolumeID's will be overwritten;
   With RAID present, this may defeat all boot redundancy.
   Underlying RAID-1 drives should be marked INACCESSIBLE.
   Check 'man lilo.conf' under 'disk=', 'inaccessible' option. device codes (user assigned pf) = %X
 BIOS code %02X is too big (device %04X) Devices %04X and %04X are assigned to BIOS 0x%02X device codes (user assigned) = %X
 device codes (BIOS assigned) = %X
 Filling in '%s' = 0x%02X
 Internal implementation restriction. Boot may occur from the first
    %d disks only. Disks beyond the %dth will be flagged INACCESSIBLE. 'disk=%s  inaccessible' is being assumed.  (%04X) device codes (canonical) = %X
 BIOS device code 0x%02X is used (>0x%02X).  It indicates more disks
  than those represented in '/proc/partitions' having actual partitions.
  Booting results may be unpredictable. Fatal:  First boot sector Second boot sector Chain loader Internal error: Unknown stage code %d Warning:  Out of memory Not a number: "%s" Not a valid timer value: "%s" %s doesn't have a valid LILO signature %s has an invalid stage code (%d) %s is version %d.%d. Expecting version %d.%d.  -> %s %s: value out of range [%d,%d] Invalid character: "%c" getval: %d
 current root. current root Reading boot sector from %s
 stat / Can't put the boot sector on logical partition 0x%04X %s is not on the first disk '-F' override used. Filesystem on  %s  may be destroyed. 
Proceed?  No variable "%s" optional Skipping %s
 Password SHS-160 = Image name, (which is actually the name) contains a blank character: '%s' Image name, label, or alias is too long: '%s' Image name, label, or alias contains an illegal character: '%s' Duplicate label "%s" Single-key clash: "%s" vs. "%s" Only %d image names can be defined Bitmap table has space for only %d images vmdefault nokbdefault Invalid image name. alias label SINGLE-KEYSTROKE requires the label or the alias to be only a single character Added %s  (alias %s)   @   &   +   ?   * %4s<dev=0x%02x,hd=%d,cyl=%d,sct=%d>
 %4s"%s"
 MDA menu Unable to determine video adapter in use in the present system. Video adapter (CGA) is incompatible with the boot loader selected for
  installation ('install = menu'). Video adapter (%s) is incompatible with the boot loader selected for
  installation ('install = bitmap'). bmp-timer bmp-table 'bmp-table' may spill off screen bmp-colors pw_file_update:  passw=%d
 pw_file_update label=<"%s">  0x%08X    %s
 Password file: label=%s
 Ill-formed line in .crc file end pw_fill_cache other Need label to get password 
Entry for  %s  used null password
    *** Phrases don't match *** Type passphrase:  Please re-enter:  read-only read-write Conflicting READONLY and READ_WRITE settings. ro  rw  current root=%x  /dev/mapper/ root=%s  LABEL= UUID= Illegal 'root=' specification: %s Warning: cannot 'stat' device "%s"; trying numerical conversion
 ramdisk ramdisk=%d  vga normal ask Command line options > %d addappend ADDAPPEND used without global APPEND literal check_options: "%s"
 Command line options > %d will be truncated. APPEND or LITERAL may not contain "%s" restricted mandatory MANDATORY and RESTRICTED are mutually exclusive bypass MANDATORY and BYPASS are mutually exclusive RESTRICTED and BYPASS are mutually exclusive BYPASS only valid if global PASSWORD is set PASSWORD and BYPASS not valid together Password found is vmwarn vmdisable VMWARN and VMDISABLE are not valid together nokbdisable MANDATORY is only valid if PASSWORD is set. RESTRICTED is only valid if PASSWORD is set. %s should be readable only for root if using PASSWORD bmp-retain single-key LOCK and FALLBACK are mutually exclusive TEXT BITMAP MENU message Bitmap Message Map %s is not a regular file. Filesystem would be destroyed by LILO boot sector: %s boot record relocation beyond BPB is necessary: %s ~ Using %s secondary loader
 Secondary loader: %d sector%s (0x%0X dataend).
 Ill-formed boot loader; no second stage section install(2) flags: 0x%04X
 bios_boot = 0x%02X  bios_map = 0x%02X  map==boot = %d  map S/N: %08X
 Cannot get map file status Map time stamp: %08X
 'bitmap' and 'message' are mutually exclusive Non-bitmap capable boot loader; 'bitmap=' ignored. Mapping %s file %s width=%d height=%d planes=%d bits/plane=%d
 Message specifies a bitmap file Video adapter does not support VESA BIOS extensions needed for
  display of 256 colors.  Boot loader will fall back to TEXT only operation. Unsupported bitmap Not a bitmap file %s is too big (> %d bytes) %s: %d sector%s.
 el-torito-bootable-cd unattended UNATTENDED used; setting TIMEOUT to 20s (seconds). serial Serial line not supported by boot loader Invalid serial port in "%s" (should be 0-3) Serial syntax is <port>[,<bps>[<parity>[<bits>]]] Serial speed = %s; valid parity values are N, O and E Only 7 or 8 bits supported Syntax error in SERIAL Serial Param = 0x%02X
 no PROMPT with SERIAL; setting DELAY to 20 (2 seconds) suppress-boot-time-BIOS-data boot-time BIOS data will not be saved. BIOS data check was okay on the last boot BIOS data check will include auto-suppress check Maximum delay is 59:59 (3599.5secs). Maximum timeout is 59:59 (3599.5secs). keytable %s: bad keyboard translation table menu-scheme 'menu-scheme' not supported by boot loader Invalid menu-scheme color: '%c' Invalid menu-scheme syntax Invalid menu-scheme punctuation menu-scheme BG color may not be intensified menu-scheme "black on black" changed to "white on black" Menu attributes: text %02X  highlight %02X  border %02X  title %02X
 menu-title 'menu-title' not supported by boot loader menu-title is > %d characters 'bmp-table' not supported by boot loader image_menu_space = %d
 'bmp-colors' not supported by boot loader 'bmp-timer' not supported by boot loader The boot sector and map file are on different disks. Unsupported baud rate VMDEFAULT image cannot have VMDISABLE flag set VMDEFAULT image does not exist. NOKBDEFAULT image cannot have NOKBDISABLE flag set NOKBDEFAULT image does not exist. Mandatory PASSWORD on default="%s" defeats UNATTENDED First stage loader is not relocatable. Boot sector relocation performed Failsafe check:  boot_dev_nr = 0x%04x 0x%04x
 map==boot = %d    map s/n = %08X
 LILO internal error:  Would overwrite Partition Table The system is unbootable !
	 Run LILO again to correct this. rename %s %s: %s End  bsect_update Boot sector of %s does not have a boot signature Boot sector of %s has a pre-21 LILO signature Boot sector of %s doesn't have a LILO signature /boot/boot.%04X Timestamp in boot sector of %s differs from date of %s
Try using the -U option if you know what you're doing. Reading old boot sector. Restoring old boot sector. Using s/n from device 0x%02X
 vga= kbd= nobd Cannot open: %s  at or above line %d in file '%s'
 '%s' doesn't have a value Value expected for '%s' Duplicate entry '%s' EOF in variable name control character in variable name variable name too long unknown variable "%s" EOF in quoted string Bad use of \ in quoted string internal error: again invoked twice \n and \t are not allowed in quoted strings Quoted string is too long \ precedes EOF Token is too long Unknown syntax code %d cfg_set: Can't set %s internal error (cfg_unset %s, unset) internal error (cfg_unset %s, unknown Value expected at EOF Syntax error after %s cfg_parse:  item="%s" value="%s"
 Unrecognized token "%s" cfg_get_flag: operating on non-flag %s cfg_get_flag: unknown item %s cfg_get_strg: operating on non-string %s cfg_get_strg: unknown item %s .shs Cannot stat '%s' '%s' more recent than '%s'
   Running 'lilo -p' is recommended. Could not delete '%s' Could not create '%s' w+ '%s' readable by other than 'root' deactivate automatic reset change Too many change rules (more than %d)   Adding rule: disk 0x%02x, offset 0x%x, 0x%02x -> 0x%02x
 Repeated rule: disk 0x%02x, offset 0x%x, 0x%02x -> 0x%02x Redundant rule: disk 0x%02x, offset 0x%x: 0x%02x -> 0x%02x -> 0x%02x "%s" is not a byte value Duplicate type name: "%s" part_nowrite check: part_nowrite: read: XFSB NTFS NTLDR part_nowrite lseek: part_nowrite swap check: SWAPSPACE2 SWAP-SPACE part_nowrite: %d
   A DOS/Windows system may be rendered unbootable.
  The backup copy of this boot sector should be retained. part_verify:  dev_nr=%04x, type=%d
 bs read lseek partition table Short read on partition table read boot signature failed part_verify:  part#=%d
 invalid partition table: second extended partition found secondary lseek64 failed secondary read pt failed read second boot signature failed Partition %d on %s is not marked Active. partition type 0x%02X on device 0x%04X is a dangerous place for
    a boot sector.%s I will assume that you know what you're doing and I will proceed.
 Device 0x%04X: Inconsistent partition table, %d%s entry   CHS address in PT:  %d:%d:%d  -->  LBA (%d)
   LBA address in PT:  %d  -->  CHS (%d:%d:%d)
 Either FIX-TABLE or IGNORE-TABLE must be specified
If not sure, first try IGNORE-TABLE (-P ignore) The partition table is *NOT* being adjusted. /boot/part.%04X Short write on %s Backup copy of partition table in %s
 Writing modified partition table to device 0x%04X
 Short write on partition table write partition table At least one of NORMAL and HIDDEN must be present do_cr_auto: other=%s has_partition=%d
 TABLE may not be specified AUTOMATIC must be before PARTITION TABLE must be set to use AUTOMATIC "%s" doesn't contain a primary partition table Cannot open %s Cannot seek to partition table of %s Cannot read Partition Table of %s partition = %d
 CHANGE AUTOMATIC assumed after "other=%s" "%s" isn't a primary partition Type name must end with _normal or _hidden ACTIVATE and DEACTIVATE are incompatible Unrecognized type name FAT16_lba FAT32_lba FAT32 DOS16_big DOS16_small DOS12 /boot/mbr.b *NOT*  Cannot open %s: %s stat: %s : %s %s not a block device %s is not a master device with a primary partition table seek %s; %s The Master Boot Record of  %s  has %sbeen updated.
 Cannot open '%s' Cannot fstat '%s' Not a block device '%s' Not a device with partitions '%s' read header lseek failed lseek vol-ID failed read vol-ID failed %s%d
 No active partition found on %s
 %s: not a valid partition number (1-%d) Cannot activate an empty partition pt[%d] -> %2x
 PT lseek64 failed PT write failure The partition table has%s been updated.
 No partition table modifications are needed. us.ktl No initial ramdisk specified No root specified identify: dtem=%s  label=%s
 setting  dflt No append= was specified %s %s
 identify_image: id='%s' opt='%s'
 No image found for "%s" 		Type Normal Hidden 	 **** no change-rules defined **** %20s  0x%02x  0x%02x
          usage: 	lilo -T %s%s	%s
 %4d			     ** empty **
 %4d:%d:%d %4d%18s%5s%11s%14s%12u%12u
  vol-ID: %08X

%s
 %4d%20ld%12d
     %s: %d cylinders, %d heads, %d sectors
 KMGT vol-ID: %08X     bios=0x%02x, cylinders=%d, heads=%d, sectors=%d	%s
 	(%3u.%02u%cb 	(%3u%cb ,%03u %14s sectors) 	LBA32 supported (EDD bios) 	C:H:S supported (PC bios) LiLo 22.5.1 22.0 24.2 22.5.7 Only 'root' may do this.

 The information you requested is not available.

Booting your system with LILO version %s or later would provide the re-
quested information as part of the BIOS data check.  Please install a more
recent version of LILO on your hard disk, or create a bootable rescue floppy
or rescue CD with the 'mkrescue' command.

 GEOMETRIC Int 0x13 function 8 and function 0x48 return different
head/sector geometries for BIOS drive 0x%02X fn 08 fn 48 LILO is compensating for a BIOS bug: (drive 0x%02X) heads > 255 LILO will try to compensate for a BIOS bug: (drive 0x%02X) sectors > 63 LBA32 addressing should be used, not %s Drive 0x%02X may not be usable at boot-time. 
BIOS reports %d hard drive%s
 Unrecognized BIOS device code 0x%02x
  all 
  BIOS     Volume ID
   0x%02X     %08X %s%s
 
Volume ID's are%s unique.
    '-' marks an invalid Volume ID which will be automatically updated
	the next time  /sbin/lilo  is executed.    '*' marks a volume ID which is duplicated.  Duplicated ID's must be
	resolved before installing a new boot loader.  The volume ID may
	be cleared using the '-z' and '-M' switches.     no %s
     %s = %dK
     Conventional Memory = %dK    0x%06X
     The First stage loader boots at:  0x%08X  (0000:%04X)
     The Second stage loader runs at:  0x%08X  (%04X:%04X)
     The kernel cmdline is passed at:  0x%08X  (%04X:%04X)
 purge: called purge: can't open /dev/mem purge:  purge: successful write get video mode determine adapter type get display combination check Enable Screen Refresh check VESA present mode = 0x%02x,  columns = %d,  rows = %d,  page = %d
 bug is present bugs are present is supported is not supported %s adapter:

 No graphic modes are supported     640x350x16    mode 0x0010     640x480x16    mode 0x0012
     320x200x256   mode 0x0013     640x480x256   mode 0x0101     800x600x256   mode 0x0103 
Enable Screen Refresh %s.
 Unrecognized option to '-T' flag bios_dev:  device %04X
 bios_dev: match on geometry alone (0x%02X)
 bios_dev:  masked device %04X, which is %s
 bios_device: seek to partition table - 8 bios_device: read partition table - 8 bios_device: seek to partition table bios_device: read partition table bios_dev: geometry check found %d matches
 bios_dev: (0x%02X)  vol-ID=%08X  *PT=%0*lX
 bios_dev: PT match found %d match%s (0x%02X)
 bios_dev: S/N match found %d match%s (0x%02X)
 Kernel & BIOS return differing head/sector geometries for device 0x%02X Kernel   BIOS maybe no yes floppy hard No information available on the state of DL at boot. BIOS provided boot device is 0x%02x  (DX=0x%04X).
 
Unless overridden, 'bios-passes-dl = %s' will be assumed.   If you
actually booted from the %s %s drive, then this assumption is okay. first second 3rd 7th 8th 9th 10th 11th 12th 13th 14th 15th 16th EGA MCGA VGA VGA/VESA DOS extended WIN extended Linux ext'd Linux Swap Linux Native Minix Linux RAID help Print list of -T(ell) options State of DL as passed to boot loader ChRul List partition change-rules EBDA Extended BIOS Data Area information geom= <bios> Geometry CHS data for BIOS code 0x80, etc. geom Geometry for all BIOS drives table= Partition table information for /dev/hda, etc. video Graphic mode information vol-ID Volume ID check for uniqueness  4.A     .A     +.A     +.A     +.A     +.A     .A     .A     +.A     $.A     $.A     $.A     r�A     x�A     �A     ��A     ��A     ��A     ��A     ��A     ��A     ��A     ��A     ��A     ��A     ��A     ��A     ��A     7�A     �A     ��A     ��A     ��A     ��A     ��A     ��A     ��A           ��A           ��A           :�A           ��A           ��A           ��A           ��A            ��A            ��A     �       ��A     �       ��A     �       �A     �       �A     �                       %sColumn(X): %d%s (chars) or %hdp (pixels)    Row(Y): %d%s (chars) or %hdp (pixels)
 
Table dimensions:   Number of columns:  %hd
   Entries per column (number of rows):  %hd
   Column pitch (X-spacing from character 1 of one column to character 1
      of the next column):  %d%s (chars)  %hdp (pixels)
   Spill threshold (number of entries filled-in in the first column
      before entries are made in the second column):  %hd
 Table upper left corner:
   %sForeground: %hd%sBackground:  transparent%s %hd%s Shadow:  %hd %s text %s color (0..%d%s) [%s]:  ??? %s (%d..%d) or (%dp..%dp) [%d%s or %dp]:  ???1 ???2    Normal:   Highlight:       Timer:   Timer position:
   
	The timer is DISABLED. %s (%d..%d) [%hd]:   %s (yes or no) [%c]:   Cannot open bitmap file Cannot open temporary file get_std_headers:  returns %d
 read file '%s': %s Not a bitmap file '%s' Unsupported bitmap file '%s' (%d bit color) Unrecognized auxiliary header in file '%s' Error reading input Using Assuming .dat .bmp '%s'/'%s' filename extension required:  %s cfg_open returns: %d
 cfg_parse returns: %d
 Illegal token in '%s' Transfer parameters from '%s' to '%s' %s bitmap file:  %s
 Editing contents of bitmap file:  %s
 
Text colors: 
Commands are:  L)ayout, C)olors, T)imer, Q)uit, W)rite:   
Text color options:  N)ormal, H)ighlight,  T)imer,  Normal text Highlight text Timer text 
Layout options:  D)imensions, P)osition, B)ack:   
Number of columns Entries per column Column pitch Spill threshold 
Table UL column Table UL row 
Timer colors: 
Timer setup:   C)olors, P)osition, D)isable E)nable Timer 
Timer col Timer row Save companion configuration file? Open .dat file #
# generated companion file to:
#
 bitmap = %s
 bmp-table = %d%s,%d%s;%d,%d,%d%s,%d
 bmp-colors = %d, bmp-timer =  none
 %d%s,%d%s;%d, Save changes to bitmap file? Writing output file:  %s
 ***The bitmap file has not been changed*** Abandon changes? Unknown filename extension:  %s fg bg ,transparent ,none �BA     �BA     �BA     �BA     �BA             '�A     *�A     ��A             @tA     -�A     :�A                             0   LILOP `   �                     Internal error: temp_unregister %s (temp) %s: %s Removed temporary file %s
 ;  �   t>��T  4D���  dD���  4_��$  �`��|  #b���  e��  He��,  �e��L  �e��l  �p���  �t��  gu��T  v���  /x���  �y��	  �z��\	  {���	  \{���	  �{���	  �{���	  _|��,
  i|��D
   ����
  9����
  8���$  ���l  �����  ���  ���  Y���4  ����l  Ë���  ӌ���  ����,  ����|  �����  ����  +���T  Y����  r����  �����  e���4  1����  ^����  ۱��  ���T  V����  �����  �����  q���,  ����\  �����  u����  Ϳ��  P���$  ����l  �����  &����  ����4  g���t  o����  *����  ����  ����4  l����  �����  `����  @����  m���  ����4  ����L  ����l  T����  ����  '����  y����  ����  ����,  ����|  �����  "����  ����  *���\  O����  i����  z���  X���4  g���\  +����  �����  �����   ���  ����D  �����  	����  ����  ���  G��,  ���D  ���  T���  ���  e���  ���  ^��<  ���l  ����  \���  D���  j��L  [���  ����  ����  ���  =��,  c��L  ���|  	 ���  r ���  � ��  �"��D  �"��\  �"��t  �#���  $���  �$��  �&��T  -���  2-���  �-���  .��   �0��\   	3���   )3���   �3���   h6��!  �9��T!  �;���!  ?���!  J?���!  @��"  I@��,"  �@��T"  �A���"  C���"  5C���"  �D��<#  �F��l#  +G���#  �J���#  CK��$  �K��L$  �L���$  �M���$  �M���$  �N��%  #Q��4%  �Q��T%  �R���%  �R���%  fV���%  �V��&  �W��,&  XY��|&  {Y���&  �Y���&  MZ���&  �Z��'  i[��D'  \��\'  �\���'  �\���'  H^��(  f_��d(  �_���(  $`���(  �`���(  a��)  Vc��\)  �d��|)  �e���)  Sf���)  �o��L*  -p��t*  �p���*  $q���*  �q��+  �q��$+  �q��<+  �q��T+  �q��l+         zR x�      Y��*                  zR x�  $      8���   FJw� ?;*3$"       D   Z���   A�  $   \   �[���   A�B G(B0w   L   �   �=���   B�B�E �B(�E0�A8�L�%�8C0A(B BBB         �   ^��0    A�n          �   ^��K    j�`�           ?^��+    A�i       \   4  J^��+   B�B�G �B(�F0�A8�L���M�m�A�.8C0A(B BBB    L   �  i���   B�B�B �B(�A0�A8�A@�8A0A(B BBB       4   �  tl���    B�B�A �A(�Dp�(C ABB4     m���    B�B�D �A(�D0�(A ABBL   T  xm��#   B�B�D �B(�E0�A8�M��8A0A(B BBB      4   �  Ko��T   B�A�F �J�< AAB      D   �  gp��/   B�B�E �A(�F0�R�0A(A BBB      ,   $  Nq��h    G�J�A �B�F�B�      T  �q��B    A�@      ,   t  �q��~    B�A�C �L0g AAB   �  �q��           4   �  �q��n    B�B�D �A(�K@S(A ABB   �  +r��
           L     r���   B�B�D �B(�F0�A8�G�q8D0A(B BBB      L   \  du��9   B�B�E �B(�D0�A8�OP8C0A(B BBB       <   �  Mv���    B�B�D �A(�K��(D ABB       D   �  w���    B�B�B �A(�D0�I��0D(A BBB       4   4  �w���    B�A�A �G�� AAB       \   l  Qx���   B�B�G �B(�D0�A8�G�
�
M�
K�
A�
�8A0A(B BBB       �  �z��!              �  �z��K    bT 4   �  {��4   B�A�F �G� AAB      \   4  |��6   B�B�G �B(�F0�A8�G���N�Q�A�j8A0A(B BBB      ,   �  �~��   A�A�J�AA      ,   �  ���$   A�A�J�AA      L   �  À���   B�B�E �B(�D0�A8�J�t8A0A(B BBB      <   D  ����   B�B�A �A(�C0�(A ABB       L   �  ��   B�B�E �B(�A0�A8�M�C�8A0A(B BBB      D   �  ~����   B�B�E �A(�D0�V�l0A(A BBB      ,     ϕ��.   A�A�M�AA         L  ͖��    A�W       T   l  Ɩ��   B�B�E �A(�D0�G�-�Z�H�A��0D(A BBB     4   �  �����    B�A�D �G�� CAB       L   �  )����   B�B�B �B(�D0�A8�J��8A0A(B BBB      L   L	  ����-   B�B�D �A(�E0�
(K ABBUA(A ABB      <   �	  ����}   B�B�F �A(�I@b(A ABB       <   �	  ����
   B�B�D �A(�J��(A ABB       L   
  ����q   B�B�G �B(�D0�A8�P�D8A0A(B BBB         l
  ����B    P�f   �
  Ԩ��     A�^       L   �
  Ԩ���   B�B�E �B(�D0�A8�J��8A0A(B BBB      ,   �
  =����    B�A�D �zAB      ,   $  �����    B�A�D �P0� DAB,   T  ,����    M�A�I0�A�A�      D   �  ����X   B�B�E �A(�C0�J�!80A(A BBB         �  �����    A�}      D   �  $����    B�H�B �A(�C0�R�@0A(A BBB       <   4  ����   B�B�D �A(�I�`�(A ABB       4   t  K���'   B�A�A �G�  AAB      L   �  :����   B�B�B �B(�D0�A8�V�!�8A0A(B BBB      <   �  �����   B�B�D �A(�S�m(A ABB         <  ���           ,   T  ۵���    A�A�I��AA       L   �  f���]   B�B�B �B(�A0�A8�K�=8A0A(B BBB      $   �  s���Y    A�A�F NAAL   �  �����   B�B�B �B(�A0�A8�G�!p8A0A(B BBB         L  ����"    A�     d  �����    A�J�         �  p/��0    PN $   �  �����    A�G��A          �  <���-    A�k          �  I���    AX    �  K���    AU      J���8    A�I lA    4  b���~    A�I pC,   T  �����    B�A�F ��AB         �  J���           $   �  K���R    A�A�KD         �  u���    DV    �  x���5    G�mL   �  ����6   B�B�E �B(�D0�A8�LP8C0A(B BBB       ,   D  {����   A�A�J��AA      $   t  �����    A�A�D ~AA4   �  F����    B�A�C �r
ABJAAB  L   �  ����~   B�B�B �B(�D0�A8�GP\8D0A(B BBB       L   $  ����%   B�B�B �A(�A0�
(A BBBJA(A BBB   ,   t  ����   B�A�F �AB     $   �  ����   A�G A       ,   �  n����   A�A�D0�AA       $   �  ���   A�D A       4   $  ����    A�A�C l
AAE�AA    ,   \  ����w   A�A�G�kAA         �  ����6           $   �  ����H    A�A�F }AA <   �  ����   B�B�D �A(�D0t(A ABB       D     \���=	   B�B�D �A(�F0�O�	
0A(A BBBA      T  Q���$    A�^       L   t  U����   B�B�G �B(�C0�A8�S��8A0A(B BBB         �  ����              �  ����Q    AO   �  ���Q    AO<     L����    B�B�O �A(�A0�g(A BBB         L  ����8    Re ,   d  �����   A�A�I��AA         �  G���J    A}
JA   $   �  q���2   A�IP
AA    $   �  {����    A�A�I`�AA,     ���z   B�B�D �A(�M�!       L   4  d���   B�B�E �B(�D0�A8�O��8A0A(B BBB          �  2���f    A�Y         �  x����    A�J�      L   �  @���&   B�B�E �B(�D0�A8�JP8A0A(B BBB       D     ����    B�B�B �A(�A0�G��0A(A BBB          \  �����    A�
EC  <   |  3����   B�B�A �A(�G��(A ABB         �  � ��              �  � ��M    A�K         �  	��&    A�d       ,     ��g    B�A�D �G
ABA   ,   D  F��?   B�A�D �4AB     ,   t  U��i    B�A�D �[AB      ,   �  ���c    B�A�D �XAB      4   �  ����   B�A�A �G�	� AAB           G��              $  F��           <   <  M��   B�B�E �A(�D0�L@�0A(A BBB$   |  ��A    A�A�I0qCA 4   �  5���    B�B�D �A(�D0|(A ABB<   �  ���   B�B�A �A(�G��(C ABB      L     [��K   B�B�E �B(�A0�A8�M�#&8A0A(B BBB         l  V��0    A�n       ,   �  f���    B�A�F ��AB         �  ���    AK L   �  ����   B�B�B �B(�A0�A8�G��8A0A(B BBB      D   $  a��D   B�B�G �A(�F0�G�"0A(A BBB         l  ]��     AZ    �  e���    Am,   �  ����   B�B�F �A(�S�       L   �  \��J   B�B�D �B(�D0�A8�Q�8D0A(B BBB      4     V���   B�B�G �B(�A0�A8�M�     L   T  ����   B�B�G �B(�A0�A8�D�c8F0A(B BBB         �  (��>    As    �  N���    H�     �  ���D    A�W
Ja $   �  ��F    A�A�F {AA <     3��B   A�A�H��E�W�A�DAA      <   \  5��<   B�B�A �A(�L�#(A ABB         �  1 ��(           L   �  A ���   B�B�E �B(�D0�A8�P`|8A0A(B BBB       ,     �!���   A�A�A �AA          4  <#��{    A�y      L   T  �#���   B�B�B �B(�A0�A8�NPg8D0A(B BBB       <   �  �&���    B�A�C �DPBXG`\XAPV AAB    ,   �  '��W    A�D@XHGP\HA@TA     L     F'��)   B�B�G �B(�A0�A8�D�8A0A(B BBB      ,   d  (���    B�A�F ��AB         �  �(��8    Av    �  )���    H��      ,   �  �)��_   B�A�A �WAB        �  �+���    A��
LA4     �,���    B�B�B �B(�A0�A8�D@         T  -��@    D@{ L   l  8-���   B�B�E �B(�A0�A8�J�`8A0A(B BBB         �  j0��Y    JN   �  �0���    A��      L   �  |1���   j�B�D �I(�H0�H8�=�0M�(N� B�B�B�          D   �2��#              \   �2��G           <   t   3���    H�B�E �A(�A0�r(A BBB         �   Y3���    G�v      4   �   �3���    B�H�E �D(�S0C(I ABB   !  4���    A�4   $!  �4���    B�A�D �[
ABJKAB  $   \!  �4��K    A�A�I�}AAL   �!  5��p   B�B�B �B(�D0�A8�F�R8A0A(B BBB      T   �!  46��   B�B�E �B(�D0�A8�KX_`fhBpZP�8A0A(B BBB       ,"  �6��q    V�T
EA   L"  K7��M    Ks 4   d"  �7���    B�B�C �A(�Q@`(A ABB4   �"  �7��g    B�B�D �A(�A0T(C ABBL   �"  �7��K   B�B�E �B(�C0�A8�O` 8C0A(B BBB          $#  �9��@   A�>     L   D#  ;��:   B�B�E �B(�D0�A8�T�8A0A(B BBB      $   �#  �;���    C�^
LA
SA  T   �#  W<���	   B�B�G �B(�A0�A8�D@�HBPCXA`EhBpU@?HAP^HA@ $   $  �E��4    A�A�D kAA ,   <$  �E��]    B�A�G �r
ABE       l$  �E���    A��      D   �$  XF��e    B�B�E �B(�H0�H8�M@r8A0A(B BBB    �$  �F��              �$  xF��)              %  �F��              %  �F��              4%  �F��    D Z                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         ��������        ��������                                     �              �@            �PA            x@            �@            �@     
       z                                           b            p                           @            h@            �       	              ���o    @     ���o           ���o    R@                                                                                                                                     @b                     �@     �@     �@     �@     @     @     &@     6@     F@     V@     f@     v@     �@     �@     �@     �@     �@     �@     �@     �@     @     @     &@     6@     F@     V@     f@     v@     �@     �@     �@     �@     �@     �@     �@     �@     @     @     &@     6@     F@     V@     f@     v@     �@     �@     �@     �@     �@     �@     �@     �@      @      @     & @     6 @     F @     V @     f @     v @     � @     � @     � @     � @     � @     � @     � @     � @     !@     !@     &!@     6!@     F!@     V!@     f!@     v!@     �!@     �!@     �!@     �!@     �!@     �!@     �!@     �!@     "@     "@     &"@     6"@     F"@     V"@                                                             ��������������������               ?        ?       ??          ?? ?          ??   ????                                ?                                                                                                                                                                                                                                                                                                                                                                                                   �A      �A     �tA     %�A                     kbgcrmywKBGCRMYW NnOoEe                         110 150 300 600 1200 2400 4800 9600 19200 38400 57600 115200 ? ? ? ? 56000  0123    ����       �+b      +b     �!b      b     �b     @b      b     �b     �b      b     �b     @b     �b     @b     �b     �b                                             R�A                                     <�A                                     �A                                     �A                                                                                                   ۹A                                    ٹA                                     2�A                                                                           �A     CA                             �qA     A                                                                            z�A                                     W�A                                                                                   �A     >A                             ��A     nA                                                                            =jA                                                                                            uA                                                                                            �qA     �e@                                                                                    ~uA                                     �uA                                     �uA                                    ��A                                     �uA                                     �uA                                                                                    ��A                                    ��A     EA                             ��A                                     U�A     ��@                            ��A                                     A�A                                    ��A                                             b                             O�A                                            �b                                             |�A                                     �A                                     ��A                                     ?�A                                    ]�A                                    g�A                                     ZA                                     S�A                                             b                                                     9�A                                    ��A                                    a�A                                     JbA                                     ?�A                                     ��A                                    �tA                                    '�A                                    c�A                                    ��A                                     S`A                                    �A                                    	�A                                    -�A                                    &�A                                                                            �A                                     WA                                     %WA                                     R�A                                     <�A                                    ��A                                     �A                                     �A                                     '`A                                     ��A                                    t�A     -A                            �VA                                     �A                                     �VA                                     ]aA     �f@                             6tA                                    ��A                                     JbA                                    �VA                                     WA                                    �UA                                    �VA                                     ��A                                     �VA                                     �A                                    �A                                    VA                                    �UA                                     ��A                                    �tA                                    '�A                                     VA                                    ��A                                     G�A                                     ��A                                     N�A                                    ZA                                     �A                                    �A                                    WA                                    ��A                                     S`A                                    �]A                                     WA                                     ?�A                                    ]�A                                    g�A                                    �A                                     ZA                                     �A                                    	�A                                    ��A                                    �A                                    0�A                                     ]A                                    ��A                                     ZA                                     S�A                                     �A                                                                            `VA     �A                             եA     HA                                                                            `VA     ��@                             եA     ��@                                                                    Extended BIOS Data Area (EBDA)  ����                            		 Type  Boot      Start           End      Sector    #sectors  �A     �A             �A     ~uA     �4A             :�A     _�A     AA             e�A     ��A     �*A             ��A     ��A     )A     ��A     ��A     ��A     �(A             ��A     �A      A     �-b     �A     :�A     _/A             @�A     Y�A     �)A             `�A                                     <device>    ����                   ��Y   LILO     �                                                                        1ێӼ |���=����&�G< w�r�>X �Z �>T �;���<�u!�& �D<�u��$���ĉD8�u���D���6T � � ���$|�~�uO&�<�rI<�wE&��u?&�<)t<(u5�t� &��x)t< r#�� &��x< r��� �V$�6 f�Tf�V�  � ������t:�t:P�Q XP���x 8�u1�� ��; �| �ػ ���������� �r7X���þ �&8u&�'������t����t���rþH� 1�� |         V� ���	�t8�u���^Ë>T �= t�� ����6 �ƾ1��؎�� |�܉�PS6�?�t�?�u7P�G�@@�X�?�u(6f�LILOu.f�>X  t.�X �w�&f�LILO�ֲ��PS��t	�� ���[X�Rewrite error.
 `�	�t$W�GG&�= t&8%u�&�e&���8�t�CC_��&�GG@t�H�tCC��a�QV6������1�f��6f�L f���- �^�&�^Y�`��&�= t4�0 ��`������	�t��� � u�������b���0 ���a����QV6�>L 	�u;�ǁ� �s3��`r.1�� �^�u&�> �1�� �U�u&�=��F r��P v1�	�^Y�PU��V�Z PU���
LILO Z �V�Z .��t	�t8�u��^�F�F�n �    U��F���t��t	�F
	�t�F�F
]���                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     FvjS                               ��1  LILO   |          ^��t	�� ��� ����1��м |���SVR����؎�� � ��V  `� �6�af�>�f	�t�����ʒ�� � f;>�}tB�󒾾f1�� �����x?����f��f1�f�f�>�m ��}��x!���� t��\�No partition active
 f�Df�8 �>�}U�u1�X<�u��^[��.��No boot sig. in partition
 `� ���U�A�r��U�u	��t�B�?R��rCQ�����Y���@��?�ᓡ�9�s"��9�w���������AZ�Ƹ�\�raô@ZMt0�����Disk read error
 �D<t<t<�uf�|�                                                                      H��                               ��1  LILO   |          ^��t	�� ��� ����1��м |���SVR����؎�� � ��V  `� �6�af�>�f	�t�����ʒ�� � f;>�}tB�󒾾� ����x3������No partition active
 ��y�e�Invalid PT
 �����f�Df��= �>�}U�u1�X<�u��^[��.�*�No boot signature in partition
 `� ���U�A�r��U�u	��t�B�?R��rCQ�����Y���@��?�ᓡ�9�s"��9�w���������AZ�Ƹ�\�raô@ZMt0�����Disk read error
                                                                                                  `绯                             &  �N    LILO                                  ��  �  ��   �                  ��.��$���-���1�1�1�� �� � �h~ ���  ��t0�����L��	j �6x �|	w�4%� �&�E�j ��x 4%�z �.�% �c
�ˎێÁ� � �9�v����$ (�t	�O �r	��)����Ӊ�f�> LILOuf�>K%MAGEu�> un�>
 uf�%@%��4�&�$d� 8�t�1��df� f; u7��
�#� .��-�������
�� �����-r� .��fh���c�f;t�+"��C"���"�������
s%� .��t�E2 tW�u6�6 ���u�_���6����
r%� .��t�E2 �tW�u6�6 ���u�_���6��1ۉ���� -��� d � *��-��-��-�A
r� *�?��u	�mk�	�L�G �F��� �7� .� 0���t%���������u��S� �[C9�v��#����t��� ��$��f1�f�%��$�% �� 	%�%��*
r�>  td� u�%��Qr=d�>��u&d��d��d��&f�?LILOud�6�&�< t��*�< u�%���p�%@%�%��!�_�P%��tS�`[Cu��O% &�<�t&�F�!�������x�>� t
<�t��J�t�<	t�<?t��tk<ta<t{<tYw�<tV<tR< r�w8G�t���O't�0�CS��P��X[��Q%u��� � .���E2 t��k8�u�} t&��6���b��� �S�%�=[s��#��P% ���%E%�% 0���P%�T'�% ���u���P%t	�� uK��P%��f�<nobdu�| wd� �4f�<vga=u	�����%f�<kbd=u��f�<locku�| w�%��O�f�<mem=u�9��< t��u�����Q%tU� ���� �"���b���P%t-KS��$��[S� �P%)�t������9�t�����[�V��lS1������T' �>P% u�� .1��s� ��r� @� �G2u��6��� .�޿P%��G�u�� ���P%��t< u��< u�D� N�6%�G2  t1���s��G2 t0�Bs+� ��S�a#�
�k�KP< r�
� X[<yt<Yt�y��G2�t�G2t�< u� S� ����#��U��� ��1����<tD<t/<t+<t<tw�< r��� s�6�FG�*���	�t�� NO��GOt�� N����$�s�1�A�s)�WV�
��
��^���4� �^_tAQ� ��1��Y��][	�t	��#�/���O%=S��!� [S�^V��-1��; �? ��$�����V��$�q� *��-��-��-���6 *� *�mX=��t=mku� *�?��u�$� *�P�6%� 6����P%t����PX^VP��t�I��� *�< t/� �It5f�<mem=u���< t��t�It< t���&�}� uOA�6%���t����t	1��� ^����>% �t�%��� t&��S�� u�>% t�R'���V�w^1�&�u��r	������ÁÀ ��9�v�%#��1�Q� Y��[�� t_&� �� t&� �; &� �? &�>  v��+t	�� ,&�$ &� �^�6; �? P�X�? [�; �	�t1����  � �� �mh 1�� ���	 ��#�m���� X�����LS�6�$��$��P�@	�u	�u[XÃ��6�$����O��$  ��$S��$�X��$�.�$�� t� (�� K��$����1�����t	� 6��+t	���&f�>HdrSt@d� �r	f�> LILOu!�>
 u�> u� � �T �4�V d��� �>? f���; f��f�%f	�tf)�s��"��&�>r��f��f��f��f�&f�(�&�  ?�&�>" ��!�;d� t��!�-�*��-�ad����
t&�  ���!�	�&�-��?� ��� %�t����� 6�   � �[P��	�Xt�KS� ��1��@ ��$[PQV��1Ɋ.�$�6> SQV���^Y[rX:&? u��)�LD��^YX�[P��$�&SQR�u��rZY[�� �r�s�� �����P��!�d X���' �b ��$  ���<ar<zw, �`�: �<� %�t�a�P��� X$'�@�4<
u��+ �
<u�>� u
S��0��[�� C��u�ð� �
S� .�>�$ u� ��[�R.�
%	�t��P�t.�%� t��X�Zá � ��u,�
%	�t���t���$u�>� t�+� %t�X��0��S� ,�[d� t� u� ����Z ��$_u&��u �
%	�t�>% u���u	� %t�����j �f�p .f�%�p k�r ��j f�%&f�p �	�t���$� % ��� %�Ü.�>�$��t.��$u.� %�.f�6%ϋ � � � ,����d� �u
� u� Ë�-��-��-d� u0�;�{ �; s `��tP��"�y�X���<��w���#�h�a����u����V�6i�����s`�;�8 �; aB	�u�^��  �c�� r� ,��fh��� �f;t�b"�?���t��`u
P���Y��Ê&�$���� t��@t��&�$������t�j�����f`���r)� t"f�hXMVf1�f�ǺXVf�
   f�f9��uf@t�fa�P� t����`�d$t��`�4�u�X�U��VWSQf1�fHGOt� &�F��f���� ��sf3F����f��Y[_^�� Sf�%f	��� d�  �� f1�f1�f1��f	�ttfRf� �  f�PAMSf�   � %�fZr`f=PAMSuXf��uR�>0%u�f�$%f� %
f�,%f�(%
f�> %   r�f�> %  @ s�f;6(%w�f� %f�6(%f��f	�tf��U1�1Ҹ���r;	�t��	�t��f��f��f��f� @  f9�wf�f���f   f9�uf�����f��f   f� <  f9�v2d�  uf�f�   �t	�>rf�,fKf��
fCf9�rf�[f��f��f)�f=   s��$� �f���%�; f���%�? ��6�$�6�$��$ *�D2$ d ��$f1�f�%f�f�%f�  f��������	�tBVS��$����$  [�J�f�>% t�r	f�%&f� f�%&f� j �  ���� �{�^��$��$�
LI0000� ��x[1���PR�j@[��.�
%[���t��.���R�����ZR��B���BB�$�ZR����Z��  �������� .������UWV��4f�f�uf�Mf�Uf�})�f��f!�fVf��f!�f	�f^f�řy�Z�t ��Pr�f��f1�f1�f�š��n�\ ��� r�f��f!�fQf	�f!�f	�fYf��$C�p�9 ��� r�f��f1�f1�f��*>�5�  ��@r绤4ffwfOfWf^_]�f�f��f��f��f��f��f��fŃ�@sf���4�6S��4��<f���4����<f3��4����<f3��4����<f3��4f��f���4[f���W� ��4f���f����f���_�U��W��4f�#Egf�E����f�E�ܺ�f�EvT2f�E����f)�f�Ef�E_��U��VW�>�4��?f�Ff�4f��4 �v�@ )�9�r���4)�P�6��u��c�X)�����4���6�_^��U��VW�>�4��?ƅ�4�G)���8v�@ )����4��7��%��8 ��4)��	�8 )����4���f��4f��4f��f��f��4f��4���_^��VSR0�PQS�ր��� t9<w5P��U�A�Xr*��U�u$��t[YXPfj WQSPj��� B�w �d�o[YSWQPSRWQ��d r|Q�����Y���@I��?A��XZ9�sd��9�w^�������(���� ��Z[��XP9�r��P�� [^Y_r;ك� �[ � ǖ)�u��+�� U� `�sMt1��aM����f]�Y_��@Z[YY_[�YZ[^�  `1�1҇�4�tW	�t&�GG	�t8�u�&�$_&��X-� f1��f�ty1ɿ 4�� f�f	�tdWQ��� 4)���It�f�u�e���D�Y_f�E�    �;�X-� ���/�f�u*�U�)���[S9�t�ށʀ�V��4�7CC9�t		�u�W��7^Y_A��r���-��-1�f1���s/f�fPf��X-� 4� �f�u���ˉ���� ��	if��@4�fX����@r�a�O
Error: Duplicated Volume ID
 SRQWQ�����Yr!8�s�ʹ � (�ʀ����r&f����f1��_YZ[�VPS��4�Ӏ�.�&�$��u
.�	�t	8�u���p�[X^�U��>i ud d> �WQ�׃�����@4��B4N�~�Y_]�QVj &�>L 	�u;�ǁ� �s3��`r.1�� �r�u&�> �1�� �i�u&�=��F r��P v1�	�^Y�PU��V� PU���
LILO      LiLo              j � ~� � �������H r�ð����R�A��U����Z��ث��r!��U�uR��W�H� �_������Z�`j`� �>�R����X��>���j@�� �����u� ��Pr{���������wl� ������u_<r[W�4��V�!C� �6 �_�������� O�&�&�M�������Ou'��VEu!=SAu�O��&�����O��&����� 1҉>�Q�R����������Zr��y�yY�6RW���������_�����Zr���u�YP�x����������Y����W� ��y�����:�w�y�B��>�W1���� �_� )�fh����&f�  aÉ���tC��)Ó�`�>  tD��-��-��-� (�Z��c�h 1�S��[� = rw� ���1�������$��1�1�� � .��	�t+�G2 t	���s�6��G2 @t	���r�6�9�r���6F�Ή6��>����4-�H��:P-w�P-�6-8�v���1����k@�����P%�u���MaÁ�P%tS��$�#�[K���VP���^k�6�� .��t
�CS��[��^Ø���	�y1ҡ�9�r��J��9�t
���� ���]���Pt��؀�Htȋ���Ot̀�GtŠ�������Mu	B:4-r��!��Iu�ވ�뗀�Qu�� ���؀�Ku�u��Su���-�`1�9���$��t��a�`�M-�x^�--�d�g��$;ktJ�k@t,�&m�6o;it6�i1��6q�
00�ģd��
00�ģghF-jhd�6L-�6N-�,��a�  :      �@�< `��h@-�`h:-�>� tJ�ð ��AA��QW�k�6�� .����t����2-�0-�6�9�r8-)������PQ���
��a�                                       ��              ��  �P���% Ŏ�X(��`�P'.�6���= ��wst~���P���XI$����m�� ~+���ǈ�	�t)����P���X��tP$�X���u��u��.����)����ƀ����P���X��t
$��π� u��t�f���� ��\��Y�.�6�.� a��  `j ��0�N�����D��у����� k�P��׉F��F�  ���^&�(�h ���P��#F�P�g8'XtP�İ�g& %X�
��G& E�G8t�F���P��g& %X��İ�g& eX�F�P�İ�& X�	��& E��P�N�u�a�� U��� � �N�^�V�v��v�v�.�>v���������1��l �� `PR�P'���P� &�������������������ت����Ъ����u�[��_k�Ph ��P'����WV��P�& ��G��X^_��F��u�a� �>w9��;t0�HtHtR����Z� �����
� � ���� �  VW�����^�F�&�?BMu&� u&�(t&�t� ��,���� ��� �F�V��&�?(t2&�G&�g
�F���� ����F�&��uM&��uE��tG��u;�0&�G&�g�F���� ����F�&��u&��u��t��u	� � � ���� (f�VBE2� O�=O uwf�=VESAun�O��=O u\�� ��� ��� �	 �@������f�����f��f��f�
f��f%��� f���  t�� $<u��O�=O t1� ��� �  � �<u
��t��t� ��� �1 ����� �  �$��6 ���^�&�76�� 1�S.�>w�߸ ���?�����������Ŭ�����0�[���~�=tFC9^���^�&�G
&�W��� ������ 1���� ���^����&�?���&#O�˾(���>v�H�-Hx��֓����1��a��6 � �1�_^�� 1��M��1 � �� ��PQR�&؃� �Ǌ#>
��;t��S1�1۸O�[�ZYX�`�P'�
1�1���u��C�9�r�a�`�P'�6��݅�tK��:�����τ�t��)���t�� �� ~���)ʈ���������s����� ��w��t�����m����.�6�.� a��
  `j ��0�N��^��V�����\�0��~&�&�u&�U��F�V��F��F�� 1�.�>
uS�F��^����[� 8�t����s8�t�И��s�Ș�Ā�w&�G�F�Nu��F��n���^�N�u�a�Ã�1�����t< uN�1�<ar, ,0<
r
<r',<s!��r��r��r��r ���t< t<,t�ɻ $���t�< t���� �� �&��ڃ���>r� &;t&�� &�ûZ$�y�X뾃�V�< ^V�	�t,CC���'C�u
�t< t��8�t�C�u���XN�%��^�� r��	�u���#�'�f1�f�%����ASK ��EXTENDED ��EXT ��NORMAL   Q� r)��� ��kt� ��gt�
 ��mtNf���f��r��F��Y�f�   ��V����r6��@ufPF��fZr+f=   wf�f=   v�� �� uf�>% uf�%^�[û�"�x����� RPfX�1�1ҹ
 �<9wH�<0rCuFII�<Xt�<xu�F1ۊ�� ��0r'8�r���8�sR��؃� [R���	�u	Z�r�F������QVW� � .1�V�P%��t4�F��ĊG���t< u�t+� u	�u[S�8�t�^��6V��^	�u�����1�_^Y�[��- .�6��>����>� t9�t���������boot:  Loading  BIOS data check  successful
 bypassed
 
Error 0x No such image. [Tab] shows a list.
 O - Timestamp mismatch
 O - Descriptor checksum error
 O - Keytable read/checksum error
 Kernel and Initrd memory conflict
 O - Signature not found
 
vga/mem=  requires a numeric value
 
Map file write; BIOS error code = 0x 
Map file: WRITE PROTECT
 EBDA is big; kernel setup stack overlaps LILO second stage
 WARNING:  Booting in Virtual environment
Do you wish to continue? [y/n]  
*Interrupted*
 
Unexpected EOF
 Password:  Sorry.
 
Valid vga values are ASK, NORMAL, EXTENDED or a decimal number.
 
Invalid hexadecimal number. - Ignoring remaining items.
 
Keyboard buffer is full. - Ignoring remaining items.
 
Block move error 0x 
Initial ramdisk loads below 4Mb; kernel overwrite is possible.
 O 24.2              (               �                                                  auto BOOT_IMAGE                                                                                                                                                                             �/�.                             $  �N    LILO                                  ��  �  ��   �                  ��.��"���-`��1�1�1�� �� � �h~ ����  ��t0�����L��	j �6x �|	w�#� �&�E�j ��x #�z �.��" �
�ˎێÁ� � �9�v����" &��	�O ��	��)����Ӊ�f�> LILOuf�>#MAGEu�> un�>
 uf��"#��2�&�"d� 8�t�1��df� f; u7�9�~� ,��+������M�� �����+r� ,��fh����f;t���� ��v ������Os%� ,��t�E2 tW�u6�6 ���u�_���6���Zr%� ,��t�E2 �tW�u6�6 ���u�_���6��1ۉR�d� +��� d � � (��+��+��+�
r� (�?��u	�mk��	�T�G �N��� �H��"� ,� 0���t%���+������u�%�S� �$[C9�v��#����t�
��"� ��"��f1�f��"��"��" �� 	�"��"��z
r�>  td� u��"��r=d�>��u&d��d��d��&f�?LILOud�6�&�< t�P�(�< uF��"����>  t,�v��+��+��+��"����1ۇ h � 1��H��"#��"���5�#��tS�6[Cu��# &�<�t	&�F�������<�t��S<	t�<?t��tk<ta<t{<tYw�<tV<tR< r�w8G�t���%t�0�CS��P�fX[��#u��q� � ,���E2 t��]8�u�} t&��6���p��� �S��"�h[s�y!�y�# �����"#��" 0���#�"%��" ���u���#t	�� uK��#��f�<nobdu�| wd� �4f�<vga=u	�]����%f�<kbd=u��f�<locku�| w��"��O�f�<mem=u����< t��u�����#tU� �l�� ����=���#t-KS��"�[S� �#)�t�B��T�R9�t������[�d��yS1������"% �># u�� ,1���s� ��r� @� �G2u��6��� ,�޿#��G�u�� ���#��t< u��< u�D� N�6�"�G2 t0�~s+� ��S�0!�����P< r����X[<yt<Yt�e��G2�t�G2t�< u� S� ����!��U��� ��1��	�D<tD<t/<t+<t<tw�< r��� s�6�FG�*���	�t�� NO��GOt�� N����"�h�1�A�h)�WV��
��W�^���2� �^_tAQ� ��1��Y��][	�t	��!�$���#=S���[S�^V��-1��; �? ��"�����V��"�t� (��+��+��+��6 (� (�mX=��t=mku� (�?��u�`� (�P�6�"� 4����#t����PX^VP��t�I��� (�< t/� �It5f�<mem=u�y�< t��t�It< t���&�}� uOA�6�"���t�����	1��� ^����>�" �t��"��� t&��S�� u�>�" t� %���V�^1�&�u���	������ÁÀ ��9�v�� ��1�Q� Y��[�� t_&� �� t&� �; &� �? &�>  v��+�	�� *&�$ &� �^�6; �? P��X�? [�; �	�t1����  � �� �mh 1�� ���	 ��!�b��� X�����LS�6�"��"��P�@	�u	�u[XÃ��6�"����R��"  ��"S��"�X��"�.��� t� &�� K��"������1������	� 4��+�	���&f�>HdrSt@d� ��	f�> LILOu!�>
 u�> u� � �T �2�V d��� �>? f���; f��f��"f	�tf)�s�S �y�&�>r��f��f��f��f�&f�(�&�  ?�&�>" ���-d� t����*��+�d���t&�  ������ �&�+��x� �0��"�t���� 4�   � �[P��	�Xt�KS� ��1��@ ��"[PQV��1Ɋ.�"�6> SQV���^Y[rX:&? u��)�LD��^YX�[P�`"�&SQR���rZY[�� �r�s�� �����P���V X���' �T ��"  ��<ar<zw, �`�: �u��"�t�a�P��� X$'�@�&<
u�� �
<u���� C��u�ð� �
S�_ .�>�" uUR�>e tA�J<u�u6���
���'<
u:6�s
< r;�u`��>��d���a���Z� ��[�R.��"	�t��P�t.��"� t��X�Zá � ��u%��"	�t���t���$u�"��"t�X��0��S� *�[d� t� u� ����Z ��$_u&��u ��"	�t�>�" u���u	��"t�����j �f�p .f��"�p ��r ��j f��"&f�p �	�t���"��" ����"�Ü.�>�"��t.��"u.��"�.f�6�"ϋ � � � *����d� �u
� u� Ë�+��+��+d� u0���{ �� s `��tP�� �2�X�����0���� �!�a����u����V�6������s`���8 �� aB	�u�^��  �c�� r� *��fh��� �f;t�1 �����t��`u
P���Y��Ê&�"���� t��@t��&�"������t�j�����f`���r)� t"f�hXMVf1�f�ǺXVf�
   f�f9��uf@t�fa�P� t����`�d$t��`�4�u�X�U��VWSQf1�fHGOt� &�F��f���� ��sf3F����f��Y[_^�� Sf��"f	��� d�  �� f1�f1�f1��f	�ttfRf� �  f�PAMSf�   ��"�fZr`f=PAMSuXf��uR�>�"u�f��"f��"
f��"f��"
f�>�"   r�f�>�"  @ s�f;6�"w�f��"f�6�"f��f	�tf��U1�1Ҹ���r;	�t��	�t��f��f��f��f� @  f9�wf�f���f   f9�uf�����f��f   f� <  f9�v2d�  uf�f�   ��	�>rf�,fKf��
fCf9�rf�[f��f��f)�f=   s�u"��f����"�; f����"�? ��6�"�6�"��" (�D2$ d ��$f1�f��"f�f��"f�  f��������	�tBVS��"�����"  [�J�f�>�" t��	f��"&f� f��"&f� j �  ��� �4�^��"��"�
LI0000� ��x[1���PR�j@[��.��"[���t��.��WR�����ZR��B���BB�$�ZR����Z��  ������S� .������UWV��2f�f�uf�Mf�Uf�})�f��f!�fVf��f!�f	�f^f�řy�Z�t ��Pr�f��f1�f1�f�š��n�\ ��� r�f��f!�fQf	�f!�f	�fYf��$C�p�9 ��� r�f��f1�f1�f��*>�5�  ��@r绤2ffwfOfWf^_]�f�f��f��f��f��f��f��fŃ�@sf���2�6S��4��<f���2����<f3��2����<f3��2����<f3��2f��f���2[f���W� ��2f���f����f���_�U��W��2f�#Egf�E����f�E�ܺ�f�EvT2f�E����f)�f�Ef�E_��U��VW�>�2��?f�Ff�2f��2 �v�@ )�9�r���2)�P�6��u��c�X)�����2���6�_^��U��VW�>�2��?ƅ�2�G)���8v�@ )����2��7��%��8 ��2)��	�8 )����2���f��2f��2f��f��f��2f��2���_^��VSR0�PQS�ր��� t9<w5P��U�A�Xr*��U�u$��t[YXPfj WQSPj��� B�w �d�o[YSWQPSRWQ��d r|Q�����Y���@I��?A��XZ9�sd��9�w^�������(���� ��Z[��XP9�r��P�� [^Y_r;ك� �[ � ǖ)�u��+�� U� `�sMt1��aM����f]�Y_��@Z[YY_[�YZ[^�  `1�1҇�2�tW	�t&�GG	�t8�u�&�"_&��X+� f1��f�ty1ɿ 2�� f�f	�tdWQ��� 2)���It�f�u���G���Y_f�E�    �;�X+� ���/�f�u*�U�)���[S9�t�ށʀ�V��2�7CC9�t		�u�W��7^Y_A��r���+��+1�f1���s/f�fPf��X+� 2� �f�u���͉���� ��	�f��@2�fX����@r�a�O
Error: Duplicated Volume ID
 SRQWQ�����Yr!8�s�ʹ � &�ʀ����r&f����f1��_YZ[�VPS��2�Ӏ�.�&�"��u
.�	�t	8�u���p�[X^�U��>� ud d> �WQ�׃�����@2��B2N�~�Y_]�QVj &�>L 	�u;�ǁ� �s3��`r.1�� ���u&�> �1�� ���u&�=��F r��P v1�	�^Y�PU��V�  PU���
LILO      LiLo              j � ~� � �������H r�ð����R�A��U����Z��ث��r!��U�uR��W�H� �_������Z�`j`� �>�R����X��>���j@�� �����u� ��Pr{���������wl� ������u_<r[W�4��V�!C� �6 �_�������� O�&�&�M�������Ou'��VEu!=SAu�O��&�����O��&����� 1҉>�Q�R����������Zr��y�yY�6RW���������_�����Zr���u�YP�x����������Y����W� ��y�����:�w�y�B��>�W1���� �_� )�fh����&f�  aÉ���tC��)Óô��<t	j@�.� ���ɉ�<u
f�6�f���PSQ�0��Y[X�PS�0��[X�R����0����Z�S�0����[�QSP�0��XP�� �	�X[Y�PSR�ĊC�t�������Z[X�RQP�y�����¸ ��XYZ�tOPV% ������6�&���Q������Ɋu�F������͊u�YQF������Ɋu�F��t����͊u�Y��^X�`��Ɗ�o����j� �ш��`��Ɗ�]����X� ���*���:u�d:Du�d���&������t#����:u�d:Du�d���&�������u������:u�d:Du�d���&����a��Ŀ������ͻ���Ⱥ�ķ���Ӻ�͸���Գ�ͳ�Ŵ��׶��ص��ι������������������GqGNp  `�P�R�"��ʀ>e u1Ɋ>�� ��1�1�� � ,���	�t+�G2 t	��s�6T�G2 @t	�@�r�6T9�r���6F�Ή6X�>Z�h����(���S��<~�È^ �����<���\	 �ư���(������>����`�bRʁ��fZ����V ��h�����Z����^�Q��.\��R���R������� t�����ƻ����ƻ����f����ZY(�&^� ,�>X�V������QR�ʁ��\9�r���S���M�PR�����D2  �Uu�F�D2@u�L�D2u	�W�D2 t�	����D2�t�P�D2t�R���ZX��O��6�ZY����t��v�끡R�#�u�T�Z�>e u�`b0Ҁ��d��aÁ�#tS��"���[K���VP���^k�6�� ,��t
�CS���[��^Ø�R�	�y1ҡX9�r��J�R9�t
������]���Pt��؀�HtȋX��Ot̀�GtŠ\��R���Mu	B:^r��!��Iu�ވ�뗀�Qu�� ���؀�Ku�u��Su���.�`�`�b���>���a�`�d��0���������a�`�>f te�--������";�tQ��@t#�&��6�1��6��
00�ģ���
00�ģ��L�R�f�&������ �:t�e��C����Z�4�a�  :  *****  �@�< S�R�>��S�>�QRP���R�V���ZAAS�\9�r��)��� �[�����������Z���XZY[�f�?MENUu	f�Wf����	�G��t���n�9�u=% sW�h�C>��u�_�                      GNU/Linux - LILO 24 - Boot Menu       --:-- Hit any key to cancel timeout Hit any key to restart timeout Use  arrow keys to make selection Enter choice & options, hit CR to boot ��1�����t< uN�1�<ar, ,0<
r
<r',<s!��r��r��r��r ���t< t<,t�ɻ�!����t�< t���� �� �&��ڃ���>r� &;t&�� &�û)"��X뾃�V�^V�	�t,CC��b�'C�u
�t< t��8�t�C�u���XN��"��^�� r��	�u�컭!�l�f1�f��"����ASK ��EXTENDED ��EXT ��NORMAL   Q� r)��� ��kt� ��gt�
 ��mtNf���f��r��F��Y�f�   ��V����r6��@ufPF��fZr+f=   wf�f=   v�� �� uf�>�" uf��"^�[û� ����� RPfX�1�1ҹ
 �<9wH�<0rCuFII�<Xt�<xu�F1ۊ�� ��0r'8�r���8�sR��؃� [R���	�u	Z�r�F������QVW� � ,1�V�#��t4�F���ĊG����t< u�t+� u	�u[S�8�t�^��6V��^	�u�R�p�1�_^Y�[��- ,�6��>R�R�>e t9�t��I���;����boot:  Loading  BIOS data check  successful
 bypassed
 
Error 0x No such image. [Tab] shows a list.
 O - Timestamp mismatch
 O - Descriptor checksum error
 O - Keytable read/checksum error
 Kernel and Initrd memory conflict
 O - Signature not found
 
vga/mem=  requires a numeric value
 
Map file write; BIOS error code = 0x 
Map file: WRITE PROTECT
 EBDA is big; kernel setup stack overlaps LILO second stage
 WARNING:  Booting in Virtual environment
Do you wish to continue? [y/n]  
*Interrupted*
 
Unexpected EOF
 Password:  Sorry.
 
Valid vga values are ASK, NORMAL, EXTENDED or a decimal number.
 
Invalid hexadecimal number. - Ignoring remaining items.
 
Keyboard buffer is full. - Ignoring remaining items.
 
Block move error 0x 
Initial ramdisk loads below 4Mb; kernel overwrite is possible.
 O 24.2             &               �                                                  auto BOOT_IMAGE                                                                                                                                                                                                                               ��                                �N    LILO                                  ��  �  ��   �                  ��.�����-���1�1�1�� �� � �h~ ��L�  ��t0�����L�	j �6x �|	w��� �&�E�j ��x ��z �.�� �,
�ˎێÁ� � �9�v���� �V	�O �T	��)����Ӊ�f�> LILOuf�>�MAGEu�> un�>
 uf�����*�&�d� 8�t�1��df� f; u7�
��� $��#������
�� �����#r� $��fh���,�f;t�������N�����
s%� $��t�E2 tW�u6�6 ���u�_���6����
r%� $��t�E2 �tW�u6�6 ���u�_���6�޻ #��� d �  ��#��#��#�
r�  �?��u	�mk�l	�L�G �F��� �� $� 0���t%���������u���S� ��[C9�v��#����t��� ����f1�f������ �� 	������	r�>  td� u����$r=d�>��u&d��d��d��&f�?LILOud�6�&�< t�M� �< uC�����>  t,�U��#��#��#����1ۇ h � 1��'������m�����tS�[Cu��� &�<�t	&�F�������(�t�<	t�<?t��tf<t\<tv<tTw�<tQ<tM< r�w8G�t����t�0�CS�[���u��T� � $���E2 t��@8�u�} t&��6���{��� �� S����[s�Q�c�� ������� 0�������� ���u����t	�� uK�����f�<nobdu�| wd� �4f�<vga=u	�x����%f�<kbd=u���f�<locku�| w����O�f�<mem=u����< t��u������t:� ��o ����K����t	KS���[�����t�S���[K������ �>� u�� $1��~s� �r� @� �G2u��6��� $�޿���G�u�� ������t< u��< u�D� N�6��G2 t0�*s+� ��S���L�=P< r���X[<yt<Yt���G2�t�G2t�< u� S� ���r��U��� ��1�����<tD<t/<t+<t<tw�< r��� s�6�FG�*���	�t�� NO��GOt�� N�����m�1�A�m)�WV�
�
��^���*� �^_tAQ� ��1��Y��][	�t	�}�)�����=S�t�[S�^V��-1��; �? �������V���r�  ��#��#��#���6  �  �mX=��t=mku�  �?��u��  �P�6�� ,�����t����PX^VP��t�I���  �< t/� �It5f�<mem=u��< t��t�It< t���&�}� uOA�6����t����V	1��� ^����>� �t����� t&��S�� u�>� t�����V�_^1�&�u��T	������ÁÀ ��9�v����1�Q� Y��[�� t_&� �� t&� �; &� �? &�>  v��+V	�� "&�$ &� �^�6; �? P�X�? [�; �	�t1����  � �� �mh 1�� ���	 �a�g���� X�����LS�6�����P�@	�u	�u[XÃ��6�����P��  ��S���X���.��� t� �� K�������1�����V	� ,��+V	���&f�>HdrSt@d� �T	f�> LILOu!�>
 u�> u� � �T �*�V d��� �>? f���; f��f��f	�tf)�s�+��&�>r��f��f��f��f�&f�(�&�  ?�&�>" �}�5d� t���'�*��#�Id����
t&�  �����&�#��'� �����t����� ,��   � �[P��	�Xt�KS� ��1��@ ��[PQV��1Ɋ.��6> SQV���^Y[rX:&? u��)�LD��^YX�[P�8�&SQR�\��rZY[�� �r�s�� �����P���] X���' �[ ��  ���<ar<zw, �`�: �#���t�a�P��� X$'�@�-<
u��$ �
<uS��0��[�� C��u�ð� �
S�	 � ��[�R.��	�t��P�t.��� t��X�Zá � ��u"��	�t���t���$u��t�X��0��S� "�[d� t� u� ����Z ��$_u&��u ��	�t�>� u���u	��t�����j �f�p .f���p 4�r ��j f��&f�p �	�t����� �����Ü.�>���t.��u.���.f�6�ϋ � � � "����d� �u
� u� Ë�#��#��#d� u0��{ � s `��tP����X���U�������z�a����u����V�62�����s`��8 � aB	�u�^��  �c�� r� "��fh��� �f;t�	�v���t��`u
P���Y��Ê&����� t��@t��&�������t�j�����f`���r)� t"f�hXMVf1�f�ǺXVf�
   f�f9��uf@t�fa�P� t����`�d$t��`�4�u�X�U��VWSQf1�fHGOt� &�F��f���� ��sf3F����f��Y[_^�� Sf��f	��� d�  �� f1�f1�f1��f	�ttfRf� �  f�PAMSf�   ���fZr`f=PAMSuXf��uR�>�u�f��f��
f��f��
f�>�   r�f�>�  @ s�f;6�w�f��f�6�f��f	�tf��U1�1Ҹ���r;	�t��	�t��f��f��f��f� @  f9�wf�f���f   f9�uf�����f��f   f� <  f9�v2d�  uf�f�   �V	�>rf�,fKf��
fCf9�rf�[f��f��f)�f=   s�M��f�����; f�����? ��6��6���  �D2$ d ��$f1�f��f�f��f�  f��������	�tBVS���/���  [�J�f�>� t�T	f��&f� f��&f� j �  ��� ��^�����
LI0000� ��x[1���PR�j@[��.��[���t��.���R�����ZR��B���BB�$�ZR����Z��  �������� .��"����UWV��*f�f�uf�Mf�Uf�})�f��f!�fVf��f!�f	�f^f�řy�Z�t ��Pr�f��f1�f1�f�š��n�\ ��� r�f��f!�fQf	�f!�f	�fYf��$C�p�9 ��� r�f��f1�f1�f��*>�5�  ��@r绤*ffwfOfWf^_]�f�f��f��f��f��f��f��fŃ�@sf���*�6S��4��<f���*����<f3��*����<f3��*����<f3��*f��f���*[f���W� ��*f���f����f���_�U��W��*f�#Egf�E����f�E�ܺ�f�EvT2f�E����f)�f�Ef�E_��U��VW�>�*��?f�Ff�*f��* �v�@ )�9�r���*)�P�6��u��c�X)�����*���6�_^��U��VW�>�*��?ƅ�*�G)���8v�@ )����*��7��%��8 ��*)��	�8 )����*���f��*f��*f��f��f��*f��*���_^��VSR0�PQS�ր��� t9<w5P��U�A�Xr*��U�u$��t[YXPfj WQSPj��� B�w �d�o[YSWQPSRWQ��d r|Q�����Y���@I��?A��XZ9�sd��9�w^�������(���� ��Z[��XP9�r��P�� [^Y_r;ك� �[ � ǖ)�u��+�� U� `�sMt1��aM����f]�Y_��@Z[YY_[�YZ[^�  `1�1҇�*�tW	�t&�GG	�t8�u�&�_&��X#� f1��f�ty1ɿ *�� f�f	�tdWQ��� *)���It�f�u�.���]�Y_f�E�    �;�X#� ���/�f�u*�U�)���[S9�t�ށʀ�V��*�7CC9�t		�u�W��7^Y_A��r���#��#1�f1���s/f�fPf��X#� *� �f�u���Չ���� ��	2f��@*�fX����@r�a�O
Error: Duplicated Volume ID
 SRQWQ�����Yr!8�s�ʹ � �ʀ����r&f����f1��_YZ[�VPS��*�Ӏ�.�&���u
.�	�t	8�u���p�[X^�U��>2 ud d> �WQ�׃�����@*��B*N�~�Y_]�QVj &�>L 	�u;�ǁ� �s3��`r.1�� �<�u&�> �1�� �2�u&�=��F r��P v1�	�^Y�PU��V�  PU���
LILO      LiLo              j � ~� � �������H r�ð����R�A��U����Z��ث��r!��U�uR��W�H� �_������Z�`j`� �>bR����X��>d��j@�� �����u� ��Pr{���������wl� ������u_<r[W�4��V�!C� �6 �_�������� O�&�&�M�������Ou'��VEu!=SAu�O��&�����O��&����� 1҉>\Q�R����������Zr��y�yY�6RW���������_�����Zr���u�YP�x���������XY����W� ��y��`�^:Xw�y�B��>VW1��L� �_� )�fh����&f�  aÃ�1�����t< uN�1�<ar, ,0<
r
<r',<s!��r��r��r��r ���t< t<,t�ɻ�����t�< t���� �� �&��ڃ���>r� &;t&�� &�û��X뾃�V�^V�	�t,CC��*�'C�u
�t< t��8�t�C�u���XN����^�� r��	�u�컅�;�f1�f������ASK ��EXTENDED ��EXT ��NORMAL   Q� r)��� ��kt� ��gt�
 ��mtNf���f��r��F��Y�f�   ��V����r6��@ufPF��fZr+f=   wf�f=   v�� �� uf�>� uf��^�[ûg����� RPfX�1�1ҹ
 �<9wH�<0rCuFII�<Xt�<xu�F1ۊ�� ��0r'8�r���8�sR��؃� [R���	�u	Z�r�F������QVW� � $1�V����t4�F���ĊG���t< u�t%� u	�u[S�8�t�^��6V��^	�u1�_^Y�[��- $�6�����boot:  Loading  BIOS data check  successful
 bypassed
 
Error 0x No such image. [Tab] shows a list.
 O - Timestamp mismatch
 O - Descriptor checksum error
 O - Keytable read/checksum error
 Kernel and Initrd memory conflict
 O - Signature not found
 
vga/mem=  requires a numeric value
 
Map file write; BIOS error code = 0x 
Map file: WRITE PROTECT
 EBDA is big; kernel setup stack overlaps LILO second stage
 WARNING:  Booting in Virtual environment
Do you wish to continue? [y/n]  
*Interrupted*
 
Unexpected EOF
 Password:  Sorry.
 
Valid vga values are ASK, NORMAL, EXTENDED or a decimal number.
 
Invalid hexadecimal number. - Ignoring remaining items.
 
Keyboard buffer is full. - Ignoring remaining items.
 
Block move error 0x 
Initial ramdisk loads below 4Mb; kernel overwrite is possible.
 O 24.2                          �                                                  auto BOOT_IMAGE         �vԝ                               ��!�LILO                  �     ���м �RSV���1�`� �6�a��f�
�a�L�\`���u�� �v�Ѐ�0�x
<s�F@u.��f�vf	�t#R���S�[rW�ʺ Bf1�@�` f;��t��ZS�v�  �� ��f��LILOu)^h�1��� u�� ���
 ���u��u
U�I�� ˴@� �� � �N t��a�\����`UUfPSjj��S��`tp�� t��U�A�r��U�u��uAR��r�Q�����Y���@I��?A�ᓋD�T
9�s���9�w����������AZ����B[� `�sMt�1��aM��fPYX����da�f�f	�t
fF�_������� ��$'�@`� ��a�                                                                        �tbGCC: (GNU) 5.3.0  .shstrtab .interp .note.ABI-tag .hash .dynsym .dynstr .gnu.version .gnu.version_r .rela.dyn .rela.plt .init .plt.got .text .fini .rodata .eh_frame_hdr .eh_frame .ctors .dtors .jcr .dynamic .got.plt .data .bss .comment                                                                              8@     8                                                 T@     T                                     !             x@     x                                 '             �@     �      H	                          /             �@     �      z                             7   ���o       R@     R      �                            D   ���o       @           P                            S             h@     h      �                            ]      B       @           p                          g             �@     �      $                              b             �@     �      �                            m             `"@     `"                                    v             p"@     p"      .                            |             �PA     �P                                   �             �PA     �P     ��                              �             <�A     <�                                  �             H�A     H�     |%                             �             b                                        �             (b     (                                   �             8b     8                                   �             @b     @     �                           q             �b     �                                   �              b           �                            �              b           ��                              �             ��b     ��     �B                              �      0               ��                                                        ��     �                                                                                                                                                                                                                                                                                                                                                                                                              ./.wifislax_bootloader_installer/syslinux32.com                                                     0000644 0000000 0000000 00000276504 12721171720 020665  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ELF              ��4   |w     4   	 ( % "    4   4�4�               T  T�T�                    � �L<  L<            ?   � � �  ��           4?  4�4��   �            h  h�h�              P�td�6  �����   �         Q�td                          R�td ?   � ��   �         /lib/ld-linux.so.2           GNU               %   *       !                          #   (       &                '         $                         )             
             "      %                                                                       	                                                                                                   h              �   @c     �              �              0             "             |              o              &   Dc     ;              4              �   Hc     -              �              5                           A              �              �              �              �                           @              !              �              �                 $�     �              �              )                          �              W              �              H              �              �   `c     v              }              �              P               libc.so.6 _IO_stdin_used strcpy exit optind perror unlink popen getpid pread64 calloc __errno_location open64 memcmp fputs fclose strtoul malloc asprintf getenv optarg stderr system optopt getopt_long pclose fwrite mkstemp64 fprintf fdopen memmove sync pwrite64 strerror __libc_start_main ferror setenv free __fxstat64 __gmon_start__ GLIBC_2.2 GLIBC_2.0 GLIBC_2.1                                                            ii   O     ii   Y     ii   c      ��  @c  Dc	  Hc  `c%  �  �  �  �  �   �  $�  (�
  ,�  0�  4�  8�  <�  @�  D�  H�  L�  P�  T�  X�  \�  `�  d�  h�  l�  p�  t�   x�!  |�"  ��#  ��$  ��&  ��'  ��(  ��)  S���g  ��GG  ��������t�R  �-	  ��   ��[�   �5��%�    �%�h    ������%�h   ������%�h   ������%�h   �����%�h    �����% �h(   �����%$�h0   �����%(�h8   �p����%,�h@   �`����%0�hH   �P����%4�hP   �@����%8�hX   �0����%<�h`   � ����%@�hh   �����%D�hp   � ����%H�hx   ������%L�h�   ������%P�h�   ������%T�h�   ������%X�h�   �����%\�h�   �����%`�h�   �����%d�h�   �����%h�h�   �p����%l�h�   �`����%p�h�   �P����%t�h�   �@����%x�h�   �0����%|�h�   � ����%��h�   �����%��h�   � ����%��h�   ������%��h   ������%��h  ������%��h  ������%��f�        �L$����q�U��WVSQ��$  �Y�1�o�����e���ePj SV�  ���= � uPPj j@��  �= � u-�=� u$�=� u�=� u�=� 	�=(� tPP�5@chP������   ��h����������Å�u�K�WWj�5 ����������t�����y���5 ���   ������VVP��t����|  ����x׃=,� u:������% �  - `  � ���t#S�5 �h���5@c�.����$   ������1ҡ$�RPh   h�c��t����  ��j h�c�  ����t	��P�  ������QSh۪P���������x
��������u	��S�z  ��P���������xHRRh��P�8������Å�t21�PP�$�RP��t����5�eh��S�m�����S��������t��������똃�S���������u�Wj������hX���������t���5�e�
����������h�e�`  �$a��l���[^h��h���������Å�u��h���o  �=��PWjh@��������9�u�Sh   jh�e������=   u���S�E������u��ą�u����  P��	PjW�����ZY��p�����t���h��{  j ��h��j P�2  ��1�PV��  ����	�t 9�}��p����ىT�QRPVC�  ���ڃ�V��  ^_j �5��5��5�S1���p����  �@��  �� ��	��l���;�l���}N��p����5$���1��T�����	��	��h�����CRPh   Q��t����A  ��h�����   �� 몋5����'  ������QQhΫS�������v������   ���������tq��/t��\u�ɹ   u[�F��'t1ɀ�!u:1�9�sG�P� '9�s3�P�@\9�s(�P��p�����P9�p���s�@'���9�s�@�
�����p���F뉅�u� /@RRhӫP�������������Sh�V������4$������Sh �V������4$��������u�ą�t P�5�eh"��5@c�c����$K��WShk�V�����4$���hK��������u�ą�tS�5�eh��5@c�������������������1ҡ$��$Ph   h�c��t�����  ��jh�c�  1ҡ$��$Ph   h�c��t����i  ����t������������e�Y1�[^_]�a��1�^����PTRh��h �QVh0��d����f���$�f�f�f�f�f�f��Cc-@c��v�    ��tU����$@c���Í�&    �@c-@c���������t�    ��tU����D$�$@c���Ív ��'    �=dc uHU�hc��V�(�S�,���(���K9�s��t& @�hc���hc9�r��I���[�dc^]Í�&    ��'    �0����u�P����    ��t�U����$����6���U����u�5�eh,��5@c�G����$   �����U����@������0�����$�u�5�eh(��5@c�
�����j����U��WVS���E�    �]�u�}��tW��WVS�u�u������ ��u
��h4�����u������ ��tɃ�P�'����$�9�����E����E�)�륋E�e�[^_]�U��WVS�u�}���e�����ӡ$��1��ډE[�U^_]�M���U��WVS���E�    �]�u�}��tW��WVS�u�u������ ��u
��h?�����u����� ��tɃ�P�t����$������E����E�)�륋E�e�[^_]�U��WV�U�E��u!�Ǿ@��   ��Z󤾚��i   ����*��u%f�@���Tf�P�����B���  �P����^_]�U��WVS��,�u�F<�t���<���  �F=   t,�� �������   ��  �H�����  ����  �Ff��u*�~ u$�~ u�~ uf�~ uf�~ u
�~  �6  �N�#��Mׅ��z  �Y����o  �V1ۉх�u�N 1��~1�)�ӉM�1҉]�f�}ԉ}��E�    ����u�F$1��N�M������e��M��)��]��FӃ���	�)�ӺB�����  ��u�F$1҉E؉U܋E��}��e��}��U�E�}�1��E�E���  �E�1�RPSQ��  ���ÉU��� �G  |=��  ��   ��f�}� ��  �~&)��   �~6Pjh��W��������u!�}� ��   ��   ���  ��   ��   Pjh��W�O�������u!�}� ��   ��   ���  ��   �   Sjh��W�������������   Qjh��W���������t]�V:�F6�����������   �}� ]|=���wT�L��~B)��   �FR�U�Rjh��P�������L�����   1҃} tx�E�    �m���f�í�_�d��X�^PjhʮS�^�������t/Pjh��S�I�������tPjh��S�4������s���u1҃} t	�E�    �e��[^_]�U��WVS��\�@��=���u���  ��	�EЃ�;E��  �;��>t�����K�M���@��M�N�U�M؋�R�} ��@��M��Q�M؉�@��N�M�t�M��Qfǂ@�����P��}�f�Sf�C
 �{�} tf�C �}��W
��@��}��}��O9�~QQ�5@chӮ�  k�
1��}��E��E�    H�E�    �E��E�    1��E� �  �Mԋ}��Q@��	9��U���   �}ԋMԅ��|��}��|��}��   ��   �x1ɉ���	�U���U�M܉U��M��M�3M��M��M�3M��ʋM�	�u�}���  w�MȋU��T
�3Uā�  ��t�}��U؋M܉�Of�G�   �E�
��E؉E��E܉E��EȉEĉ��}��}؋}��}܋}��Eԉ}��,�����t�}��U؋M܉�Of�G�}ЋE��} ��@��������|�t��@��u���D��|�t��H���L�tM1�����}�E�����@��9�~RR�5@ch���6����$   �j����E�u�P��@����} t>1�����}�E�����@��9�~PP�5@ch-�뫋E�u�P��@�����C    1����>;E�}
+�@�@��ẺS�������e�[^_]�U��SP�]��tprO����   Q�5�eh���5@c� �����hK�hN��5@c����XZ�5@chM��F������tP�5�ehX��5@c��������   Q�5�eh��5@c������hK��t��tjPhK�hN��5@c����XZ�5@chM����������uPP�5@ch�����������uSS�5@chE����������u�����QhǮhN��5@c�-���XZ�5@chM��U��VS�u�]���e��j h`�h@�V�u������ �����  ��f�  ��   ��M�)  5����  H�}  ��   뤃��-  ��H�  �Z  ��U�  ��O��  ��S��   �8  ��a��  ��d�&  �`c���J�����r�  5��i�"  ��h��  PPSj �  ��m��  ��o�  ��  ��u��   ��s��   ��t�&  �  ��v��  ��z��  ��@   � �    �����,�   ����Pj j �5`c�z������ ��P���>�����P�5�ehl��3Pj j �5`c�H��������P����   �U���P�5�eh���5@c�J����$@   �������   �#�����   ������    ������   �������uP�5�ehϳ�5@c���������`c�������Pj j �5`c�������$�������W������`c�(������0�   �}����4�   �n�����tVV�P�`c� ��V���Q�5�eh��5@c�K����$    ������5Hc�5�ehF��5@c�#���XZSj@��������Dctr��u-�P���Dc� ���=� u�P���Dc���Dc����t��u@�8��Dc�Dc�<� �:����e�[^]�U��W�=� St��h�e��  ������u1��:1���������IPRQj�   ����t�P����5�eh_��5@c�E������(���t:��1�������IWRQj�q   ����tP����5�eh���5@c�������e���[_]�U�g���WV��� �/-Z�   +��=�  u�   �Vǆ�  d�(ݹ�   ���^_]�U��WVS��  �EH=�   v�����    �   �}�   wo��������e�}   ����  ��C����t89Mu$9�s/Q��)��QPS��������������������9�w)�Ã�w��j�} t:�E��9�v�����    ����R�E�M��C�K�ǋu�M�+U����1��щߍ�����󪸨e�}   �Ǹ�e������1���} t�랍e�[^_]�U1���WS�}   �U�Z����[_]����U��WV�E�8�/-Zu:���  d�(�u.1ɺ   �����  u��g�u��   ��   �׉��F��   �/-Zu@���  d�(�u4��   1ɺ   �   �����  u��g�u��   ���1��
P�D���X����e�^_]�U��WVS��(j@�1����Ã�1�����  �E�C<    ��E�CPj j S�  �����L  f�x �@  �p�E�    �   �M������9�t�E�}�	u��  �p�}�S�{��u�p �u��E�    �U؋M��x�S4�K8�P1ɉS�K �}���u�x$�}��p�u�1���p��S$���K(���  ��	�����ωs,�{09}���   w	9u���   �U؋M�)���։ϊM������� t���V���  �Sw���C    ����%����  w�C   �������w1���C   ���  ��	9U�r�{u�@,�C��C    �����S�������1��e�[^_]�U��S���]S��   �]���]������U��WVS��$�u�u�}V�  �U�E��E��E���   �}��u�}��u����   Q�u��u�V�   ���Å�t�1҉U�RjWS�s������U܅�u=�} t"�M�ރ��Ϲ   �M�u��}�1�y�Q�{ t9�S�C����*�; t �� �� ��   u�P�u��u�V�D  �F���������e�[^_]�U��SP�U�B<�B<    ��t���XP����������]���U��WVS���]�u�}�C<��t9xu90u���   �@���h  �0�������u ��S�����$  ������1���tI���J�U��M�WVh   Q�s��� �M�=   �U�t��R������1���C<�2�B�z�S<�ȍe�[^_]�U��WVS�M�]��u�K��u�C$�S(�*�������~ 9K~�A��K������� t��1�C,S0[^_]�U��WVS���E�U�E�E�M�Y0�I,9�r>w9�v8�}�;W(w��  ;G$��  ���� 9���  r9���  1�1��  �Ɖ�)�߉u؋u�]��Ӌv�}܍N���t���� �T  �E�U܋H�E������� t�ЍX�E�;X�(  �@����   r����   �  �ߋM���V�1҉���	AQ RPQ����������   ��G���  �u�Q�E؉���	1�FV RPV�����������   ���  �M��8��	ʉ�%�  ��t����=�  �iۋu��R��	1�FV RPV��������tb���  �=��  �6���u�P����	1�FV RPV�W�������t.���  �%���=���������E�E�E�e�[^_]���������e�[^_]Ð��<�\$,�\$D�T$L�t$0�L$@�|$4�t$H�ۉl$8����   �L$1��\$�������   �D$�͋T$�ƉD$�ЉT$�ډ˅ҋL$u9ŉ�ve��1�������v �D$9�v01�1Ʌ��ȉ�t�؃� �ڋ\$,�t$0�|$4�l$8��<É���'    �ڃ�ux9�r1�;l$w��   빐�t& ��u�   1����Ët$1҉���Ɖ�����돍v ���׃� ���=����v ��'    �ٿ������ �ۉL$�\$������&    �    ��)؉�������	ыT$�L$������l$����ى��֋T$�����	։���t$�Չ��d$9ՉT$r�T$����9�s;l$t	��1�������N�1������f�f�f�UWVS��������&  ��,�l$@�|$D�q����� ����� ���)����T$t'1����&    �D$H�|$�,$�D$��� ���F;t$u��,[^_]Ít& ��'    �f�f�f�f�f�f�f��S���D$$�s�����S&  �$   �D$�D$ �D$�������[á ����t%U��S� ����v ��'    ���Ћ���u�X[]�S���������%  ������[�            %s: %s: %s
 short read short write /tmp At least one specified option not yet implemented for this installer.
 TMPDIR %s: not a block device or regular file (use -f to override)
 %s//syslinux-mtools-XXXXXX w MTOOLS_SKIP_CHECK=1
MTOOLS_FAT_COMPATIBILITY=1
drive s:
  file="/proc/%lu/fd/%d"
  offset=%llu
 MTOOLSRC mattrib -h -r -s s:/ldlinux.sys 2>/dev/null mcopy -D o -D O -o - s:/ldlinux.sys failed to create ldlinux.sys 's:/ ldlinux.sys' mattrib -h -r -s %s 2>/dev/null mmove -D o -D O s:/ldlinux.sys %s %s: warning: unable to move ldlinux.sys
 mattrib +r +h +s s:/ldlinux.sys mattrib +r +h +s %s %s: warning: failed to set system bit on ldlinux.sys
 LDLINUX SYS invalid media signature (not an FAT/NTFS volume?) unsupported sectors size impossible sector size impossible cluster size on an FAT volume missing FAT32 signature impossibly large number of clusters on an FAT volume less than 65525 clusters but claims FAT32 less than 4084 clusters but claims FAT16 more than 4084 clusters but claims FAT12 zero FAT sectors (FAT12/16) zero FAT sectors negative number of data sectors on an FAT volume unknown OEM name but claims NTFS MSWIN4.0 MSWIN4.1 FAT12    FAT16    FAT32    FAT      NTFS     Insufficient extent space, build error!
 Subdirectory path too long... aborting install!
 Subvol name too long... aborting install!
 Usage: %s [options] device
  --offset     -t  Offset of the file system on the device 
  --directory  -d  Directory for installation target
 Usage: %s [options] directory
  --device         Force use of a specific block device (experts only)
 -o   --install    -i  Install over the current bootsector
  --update     -U  Update a previous installation
  --zip        -z  Force zipdrive geometry (-H 64 -S 32)
  --sectors=#  -S  Force the number of sectors per track
  --heads=#    -H  Force number of heads
  --stupid     -s  Slow, safe and stupid mode
  --raid       -r  Fall back to the next device on boot failure
  --once=...   %s  Execute a command once upon boot
  --clear-once -O  Clear the boot-once command
  --reset-adv      Reset auxilliary data
   --menu-save= -M  Set the label to select as default on the next boot
 Usage: %s [options] <drive>: [bootsecfile]
  --directory  -d  Directory for installation target
   --mbr        -m  Install an MBR
  --active     -a  Mark partition as active
   --force      -f  Ignore precautions
 %s: invalid number of sectors: %u (must be 1-63)
 %s: invalid number of heads: %u (must be 1-256)
 %s: -o will change meaning in a future version, use -t or --offset
 %s 4.07  Copyright 1994-2013 H. Peter Anvin et al
 %s: Unknown option: -%c
 %s: not enough space for boot-once command
 %s: not enough space for menu-save label
 force install directory offset update zipdrive stupid heads raid-mode version help clear-once reset-adv menu-save mbr active device        t:fid:UuzsS:H:rvho:OM:ma        ��        f   ��        i   ô       d   ʹ       t   Դ        U   ۴        z   :�       S   �        s   �       H   �        r   ��        v   �        h   �          �        O   �           �       M   '�        m   +�        a   2�                          c��Q   c��Q �  ;�      0���  �����  z���(  ����D  ����`  _����  �����  ���(  q���P  �����  �����  �����  8����  ����   /���H  8���t  X����  �����  �����  ����  ����D  ����h  �����  �����  �����  p���(  ����d  ����x         zR |�         $���@   FJtx ?;*2$"   @   J���+    A�B      \   Y���;    A�B   (   x   x���    A�BF���r�A�A�A�(   �   ����4    A�BC���c�D�A�A� (   �   ����    A�BF���r�A�A�A�@   �   �����   D Gu Fupu|uxut�� C�A�A�A�C $   @  ����_    A�BB��W�A�A�,   h  ���"   A�BF����A�A�A�   ,   �  ����   A�BF�����A�A�A�      �  ����1   A�BB�(   �  ����v   A�BB��n�A�A�   $     8����    A�BI����A�A�$   8  ����D    A�GB��w�A�A� (   `  ����	   A�BI�����A�A�A�$   �  ����     A�DB��R�A�A� $   �  �����    A�BB����A�A�,   �  3����   A�BF�����A�A�A�         ����    A�BD�S��  (   0  �����    A�BF�����A�A�A�    \  Z���.    A�BB�h��  (   �  d����    A�BF�����A�A�A�(   �  ����N    A�BC���D�A�A�A�8   �  ����   A�BF����
�A�A�A�EI�A�A�A� (     �����   C@D�T��J��
����J  8   @  @���e    A�A�A�A�N@NA�A�A�A�   |  t���          �  p���0    A�C jA�                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ����    ����                 ��    �   ��   l�   ̂
   m                   �              ��   p�   (         ���o0����o   ���oچ                                                    4�        ����&�6�F�V�f�v���������Ɖ։�����&�6�F�V�f�v���������Ɗ֊�����                                        filesystem type "????????" not supported                                                ����                                    �X�SYSLINUX                                                                               ��1ɎѼv{RWV���&�x{�ٻx �7�V �x1���?�G�d��|�M�PPPP��b�U��u�����Ov1���s+�E�u%8M�t f=!GPTu�}��u
f�u�f�u��QQf�u��QQf�6|��� r �u��B�|��?�|���U�A�� r��U�u
��t�F} f�ﾭ�f������ �� f�>���Bout��f`{fd{� �+fRfPSjj��f`�B�w fa�dr�f`1��h fa���F}+f`f�6|f�>|f��1ɇ�f��f=�  w��A�ňָ�/ far���1��ּh{��f�x ��}� �t	�� ���1�������t{��Boot error
                  ��>7U�
SYSLINUX 4.07  
    ��>��Bo             �0�5�  �� ��� ��|��f��M�f�f���f�(�f�޾恀>F} u����� �6 0�OSf�6 �I�*f�f�Tf�l)�fSf����1��K f[�.|f��
��^f�|��f�$�f)�f�(�f��u�ځ� ��fIu��f!����ׁ�� ���f`f`{fd{�QU� f��� fRfPSWj��f`�B��fa�dr]f�f�� )��>|�!�u�fa�f`1���fa�����Q]fRfPUSf�6|f�>|f��1ɇ�f��f=�  �<��I )�9�v����A�ň֕�� f`�D�farf���|[�]fXfZf�)�u�fa�Muٕ�.,�u����;.,�v�.,��f`� �t	�� ���fa� Load error -  CHS EDD                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   1�������J��ӷ�D�f1��|�8� �Nf�0�f����fh��  �f=�u  �����!��0	������8�u3�f�_4 f��
9�s#����
R�� d]���D[X�� d$���D"�����f`f��h �t{f�`{f�d{�6|�>|f�.,�fhx �fa��}�骸�)��fhR �{t�~���H�� ��1��1��ar������8[u�>�R ���>�R���>�R �{���_!��8 � ���t����f��Rf��8f��Rf��8��f�&�8  ��� <tA< rw�� �t���8�� ����sҪ�� ��<�><	t8<t-<t<�� <t<u��� �t�O���� ��� �d���^���8��>�R u�W���� �� f�6$�f;68<v2Qf��  fhW �h)�YV�� tWQ� ��&�Y_u
� �G ���y ^���f �r0�&�8<0r�t <9v<ar�<c�{�,W�$�
� ,1���<Dw,;�c��<��[�<��U�,{W��<=��= t2�Ft-� �T�W���� �6 0� �ӷ������_W� � ���_���>�R u������>�R ����c��ɿ �� �f����� �t�0��� ��<IVfh� �w^�< w� �t�< v�N�6�8��R!�u�f�6$�f;68<v_f��  fhW �?)�V� ��< v�t�^�ـ= u�^h � ��Ӌ��&��>�R�<IW�ҹ �_1۠Ӣ�8<����s�)�>�R tiVW� �Ǿۿ ���R�&��>�R_^��8�<J �<I�= v:0��� �uO�>�8�ȹS�<Ifh: �[�� f��6�8f��D ����ܹv׋�R!�u����<I��z��a�� �VWQQW�_[t��ۍ������E �1���Y_^����7��/�����6���`u+�X;��t�f��8tf��8u�Y��� ���R��f�Y�e�Ë6�8f��8f`1���8��8f�8<f��8faWP�<I0�� �uOf�M�X_�>�8���\�f��    f��.com�cf��.cbt�Xf��.c32��f��.bss�/	f��.bin� 	f��f��.bs �	f����.0�	� V��fh4 �M^�
��������m���Vh �
� �1�^fh �#�� ���&�>�U����V�>�R�ش� �<I��&�E� ��6�8�� �&�G �t~< v�O����WF�u&�E�<=t�� wX�&�G< w���_�FF��&�E����==ntK==etK==at�==ct��r&�����rf��8���8 É�&�= w1���8Á� ��>�8f��8���7&f�>HdrS�&���8= �=r&�$��&��=r	&f�,f��8&�1f1�&f�&�
�8&���8�p���<I�&��!�u�@��8�f�6�8��	f� �  f)�f��   f�   ��^!�t���f���� ��f�>�8� ���z��<W�>�8��	f1�� �)����f�_f��8f;�8wf��8f1�9�8t�J�A�|��� ����&�>� u&�� ��8��8t��rdf�( � �t���d�$���T� �� �d�  ?�d�>" �t����� ��rd�$��vdf�( �	 ����89�v���d���>�8�� r&�>� 1ɌÎ�f�   ��8u"f�  	 f�f�   f�f��8f�Af�   � �f��f�f�   f�f��f�8f�A�>�8 tdf�f�f��8f�df�f�Afhn�  Q��8 �����؎м��������� Pj �1�9�8t����!��8��8�!�� ��.f�>�8.f�>�8.�6�8��<,t< v��PV�D� ��W�<Kfh� ��_�/ ^X�D�<,t�.f��8.f+�8f�.f��8% �f)�% �f���Ȏ؎�fW�<Kfh: �f_t%V�n��0 �<K�* �y��$ ^� ����f��8þ����<K��z��X��8 ���fho �I�ѵ�s��V���h � ��1��@ f1��f�&�  � ���&� � ��} �� � �&� �t�������,�&�� ^� � �fh ��f����  w����؎�1�j �  �P9�  Qf�j �f�����O�E��f�)��Y�� ����8f�f�CCf�D����`��8�� �  �f�a����f`��͎ݎŉ��d�
 �D��:F�����Љ��F,fa��ϋFf�v(j!Zf_���hs��$��� �3��� �*f����K����hx�1�[1��ގ�f�&��f�� � ��fhg ������<I�#�������e ����ÊF���ÊF�����J �ÎF&�v&�<$t����À>�� u�����ȈF��f�F  SYf�F  SLf�F  INf�F  UXÀ>�� u�� �u�&������Fà����������9����L����f`��͎ݎŉ��+��%r1�����b�������F% �F�F1 �N�^$�F���F Է�Î^$�v�0�Î^$�v� ��h/����h������U�ÎF$�vfh� ��f�F�N�vÎF$�^�v�Nfh� �s1��vf�NËvfho ����F1��R�F�t{�F�N"�Fp{�N �F `{�N$�Fx{�á���F����F�����&������Ru�̀�F��f�h{f�x �d�ÌN$�F�9�ÌN$�F  �F  �����ËF��N$�F���F �ÊF<�� ��8�^$�v����^&�v�<Ifh� ��fh: ������6�8f��8��� �¾ѿ ��y&�E�  �>�R��8�����F��w�t��N�V�LL�NL�u�l���àb� �t�`��F$ 0�F  �F�f�~  uf�Ff�V�F$�^�n�y����Ì^$�F��F�Ã~ u�F �F �N$�F<<��ÌN$�F�����F�����f�~ f�vf�N�VfP�{ � �� �� ���RA)��d��<I� ��� �f�   fX^1һ����f�   f�   f�   �f�> ��L�u�>!uf�8<1�f��f�   ��<I�����9�� ���>�R� �6�8�*O�>�R&� ��j �j3f�   f�>f�  
 1һ���Zf��   f�>f�� �	 �� f� |  f� f1�Yf�|  f�  �fPf1�f1�f�h{f�x �t{�x{��W� 1��^1�f� ff�f��
f)�f�f��f�j�'�� 1��؎��x{W� �_&f�U&f�u&�]�p{�r{&�E&�]XWf�   k�W�f� SPf�1�f�f�_���	 �f�f1�Y���	S�Sf�S��	Sf�&Sf�   f���N�3�0��&V�z����^���Vt`�<t<taþl��x���ј1��؎�f�&��f�� � ������R!��v���f`1�1���3��fa�!�����>�}t
�%�$�������fh: �	tS�x������:r�x��71��G�G@[�fho �t	1�[�SVW�>x��]!�u� �ƃmr�u&�F�u�_^[�K�A�]��f`�����:���]�5!��ut� fh �	�M�5�fa�fa0���P��r���X�SV�x��7fho �����x�^[�WS�>x��]�AC�][_��Z�r<t	<
t	< v��8����ÿ�:���:sW�7�_r�<-s���� ��:fPfQUf1�f��f��1�<-u����<0rSt<9wM�
��<0r% <xt<7w:���0��@ r8�s
f��fì��N� <kt"<mt<gtN!�tf���]fYfX����f��
f��
f��
��<0r<9w,0� <ar<fw,W����*��t+r&��RW�y�_Zr< v1Ҫ��<
t<t �u� B������ �u� ���������ù � ��r�3�s� �<<�@ �f������;��;�`��r<t�t���A��;���m�<tg<tZ<
tf<�� <tM<�<�� s<�+�/��;t/��Rt(��;�>b�	� ���;@:�;w%��;�>b��;��ø1�����;�þz����;t���; ��;@:�;w��;��1ɋ�;�6�;�>�R��믾}��� ��;t�1ɉ�;��;�>�;� ����r/����;t��;��;-���r�r��;t�;���;U���L�!��;��;M��<
t< v�>�L���Ms�G�>�L��
��6�L� ��L��Mfh� �,��t��+	`�>b����;a�$��;���;t-f�f`���!�tP�&���W� t�B� �8�u���X���faf����;t
� �t������f`��u*���!�t"�4<�;2<u���tB�&��� �8������fa���m��uD���!�t�4<�;2<u�W�t�B�&��� �8�u�0�����(��� 2�؊C����4<���<�u0� �t�<<���
.f�6�;�x.f�6�;�p.f�6�;�h.f�6�;�`.f�6 <�X.f�6<�P.f�6<�H.f�6<�@.f�6<�8.f�6<�0.f�6<�(.f�6<� .f�6 <�.f�6$<�.f�6(<�.f�6,<� �PR.������uZX��W� 2��.�>2<.����.�&�����P �8�u���.;>4<t.�>2<X�u�_��f`� �  ��;� �f���� �f��  � f���  f�������� f���������0<�W���怍W����䡈��!�6<��1��!�fa�f`1��؎��0<!�t7�W���怍W1���怡6<�!��桾�;�  � �f���� �f�1��0<fa���f`� 2��f1�.f�2<� 1��f�fa��Ff1��乿�R�
 �f��<<0��Ū����f�$�f�8<�;�R�L��R���S��E� ÿ��H���	�>�Rÿ��9����>�RÀ>�R w���#���ۉ>�Rÿ�����Ӄ�u	�>�-u1��>���@��>�R t	�����À>�R t������fh� ���P��^rf��*�f��f�f��P���^r��P��<Jfh� �fh: �uX�P��<Jfh� �{���uX���R����� Sf1�f�����r1�w���r)fS��r�h���s1ۀ����>���߁�����f[�f��%  _f��K�� f� � f�f�󣂶P��w�狽 �>�����U�����X�����B����怰BB����<u>J�����<�s1����BB�����怨t�O��>�� t��� �������ӷ�������  �P� _fh� ��� �<K �ѹ1���e �ѹ� �< v�����R�ѿ�fh� �G�ۿӋ�R�����/ �`
�P
� �# r f�f%����f=ENDTu�f�f%��� f=EXT u�ÿ W��� ^ÿ�1��
��n s������Ru�>�R tQ��>Ӏ><K t���� �<K�&�E� ��-ӣӹ )�1��f��  f�>8<f�
  fh� � f�>8<þ���	��s ��tlr�<#t� � f�����rW< v� f��0����p�1���~�t=r%�c��H��0 f�f9�t&f�������]	� �W	�G	뢾ն�L	� �F	�6	딭�����<
t��s��f�f`�����f���  �����faf�� �f1��،Љ&8�
8f��f��f���d �m��`�� �"���  � ���؎Ў�����1� �$�"��6�  .�&8f��ڎ����.g��    f�A�  �~�f`.�@L��s un.�&�.��o��$����[ uV�� uO.�������d�s ���`�l ���d�e Q1��0 u*��Y.�����$��Q1�� u��Y.�@Lu������Yfa�QfP�����.f�<L�  �fA�
C.f�<L��&f;LL��fXY�0����t �u���d�t���`��u����f1��0�0Sf�j �z� Q�  �?�G  f�G �  ��f�f  �����E��f�4�  f)�f�U�f   �Y��É���,�DL��faf��.�&DLf�f`��f��  �0�f��.�&DLf��f�6 ��g�fh�  ���f�f�ûƯ��fUf�.�8fhx ���f]pþ1������� � ��r� =6u�<w�1ۊ>��r؀� wӿ ����r���� �>`�� 0���  �����f��b��t��t���b�tH� 0�Ž  �>`�0��t�t 1Ɉ��NL���H��;�!��LL��H��;ù 1Ҹ�0۸�`�� �u���;���̈&�;a��h�u�8 �PL�x���r|f�>PL=�uq�XL�1۹ ��VL�`��H��1�:�;r��;�Ȉƴ1���VL��L  Q��NWW�� f1��f�_�TL�% ^�`QW���l ^� ��ǋ>�L�~ ��LPY���h�1��4 8�t���Iu��1��$ �tQ�و��Y)�w���� ���
 ��Ã�����t������������$�1�AVU� �����Ku��G��w�]^��v�ú���BH�W� �f�_�<v���t�<t@�t
�O� ��� 1������w%� ��c����t�f�LL���+���R 1��f`�Ȏ؎��t� �t�t�O� �� ��t� ��R���fa�f`�_�f`� �>t�u
�	� � �fa�f�f`f��R  ��f��R   ��R1��
 �f1��f!�t}f� �  f�PAMSf1ɱ��R�sf!�u`�uf=PAMSum��rhf�>�R w�f��Rf�>�Rtf=   r�f;�Rs�f��R�f;�Rw�f�Rrf�>�R tf���f;�Rv�f��R�o�f��Rf;�Rvf��Rf=   w8���r= <wr��f��f   ����= 8v� 8f%��  f��
f   f�$�faf��P�� �u�X�fP.f���.f�x�fX��fP�Ȏ؎��X��u%VQ�~��7���
� 6��JIt� �����Y^�f���f+x�f��r	fhO ���fXÀ>������>"�r&f�`{f�d{f��f��f��f���t{����Y�>���t� ��9 t,� ��1 t%� �f��/-Zf�f�g�f�f1��} �f�f�d�(�f�ÿ ��� �f��Vf�f=�/-Zuf1ҹ~ f�f���f��g�uf�f=d�(�^�P��1��8�t �t�Ɓ���r��
����=��v1�X�PVW �uYQ��1��8�t �t#�Ɓ���r����|�Wƹ��)�r�%^��^�NY���΁���s�ވЪ�Ȫ�d����)�1���_^X����f`���} f1�f�f���f�g�f)Ѝ|� �f�D�� �f�fa�fPf���f��tf���f��t�>���t���� �fX��fX�P�� ��XÈ&�Rf`��U�A�������r��U�u��t�˪f���f���� �� f���f���� �� fa�V�� fRfPSjj��f`���� @
&�R�fa�dr^����^�fRfPUf!�us��� �y��r �u��Bf����?f���:t{uJf�6|f�>|f1�f��1ɇ�f��f=�  w)��A�ň֊����&�R� f`�far]fXfZ^�Mu����f�p f���f�p ��  �f���f�p �.f���.�����.f���6�    ���f�.�t�t�i�.��Rtf`��.�>b�faf��P�����
���X�f�f`� �t����faf��f�f`f��� �f�f`f��� �f�f`� f��fP$<
s0�7��fX��faf�����1Ҏڎ�f�&��f�� � ����꾶�������t9��0�R1���� � � `�asMu��$�Z�� � |� �f��Ѽ |� |  ���              j Th   �5��  h0�  �   ���E$1�� v ��  �8  ��  �0�  ���  ���E)t��U.f�΢� 1����� а(���؎а ؋%�  �������%�  ��   `�t$ �J�  ��a���f�UWVSQR����t$(�|$0�   1�1۬<v,�"�   �F�t�D�f��F<sA�t����1���!������Iu�)�)ǊF<s�����������F)
���n<@r4�����W��������F)�9�s5�m�   �F�t�L$1���< rt��t�Hf��W�����)�9�r:�D���������Iu��1ۊF�!��?����ƉǊF�w�����&    ��)����ԁ��   �F�t�L��v <r,��������t߃�f����� �����t+)��z����t& ����W���F)��Z�_���n��������T$(T$,9�w&r+|$0�T$4�:�؃�ZY[^_]ø   ��   �ܸ   ��         SRP���t~9�r.����s�I�ȃ�r��sf��������tf��t�XZ[ÍD�9�w���|��Ɖ���r�INO�ȃ�r"��rf����������������tf�FG�t���1�����s�I�˃�r��sf����������tf���t������T����;�����  ��)�b   ���  ������  ��`�  �R�;�s�K����������Z0Q!�t����f�Bf�B���B�b�B�b �$��f� �ڎ����                  / `�    g � �  ��   �  ��   �  ��   �� ��   �� ��              `{    �7�0 �1 ��  ��3                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                It appears your computer has only 000K of low ("DOS") RAM.
This version of Syslinux needs 000K to boot.  If you get this
message in error, hold down the Ctrl key whilebooting, and I
will take your word for it.
 XT  
SYSLINUX 4.07 2013-07-25 No DEFAULT or UI configuration directive found!
 boot:    Invalid image type for this media type!
 Could not find kernel image:  
Invalid or corrupt kernel image.
 �|�_�c�_�s�v���\�
Loading  .. ready.
 Cannot load a ramdisk with an old kernel image.
 
Could not find ramdisk image:  BOOT_IMAGE=vga=�mem=2�quiet=�initrd=C� ��+�d�\9`9d9h9l9X�^�x9|9�9^��9^��9�9�9^��9�9�9�9�9�9�9�9�9�9�9�9 ��ʓؓ���	� �0�L���_���������ʔДՔ�����H�o���|������������������<�T�����s�I���������������   : attempted DOS system call INT  COMBOOT image too large.
 : not a COM32R image
      	       E          ?  �          i Too large for a bootstrap (need LINUX instead of KERNEL?)
  aborted.
 �;
         Out of memory parsing config file
 Unknown keyword in configuration file:  Missing parameter in configuration file. Keyword:   � �0  o�
A20 gate not responding!
 
Not enough memory to load specified image.
    	
           ERROR: idle with IF=0
                   ��            Booting from local disk...
  Copyright (C) 1994-2013 H. Peter Anvin et al
 
Boot failed: please change disks and press a key to continue.
    �7   ��t�;   �����B�+���9�  ��$^��<K)��YQ� X��   X�@�	�%�+���2 ��+����R�P���+�̴h�  ӟ�6� ӟ��0  ӟ�  ӟe�  ӟ��N ӟ��� ӟR2 ӟG��� ӟ��  8�t:��R�Y�   ��L�h�  G��1��R��2���Rퟩ�Q��Rퟹ^��  n���h  }��H�R�	 �R��6:�R����|���]��R��  <=)��  <>)��  <?)��  <@)��  <A)��  <B)��  <C)��  <D)��  <E)�� <F)��  <F)�� <G)�� <H)����  ��.cbt.bss.bs .com.c32                         �                 "��S  �  ��f�    ��faf��      $hi h �  �5$�  h� ]?s   � E�� j	���� f��������D$��[ ��    �SUVW�5DL  �g�>8T 
8��6gf�X ��ߋt$ 1ɱ󥫸��  ��G�%�  �G�f�f����XI6�
8�|$$���!�u���g�6�x_^][��*��L*`DL)σ����*8D$%D$	$��L ���������f���������
[]^_�á��  �xP �+l��v �� ��uf�=|P  t��Ѕ�t������UWVS���P�TL(P�p �D$j)�P L �	�L$�4$���  v�$b�@ �A;$r��v�5�\$�l$8\ t����vJP
1��L$�J�G��G�]|\6 NJ�2��aw�z��i~��Z��P��� ���f�j��W�x
�_�T)΃�����a����B� x�hJ�P��[^_]�R�XC�p�n �v�*���݊L;��*O��	�,9���u��T��)���=k�w
��y���s�����O��[% 
<�^��N�1���2F9�u��s��K�I&\
	��p��+H�H AX�f�'X; )��	B9�s�\����u�z�m��	
�X�ǋ@@6;� u����2�Ӊ��P#����t�h�pX���S�w��RZYI�X�" �ǉ͡w ��Y��tU�щ��Ӊ�]�Q���HG����xC%��@F�p�k����HIK	��F	�
�`R��QK��1҉��#�_��T�؜
�P���H�W ��P@ȹ_{ �bSS��n���J ��t{���\a � OY��P�X&�&��ۋC�x5Q�\iu%k�@ �DF�@�o�B ]�T��W
 ��
��H t�|�/t�/@=ov�x @ �H���$D�W  1���l[Ð��rx"�Hk���VR�zW�0N1�q(Y ��=4^�	��F�k��� �%�'�<I��9U#J� �@rB���t< v����@Y �\�l�~$j�x|$V1x\ �h�׋@!�UCf] '��N���T��0�Vc|��W �`F�9DE�x]]�l	1ɺ�� �AK\Q�A$A+�x F
) �T� �<$9�v�$�>�$D$�N��T$#R����H�WZ����)X	Iw#�j��Of�CM����@ �]\MLv� �!�IM�@X��NVX% k�{�C(%*���	��C(��$�YLw�^1��%���@�y@9�s�K��$NK�V�`�l�֍AX�*``CDT�p�@`��Is@TX��j��y �@u�Kt�DA�g�OcR�h1H�[�U  X�Y �P$1�Ch�^s�MKEX�@t3S(��ʉ	[	�	�Q9���T&XF@]  pMC�2N,w�8Y=K��SQD$P��G5��Y� uU�6P	�3�{ Zx�h�h4[�:Y
 ���A�Kʍ]�Q\A�X(���)�^�S��
fa�K,��8��* a���	^�Y����P�p�$�: t���$��pL[u��Et����<$ �F`��B�	�u|U|N��S[�xU
V��_A�2^PL�W�����p �Fp�Zo|Y�݀} /�Eu	�ý�uO�/r�TI�}m�C; u�C�</t���������!�zuV%|� 9�Z�@h�C ��p����S���'aa��ɀu�n���_�EI
)H
���� ����Q,W\eD���
�tN���C��n�wJ"]DG�G��
��dw�F]8D4�R  �D�,�z0 tk�L$te=T� ^��Bۉ�US�(P��U0��~:�F$�;�/H	����R���`@��_�CQSs߉t!�!��iRBfC�;\1��H
��tL����ZRG�����t&A>�|�@h��ǁ�xH��i������W���V�L
PH�	�݉��h	Ѓ����p@�l��e�n�y�^�C$x�K(@�%f�C3!@T@�C$�c(�[�����T�����[���
x>
؁�Ik����ɋQq�C���aHk��R�Z ��U���l΄ux����]!�#�Jk����Y���IK$ViRS t�e��'����w��H��x�P���PY 	Gl�x!-,fA�

hPK�Xb�z�4KG/1�#�1dt�c�I�3)�Lb �/
�u% *Q�	���}$U�D$PWV�D$�OU �s�q�v�t �$�R��Lb\�yM���u��Z���x N�6FHj�P(��t��ң,x @�0^ �S f��RX� ��J�" )x_a�`D��h�f�+C^�&-��L����'% |'% x'% tT n��}��E���'% �'% �'% �U ��'� �y(E @�/�\e��
-`0 ������dI�~��L�:!3�����v�H"0�y����Mu(| ��,$�9�u����L���	��i�Q�JLY	�!������pǊ:�K	�H	 XZe�@A�J�˃�Ku:�X��H	 
�<09�u+�����	ىH�J�Z�Y]JW�H$R<B[�-\U���7PS!2 �Pу�Q�r��4�S�,Tx�9�r�@RH@	ZV�BN	��X�
9�r	�R9�u���#t!1ۉ����ƍ"FLVu
�8u��LP�9�u�C��u�O���	�xy���,�P/^�~!�"��L) 9�ro�P 9�rI��{��D')�	�r��'sW	ƉO�Z	*z?WP�!�%	-mPW �P/�K�S��SZ���[9��zS%1��"�,�(��1��B\��~I�3y'9 $�Q�jw���|u ��\t��/u�U S���  /t�AEO�w�]��� wՍ19�u���� ��)΀y�/u�Q�9�u�W���AHM�X���XK�@[�C'�
"P(�xO��
4��tv���� �텟d�	���ՋK�����T���!�!� "x>A��H9�u"�<(�����")N�Hg��A�<��%M��
C�����<�!�L��1�MKl�8�#���)q .Q�%lt��X�NՋ"�"� �N$�L$��N(�F�Vt�M�Y:�x1���D�DD$9��S�Cd
h�@	������ t���!20Cl
p9�w-;Tr'w;G
r+U D0� �x�
�{X lh�G�;FrHN�����t[O
s�M��B�����ѽpr
��O����>UT�CH�SL�kTYQ�GG9��
��F�TH$r�i�Sd�Ch���R��(El	pt[G���,��%�6E��VJ�s1{Pc@��U��E�t	 9}�wr9�s�A����t +��!��x�E�U�)���EЉUԃ��� �E�U�C,��E؉U܋U�#S,�E�#E�	�tB	�=ЋUԊM�-�P�E��'
@N1�L%M�;Ks��_���&5%44R�
_�HV2V�
#.3蓝�d]N��H�f��4^x��AH�L�]@D�u��Kd�{h u9�s]=\2`��lp�2Er�跆;��L�A9�r�s�0�
�CpY4X�#�8����Z�#]�RiW��#~9�?B<`�R��!W()\ �| �" R #�Q !�9�hI���uJ:�dB�<���tW����H�è@�Wt%T�#��?���rS�
t���$*W�G^�:S�SA:W�IDK��k����x��M�&�!I*+P!�3%�EPf�
��t�ٍ4�4xWf9�
u�V�f9�pl[f���V�@�B��D� u݃���f?�!�>%��@��F�={���`�s ��"�a|Z$t+ 1����������B��u�Y#I� �0��~ 1�	�� t�Gt��pkR@Tu� t'� .@�`)� ,� �LJ��!=Ny6f6 �8	�L$�� �E �\:!�@8t�^NSlFJ�h"@0уCd�Sh �v	�,x(���XD�=E.ǄF@����]���d$띍N�W���G	r��E|O�B�A�BAF���
��M�f�P
p�o�OEP�H"LJlf&�0����k�"�-uh�~h�R �,"IP �K�Q �I�HX����u��!�PHU�"�-I�H:Xp\�X`�@�uñt(@Ao�*�BW�Z`J��Wl��������#�N@�		�UH �8.u%�@��t
<.u�z u�tNU$!�5L	)��OQx1!2;Ah�S  v<.5��D @��~��l@
�ي�pj ���uK��D
~���
~�j �@R1yw�t|Ҙ0����;VM�7�7�p �-S�~�!=?D�F�<]z�n�V�Ez^
8
���H�@t*�V�T$��?UL_� ��}D$ ��D8F���t	I	JA�o}T$ C}��!�3�xTt1�_f�
\J"�C/�9A���w;�?zxt�nG�eM\)h	��uŀ9 �	f��AuFN�k�E�	�7!);(�/���j�ڍu�:L!�+A(\@k�� �^�%YNťf!�?�PjFG��b	�D�R��\	�XR��/h6MXOR �S�P
��S�i KʉPX�ҋUu�r �R\�[�U[Mq��t[U�[��Us 
�Ή���	�u�r�z��������J���� �1�rz�pl�xp�p\�x`�S-�!�*�hrdd�r���$7*��tf"�_�Fp�OO��K�W�Wj jL q�,!�JS!JRfM'*RM���,I�J�8b���U(Ɗ$q�$E5E,S �G"I:2|,ME-@d��l$/f��u�l$<i*IA]%�W|���V"#<,�d5MV�Y�A|tJN��VN\$-!"G� K	����RO`i
���F �$���� �i�R]&�+VN| )�؉^$�WډV(�P��V,L	!J'F0�1�+B��-)�=�  w	�F4b�]���[M@M1 X�v�x PD��t����Y� UH!�#��L�1�$\HN�^�n�W�G�~RG#G'���@��!�N��!}2�A�v�u�&�#����f`, ˃�!	"�"�e�;���!R��?oA�/H&	u��r URSh]i@ ��HP�@%aYIL$a���"�)@t,�fO:�LO;ʸ!�,�3�0@u"�MJ�#�5��.!�O�d"Ej�Q�!k��x%�k�PY�&�K�����\%LU�~�!�&!P^	(�\$$�5���E�!�V��|ɈA �у� }�^�u
G,�1@��9�|ǝ#�1'�L!�kX'H�9�wr9�wE!�,�sR�	�qt['�- <�E��U��EԉU؍E�P�5t�@qhn �MԺrY�lN�3n �\i	�E���}� uD
���@�M�I��h $��Q�E��UĉƉ�qy9}�w�r9u�sˋE��U�+E�U�AQ�e����c@�=&'9��bD� ��k!D��[��EX\WV\i�/I  ZY1�#XIt�{ uE#�+!�J �����1a�]T�7�C�P\�@XQ1"D��t!����SQ��Hb
)�]!O�#�S�<U��.{W�Ð#Q"/!�HDxNf�  �J����m�h�!W.��!=I�$'H�|�zR+��ٓ-����,tX�y=`uhdS\�b0" K?��������J��h�o�9ʋ5b��!�C��f@�i
[�\]�x
V
�TD�wCrH9�w=Er<#| �Z8Xw2r-�H	�X�B	�RCKrILGrKL�!I2
�Y����%`b+�r$M�*�1� �@['֋ "�SX�M1,l�LedCU���uA=l `@70�G  ]Z��/a !�QY[�щ��2��@�$)�Q�0[
;�,vIC,i(��!Z&�:aS)EG�LxQ�(N
0^
u�u�+D*�~��LBHX։ϋ�$(q�
e�{L�d�_�Ch[Y�eMl ]� #.U���AY�tY߿nq�|!�L�e"RP�dbOЃ�e!�;RP!�3�����D��$�c�$�d@T�@�t� �|�L�QR�t�`h� Gv�$DJ�!X!6�~PC�m E#d	�T$t;D�`~H�/��Ok�!�o��[ U�����"�N��D��y� �R������_@�u
}Y#
�u,�)���l=��E]Th4Ѝ�w��eAw�p	��#Bf�zH1�-�L�WV�@1Ҭd�E�#��M�w�؁�ù@Ę@!JyNr�n	AUWtW!*.l!8$D?H$8GD�!�e�MWA�L8W'�<T ER�RZYGhzO��S�2"\x#�_�$�k�$�{ �$�{ �$�A�)H "#�$��Y �	
�pth�b��+HhP�# I^P Y�y�!�)M�(D�,��z��a��� �׋C�D��$���3YZ!�.��H�fl(�&XH@-6#CT9���O���1p #XJsX�{\"�)��-g�y@�|���t"�q`F�9�}�q`QR��I�_@p^_0��$$�xE�Έ �L�@��t1�T�`B9�|C��u�� �@�D�\x�ދL�VW�J	XZY�������m>�!�/("TPU-U�=T�F�QQ�>F>��e>|
W+���IrYu�UV�o8��XCY�NM/�fFE�eZ�C!_T�$�rA"�j!m
RCI�ne�5Nl����D %gN�İ,	�xM��]Y�N&�,] �T�QS3NV�
yU*j~��F[Z|V1��½RɡRI����"z=��$@�tΉxn�Ctz % �  ���C�����uvml.L^��\0.X��h�p���Ωaҩa�vuH"!$�zT~Qj�t\����CX�S\a~��%�`�1���L�(À=�{�XXF�'9�&��'9tYA�	}�h)�A���xA!m\���!�7�A D��CC��~P0m���$"�y���|D�{���4$�{�oL$M�E	�#�rt��y)Q س�h�f��'!*"���pI(�p| �+�UP-����-e�-iY �n3�l3Y[�J*"����oB��]Y��EGR�u�+]�",�'$��|UD;\i3Ћ3�=�X!�4�=�@vhrJ�&!� j
 ,��1�4V=�(�������l�I�����)*N ���b�鐥c����EU͵Ѵe� U���"u!(U�,	�,U0#�B;R���;���Y_%�h�)e ��?�)Є)��#:dp�"-S\�������WV`�!�|>\Z��DH2\ ,b$DZ'�\#�F��$�+#'51۾T�Tm�h�k�� @po,�B;=xr��N;5{
��L!v-+|�Y)m����=*S��d�|$Muu9t$Iuo���8P?H$Y��1wcuX�p<A9U	!C���!".�	8�7t�!W�er- �!\*9T$av"�`W�@Z�H]aE�e%�'A��'�+|!)�i !� !�D8!bjʾ��!�l ���ځ�x;��1�Nu��x�A��dTuՋO�K'kES� ]{T�C"���n��PZY:wT�(���f�0�z1��Y��qO(���X H���ta��tW��xT ��G�Wl�#>�G;?U#�]GCGUU!���AK�	g�q5�UkH�Z ���E%Eh )���"�U`}+�Bn�/j���|��1Ӊ�$ P��3��#!Ms�p-^��(�+�C�A�^A!Yf���h�I�T�$�K'p'͡0#�o	T$D�Z����ZG�>�489�w�> u��^�9D4��u��[��!��L$���
z<�N��@"]!�b�!�e�W ,1�-��I"&�"�I!ܠ"0������|D�l$(�<1ω|$����F dLT�!3(r�K�P!����!1g�!=9�"�GJsZ#aJ"���h��8 x1�1��"�6�NF'��(�MA|5"��	�[	N�C	�<0��JZ�J"�|�	�P"J�U �"�._kK'�p0)�Ye "Xv!�L^PHX �{t ue�����{ɉ$#N�N$oH�#	s,tI!/�v�^C"P%twCT��zkx!�G��t!�W�|����T "��~Exc�N)�E�U?��n��{
�N%,� �I
u
},hY;$F.��M�������1osT�fvCxF\M�E\-�	&�RSH�KL'�)�,#�r(��E	L!�3!�?U!!�)_-�M"�tZ�!��DL�܅	�|$D w9\$@v#�p�%0b\$H��K�9#%����	�u-LjT��V�-�z&�<�!7!e"_"�I&�9#Hx�L$D9�r6wd@9�r,�3Q@P(��*  �\$D���$�h`!"2��$u:@l|�E$ �%�&��4"�Op
@
Af j_�`"�5!=%)P�L$���RlBU_T$xQ9�rYX�]59!�N'L%�bK%�"�$��\��YZ$�q}tW|$.��`Q��GA�;H!6G
;R&rh6GL�!��X4P t�XP�3�{U-Dl ��4"\Ek4h"�,)0"�h��x�*�_$&�_i<H"�_"Hh"��L�I%�%I�&I�'M�*M�PHI4H"֩��P ��G���)��"=bM��\$T��y&��P�]�t��N��!�y눡!����Í�T$$P}���]�;b�H�$�g[
�YC
�4�H� �t�H��x%}�x)�J��H-"�f�P1yrz��]uV
ؙ`A!���QIX~�HL�L
����M��u|[hE!"��XA�%IX�s4|$H-d@-A -g0�x`m"	p�M ��XDI
<I
@,pr+�@K  wr���w�p!�o�@Q��	!xd
�@5�@6 �@7�7R�Un\{��#�3p�3�'$�25F_�P #�:)(% ,�
��INDXt��FILEu,�Z�f�;f�r��L
�1�N�Bf99uf�,Sf�)f9�u�)�DD�P\Uu#??�Hi���!�|�Q �5L~���X)",�#�O�AybA�2���!XeJr��!�e��HnNAQ"�`<A
@!�SՈ�����*�!�-N_4����1�+AyD�M
!�yv},M}0��FP� ��&X0R'<PNo8RF4PR 0PEyl Y(#l�� !_&��C`h�b�%�&��]�#'v�FB�菶��8�,`�	9P,u�|$ tr[
�9!"��jI4U8j�~�!�]9�}LE�\
r*!~X�r"E�,ؖ�"�!	���� +8h�UF�l�lh�_ 0�#)�$/D)q)�E3*�h5�7Ptqo�
)����zB��(	�B��As\�Cr��U7O(�8Y	<"�Ws��
�5�!I�O_7����	�+Yj"�($Y7wy(�x-X��Y
 L"!{8z74R�7Q ,y7 l #uh�!fHc��7�7%#+k�!,:I7�j7G
��!.�} �6y5�5��q�gE0XWF4�L�9�&DDr.w94$r'U(�5�b��j� �#��x'��QG-,�m�+@'�Pm��zP��  $H/9�uJ1ɀ{QH��8�|KR�9�u3"�/��(��W���w�� z�j	�z� E	gذ%��(��p�U��υ�t��Bu��`T�!���D�����@J�� m
;U�u�>|��@�߉e��K1�#E��������)ĉe��EІ%E�z �~!��)N�"p�	���U�9��|Q�9�r�h�H8!�/F��%���E��v"q	�p	�F {��U]�TP�M��U��E��V���"�Mh�tA  ^1��b#�% 	�t�E�t�딨u��t��E��U�$'o�E���y �#>YE�	�	�	���U��"�mH)�,�&@%"�+�`�����EȉU��E���x �U�RE�
�E�!�_�	 �3��!�8���[
�[�-|}M��F0���(t\'��
!��,`%���RPU3�h��!�[YY1U�H;U��W
��`�E�;E��F��` q�G,1�9Qu9�t�{�MЉ�"��7##�h�a-�!F�X����"��!���^ �P &�s$8E"�hP�9�u��bp�u��p
Z�PD#xY�V��lLJ���}0"0�N���vF'�	��a^!5.h!3A��S'����h�eF^ǐ�;2!�(��z��v ��$UVQ[h��Q�dNP� x!6y!�`�!|��D�G�{1Ҁ!���#8jW�Bt)�G#/*�@U�~1�@$VM@� y ���JщO"|�ZP��������\JR���SA;�or싞 Ƅ� ��x ��$t���.�wu7p!�A
J-���nN��`	"jX�#Z�x[t
h�|"ŵ��,0���n��m
�e!�����
�T �v��S�V���.��A���ip'BV��y�	R��f
��e���x�{
h(sMO���DB{��u�!���!TLq��t u����C�^th�8�A�Q;��t* w;��g�A�3A�3�A*n��f��~��u �pd��4�I%-N.@ /J���)�W ǅ��$ǅ����QD��P��P��k/����:��0|_V:S�����!"�"����xj�;#�(hHZ(��W[��h��1�o��	'��� �rQ
�C�5���z5};���a�)� A�<�J��r��p\9��dV��d�d5�F-��L��L�8'��CS�C�g�9kʃ�h!4vd4�@! �o
��W�JP���f�LBR��ff@;�r�Ƅ�i�z <$	�I
<Aj��>�"�}Ry�����#:.�h[�v!}��m��	G	}A!�{!JjA����v��^~!�՞�D�]��aqN!�kf�@!��f!J��b���f�B
�K��"���c�$�yz�l�hbj:B&�OBhs^���U#�Ջ8!I�^t!/%�R��!v�tj!�f�_+Vu��t�"�����Q���$Fn0��qu���!u�"d\L���F"V$N���V$!+����L!�G�_)�*8����"�$�%$��x"hfl##<�P�f�n�uh"#,f�B!2�El��%&��-zIE|�@�b��%�)�@AEz]	�"$����P�=[h� ^�xa �b�QU-��!�,�q��}
0iC�e��l�
�C�Et��Ep�{L�!M�CG�	x!f���mS�"�5!�VܦV9�(�eM L"
uExc�4$!2,PX�"�"�p�]���^#��#�#`@�4!���!�#]!�#Ÿs�̏�
��zE%`ъ.�d	ǋ4$�}x uT	�	�|� �B�| &��X!#G �lDM�
h�q!|uqCuE#�E$q�ʑTT��ʊg�FQPM��!����K�x^[�ih�����F���!9��mE~��8+�+l��!&! � �����������u��},�*��s%� ��V�E�(�	�D��u��M��4�&� �#	-xuǍO�w�;u��"�
�GȍV9����V	��u�Tf�FT2 ��E��M�������	51�F�뱨I�y*j(-����D!�X���n^$�~(=a~	��;�)&-,'�)&%-�O!�E�$$-
��U��E�����_u0�'�,#�,��DII�&�,"�-�,Bp uЋ}ԉu��}��u��}�u�L�u"lN.�, -$�.ȭ̘auЉ}ԍ}�W\�!-�E�'%-�'�V$=�-%-![�CW��HUu��>��
���x }������E�p;u��吟WB�:� *Y�U�uu�:��f:uf�9��	��5�.L Ew^%�.}�;}	�b�~)�.z��m���~�#��W�@��!ؿYBǀ|"w��'!C��I�#�s!��f���<F�m	2e����S_���%��.�\p�"ȫlgP�uht^�p�"��e�p�V��gh6muOX顔(D�ЋK�P�Q5�	 6�xu'�@	A)P&%�L	���u�~,u
��5#Ȑp���(&A�%��!Z+�Y�|�����v{��j������"!/�N��J
1�A�#��Ð!=3j	H	"��X�#��k$\�M��$X�`M����;ps^1���|� uN#sƋ��C�G�F��!n��V!|>!5�w�0!��TNN��G�,H&\�Dfy%�b)a� "�gPOs@�$9�w\P{4 t)Ѱ���9;Cu8�SX��VB�\.��;4$v�,#�]�y��"{)�]�\)���u�(�s(X�o�B�D:!�Gq:֋QNgr�hbm@qL�!Ʃ鬓6�q!�"Q!B�X"T%	
  �����p4!9[�]1A	U	�²�	t�
�r�u�b�<q8�y�%i�N	Zf!+���"�"�BC G��C(!hB!6��F!��, 0h4�V(�CX�
�#�����m�'e�$#?M֋v���$0lK�$��1��.&���eT��FM��#a]#8e	��+n9�v���o�E�X �B�\$$[��+L;�w7�; u	 !�� �C9Ru� v"�O�hHB_��y: "b㵃O�T@D8;~�"��![�h$��'#`-��#�> T%4!�cm �H!)W#���|$8S��"\3$
"�'z÷t&y�fZ�Mn	C�!-G�uDKU^!�J�`%#���
T8#6���L�{��"X�"Y�("��Q$�x�":aC!����$"@�w
fǄ� Ih���F���o"�H+p6!�ӉFa9	"e�X!$�CP�ak1�JQ#=K!	]!�ֺ#�.��&��|%V'Ð&�"�}suM܋�
r}�V߃�|M쿊��H"����!�(�!r��  
�M�1�1��O��M��8�M���u�}� tn|��E�8�a�d�cu܊��#u؋��M�M�T	���u���)�4���( �����Ǎ���9�"����	@�9�u�����Ea�"y�+ &�E��?�}��@2��q4�!w��XR�"N�U�y 38
�ucf�x �xtQ�X�]�1��k��M�;LsJ���u
�:B;U�|���k���_�]��E��W@
U�M�]����N��H�1��h�k�;te
I|	�A9�|���h%Z��O^�AT k��+1�y#�p9��.$�R!r"I��Ӄ}� t)��E�8`�"A@�#@�h �X���p�u�� wS��wN#��)э��]��|X�D�Xw	�Ņ��"�E!���[�_�t
�]��@B�9�u���P*
σ�����]��E�l
�� w9�sf-��w�u�jn`�J��@e��+M�]�X2��e�Eu���
�(�Ή�+u�}�mH�d9�s~���
�(S�Y[�&*�9U��p+p��v���Mʚ��
C$P�˸`��	�u�CH#ƔCLz �-c��!�	�K"��p
���!�)��CT1�_%���*��}U��K���̖!��[ P��� ��O~�`��>`!��lv",�Gڃ�
!I!a��\��� ��X Y�Y �"��[�[!Z@�C������2�L""W�͉�$����Z��"$�\�(���	�"�`UH�RP�ˮ#�3q�&H�$C���"<�$~�@%�O�pF�)�!>#��HPJ��9�Q��L|!ʆ�a��	�S"��SD9�r�{8�sH#��
�KD�49�rY�@	dDx6_B�)�])�KD!�7�S<Dur���w&�8	g<'m�S"�h�L6!%q�l��{T �s@t�09SPt	E�!��Q8I�To�sPP!~��6|\�!6h�zuD!>�CTh�]F!HP�LE(1Y�	%9N+uL�$u"�n}D"�loM1�Z����X���X��	u?u�1���	_!j !p�X"�$�P(K�s8C�	,L s@)sD)�u�i�;�vPWS>A"&�@ !�e#��@�&��$-%�L:��f�xŚ��_�W(hs	 J$��o��'�t��f�C�Љ�"��X4�AJk�"�F���lA� �4Y�$!�]p�$ɢ@�"�}A!%K�B�����{9�|�vًPdL@
"�)EJ!\.�%�[d!�0�^Z�x!�* 9Ku9t��@9�|�^E�E8!!6'�Bp`@"�&� Xs
 ^$T�ba��j��c�9xk
0t#���S�E�!��-^���Q
*^���#��"t� ��$�B!��*�M"�{�u �}$�E#'�$�<�$"�O"���E!?���
|]�"r!�S�}x��#>��!`�%��Q��!� �[��UQXZ H���'$�( )] �^�l#�t Hy�O���$��ƙ�!Q�!|�!�$ W v	Rd�~
�Mq�#$#\S^ utdqf+"�x\#��"rA9�S^�9�W �9�V �;!QT�
+�"
�t#MxlJ"�s��!�!!�PQIMQU�"��P@	�^L�D!9�I!���"��D e0R�Gw2�X#"��XS�,�e�!�*�$��t[Nu���t
d"ޠ��knB�NP���FL!�$(#�x�$�pԹ P"=��bhVy��! 8L#!e� -Mޅ�]+!��{	tP�#���PHyv��4$!��)��&K���!JZd��
$,�dL)���`N#��ANԣN�NcN�FiMUE0(�t�E�BKU�f)�L�$��WS'T$6�)<�L�~��9}V�N*�#��$"�D+�	�MHM�l$���\LQCQC�'r���/��Ё�Dw
����O@
�O�I�gHtE*@+�HdH#5X46�A[��#��#C�f�x"&<N@U�,
Ph[f�Rd����Tb$XT II\II0�I��It2!�l�|B$u�1ɍ��&��V��UK"�Qty��M0PLHl6�!Lt+F V$�����p�I�@e@�
9�u�F(�T �|�U�UI̵T��T��T�vTF�" �['�$UstI)�!�]Lh@�V,$EМ�?��
]UнU]UнU|UD"�#��U$��"��T��vj P�����L$��hn
����d$�RPS��V"�7(k�\��]���^]~Q	xe<IL|(;��B���A[ QI��G���"��ţ�\ "R�y5!y�)"y`0Q:�5�P��D$Xu~4M@�UfP��rAf[Z�UN,,����dNW�HU�� �PIE��g\IXQy J�
H'
�p,eU�t��N�L\U u���	f��Iw�Je4��!�8{� |=�v��P����Ch�� �	[w��?�1ҁ�B\5�^��|'����\ Y�p!�$t	�v)=�U �w#�b&��Q �jT��VR5WI�H!U�!`�C�hg��\��T"|�H�Q]Q� |n ��!F/��_��W  �E�dPEZ�l|�EFBa/O/�:/B/Z/�#/dQ��4VWP"������s�I�ȃ�rSf�!E4��n�tf��t�X_^_>WS^��4�6
	н��}��}����`X D�X[_����s�:FB)�u9�u�1�^�!v�B9  u�)�Ð�
�B��t@��}V- 1Ɋ�A��u�^�f��@@�8�u��1�'=1!,�!X@ ���0�L$���<2F)�u	M!;Ou�!!�6S�!�1���!\`RpP#�H*�G� Z[(��h��
u�TQ\T#��t$|#��L"�1�Uk %��*�K&�K�X����@!H9��������DU
M �!�4?M N <%��$A49J�sHW�G"į"6R�Dx	� <��@TP��+���o
ᐰN� �), m �-= ��a)] �N��� �֟ �Ο  �ƞ �"�"�xЉ���	wk	1

S�B#�"�'<*�>Q�V/��R�߀��k.�
  #,]&ҵ�e,cL$ Ac �I��l!�K6!+� ����J�)| lt:<ht+<jt<L�<tH*F;<z�| qu+�x4#S�H�U��`V��A�{����o~#�S���}|G��<n!��  )<c��H><PtR<X�Z��T<dtk<i�
@�a<s��`<ot<p��@�%<u��wx�	X�q�qI�f���l�Q0�!��&��V+��'��@�|TPt3	`�u�ct2x t8��(��s	�.���DW5�����#��(��
e�w� ���//+�5P���*����1�&��-��#���T&��N4(9S�s+$��$����L$D!�=��!h:.��\ MPDB��"�dt�,y�"H+U Am�pT�$��!fΉ��&0�A�0n �N6YYIH#-G�Mx B�� L8t��uOA;B}xK||�eIt`"ӱ<��f:t!�Y����D	<�A���|$<�Ta4�gW���}	�A,M8!d=VuBZ,toHu1Q,V~d"54,X!�<;P'W  @!��u�xJ	@��8K@�#g�T$@��t�*-�$!`��+�	(H ��+q&�0@�JW#$sXDɃ� ��X�@��HHu%xD@~�(� BMx@�@�t0!�5T#)�HD"�"}�4]7X!�-�Q\�~�S�I�(B4H]8L "ʹ$O	8sD�4�G�_mI`aOU`'� |L^s,AA\l '�F��c^!ZYPP�s�G�! �3� ;V�Y_�^Q`A4T#��QL�AH����;F`sXD� q�D!��uI
v��K@_ H)�X%,���#95gHj�O!�&g�LV�k�!W]��!|8"�c�������IY�~V~C �t�W~M wf�uEuK%���0V!q�)"��m(L$0DYbu�#�#bG)�O�L�U(��@Gu��$P��L~��dx� B@
"�Eu�v��'�AD�(�(��<��D�"�1�J&1���yvof�:Ed#��j�霨P�
���'� �:�nQ��'�_�lv�"�a#\8n!�Bp&A L���3h�M&L�sgGL�����t�#A��h�TOL�L�2��1L���Q���'do��9�(�5ATt�D�`���h&lI!�$�H�À  ����Q���`1��׉����_�Q菑S��M�oM�ȉ�Kܨ"�z@_!�[���}f�Z�RQR!�#P��"mH�A�$S�6��L[}j �w�7�t%�e�[�mV&�fEQ!De"�iU��}"�`h&%�e	�u#� "�_�|9 U��M�U�M�u��}�u�}�}� y�z�H�9	wr�M�9M�w"�a}�)u�}�E�U�����u��}�	���X}�u��}� t�u�@�M܉1�yE0$�_�!G,�7 z���Q� �'!w��U�� P$!r�!JU��P �� � @���M �N |i�� "=xi&	!�� m X �� )N O DM 
N� ���N .q�l�	|Q� x� ^n!���+�!��r�:,� B�T\,� �'M- �* �%\N�]t�3��A4� �G �D�\<i/!�cu�L,�.� K N �I N ,P�xudqxt|xI|U"�$Գ�X��Q 6   N	
 !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`8|  s{|}~���A�A��EEEIII�����O�OUUY�������AIOU��������������������������������������������������������������������������������������������  � abcdefghijklmnopqrstuvwxyz�8| � �������������������������������������� ���?�}�1�WE ]GMGMI	]F_G !�Q � @                ! " # $ % & ' ( ) * + , - . / 0 1 2 3 4 5 6 7 8 9 : ;L|  u= > ? @ A B C D E F G H I J K L M N O P Q R S T U V W X Y Z [ \ ] ^ _ ` a b c d e f g h i j k l m n o p q r s t u v w x y z { | } ~  � � � � � � � � � � � � � � � � � � � � � � � � � � � � � � � �� � � � � � � � � #� � � � � � �%�%�%%$%a%b%V%U%c%Q%W%]%\%[%%%4%,%% %<%^%_%Z%T%i%f%`%P%l%g%h%d%e%Y%X%R%S%k%j%%%�%�%�%�%�%�� ����� �����"��)"a"� e"d" #!#� H"� "� " � �%�  a� �*� �(��W9� �M=�T=
� � � � � � �MB�MC�E@�T>� � � x�EF�]?�\?�� � � �U?� T��_?��T?
�������_?�� �(<��h�(L ��X8 ERROR: No configuration file found
 .. \valid�system�!ino  ructure Out of memory: can't allocate�Pr %s
 fat_sb_info)	vX /boot/Qlu�ext�.e �.cf�%sf  t my	h&k iPEbfs: search Ven	#darr!!'� � c	'p	d�,{noty#t]e.� compress9� nDubvol'�w	"ngonly support sHT+device �
 _BHRfS_M� MSWIN4.0�1tfs1NTFS B  ut8_* E{ whi8rCdZ f	mHche.
t<attribut�?Qp*se_m_n()�MFTIc	d'L1T UW!  ?! $INDEX_ALLOCATION istBYlD B(idX2@*�hp�5Qs�LI�QQ
X�EIex l/�VCrVt ic. A
�rty	l	�k..L�'o!dirQt|S(El	)t*P~Kpp�'�`gNd o`, a���in�_�d_Rtupw(Cou�ZetBS$V�ume)!+� R v��='�!�c2_g_gup_descbMnk� >= �s_cHt - *u =�d,,� h�
0t	z m��h:Rm's�a EXT2/3/4*�Pl��,�pl^f*��'�thDUight�Bgriy+ �W CHS: �,%04%s^|ctxllu (%u/� _-EDD9� 
 (�ll)+-� H�� 3!�18N �p%1NPq�                                                                                                                                                                                                                                                                                                                                                                                          GCC: (GNU) 5.3.0                     ��"               y                ,           ��    �    �           $    u       *��  0��              �       �              W       C��              �$       A�Z              �+       ��              �/                   -0                   �0       ���              57       w��               r;       V��               #>       :�5          $    �A       ؈   �           u            ���../sysdeps/i386/start.S /glibc-tmp-ec9b8d6964164aa7972612c322780d61/glibc-2.23/csu GNU AS 2.26 ��       F     	  V   8      +   &   :   �   int     !      D  A   �   �   $�G    p    R   }       ../sysdeps/i386/crti.S /glibc-tmp-ec9b8d6964164aa7972612c322780d61/glibc-2.23/csu GNU AS 2.26 �D   d   �  �  d  @       �   ,  �0   +   int 8      &   :   �       !   �  7a   �  8h   �  |z   z  }0   3  ~0   �  L   �  �z   ~  �0   Q  �0   M  ��      �  �o   �  �7   D  �  ��   '  ��   p  �o   �  �7   �  ��   @  A   O  X�   �  b�   �  m$  �	  �7   �  x�  �  z   �  {/   f  `.e  /  0�    �  2E   [  7�   D  :�   }  ;�   R  @�   �  A�      E�    �  GE   (�  L�   ,�  N  4H  R  8�  [s  @]  \s  Hr  ]s  P]  p�   X k  	@  �  :h   ;  }7   "  0�    �	�  �  	�7    ^  	�:  �  	�:  �  	�:  �  	�:  �  	�:  �  	�:  �  	�:  �  	�:   
C  	 :  $
H  	:  (
�  	:  ,
g  	F  0
k  	L  4
�  	7   8
�  	7   <
  	�   @
�  	E   D
�  	S   F
�  	R  G
l  	b  H
  	!�   L
�  	)  T
�  	*  X
�  	+  \
�  	,  `
�  	.%   d
o  	/7   h
�  	1h  l   	�Y  	�F  �  	�F     	�L  H  	�7      �  @  b  �       @  x  �   ' ~    #  
p  �  <R  �  0      0   k  7   �  	7   �  
7   �  e  �  7   *  e  #  e     0   $�  e  (�  7   ,z  7   09  7   4  e  8 *  0   u  �   3     y  0   �  "   �  	  �  �   die 1*�+   ��  msg 1e  � I�]  U�i   �  7U�;   �"  msg 7e  � `�u  j��  ��]  ��i   !  @]  ��   ��  fd @7   � buf @  �$  @%         @G     �  B:  �rv C]  S   �  D]  q   ���  ْu  ��  ��     y7   �4   �C  pp y{  � buf y  ��  y%   ��  z�  �     |G  C�"  � � ����  @  []  C�   ��  fd [7   � buf [x  �$  [%   �     [G  �   �  ]e  �rv ^]    �  _]  "  q��  ��u  ���  ���   �  �7   0��  ��  L  �7   � �  ��  �d  ��  �c�  �7   N  st ��  u��  �7   �    �e  �  L  �:  u��  �7   �  mtc ��    mtp ��  /  fs ��  c  s ��  �  �  ��  �  �  ��  *  �  �h  K  �  �7   ^    �e  �  ~  �7   �  |  �7   �  i �7   �  (   c	  ���  ύ�  ��  ���    !�'  %
  ![  �  u�!�  �  u�W"cp  :  .  "ep  :    "sd !e  6  #�  "7   I   �@   �	  -�]  C��   :��  ԏ�  ��  ��   ��  ��    X�%   <
  z�]   Q��  g�  ~�  Ƌ  ؋'  ��3  $�B  b�]  n�i  ��"  ��Q  ��\  ی�  �h  ��x  #�]  ,��  G��  a��  v��  ���  ���  ���  ��  4��  E��  Q��  u��  ��  ��  �C  U��  ��  ��"  ��$  ڐC  �/  �;   :  >   �  $�   � �  %r  �  �  @  �  $�   � @  �  $�   � &A  �L  >   �  $�   � &  �  >     ' &(  
  &�  +  	0   (opt (�  )_  .:  �e)�  /R  �e*�  �  d*�  �  +Q  Q  2*�  �  �,8  "  �8  ,U  A  �U  *�  �  �*u  u  n*    l-�  �   �  +�  �  }*}  }  �*�  �  w+M  M  %+    $-�  �   �  *�  �  4-i    �i  -�  e  ��  +�  �  .*    �,p  �  np  *�  �  2*�  �  >+b  b  �*X  X  H*�  �  N+�  �  *"  "  h*(  (  �+    
1+�  �  
R+g  g  
:+6  6  
A+    
4+4  4  2*�  �  =+�  �  +*    d*X  X  � �   �  �  �	  d  �  �  !       +   8      &   :   �   int    D  A   �   t   �  0:   
  1A   �	  33   �  :%     ]   t   �   	k    �   
��4  �  �    u  �   �  �   �  �     �4  �  �   �  �D   t   D  	k   
 �   U  k   � ��  �  �    �	  �   �	  �   �	  �   	  �   �	  �   G
  �  �  �   u  �   �  �   �  ��     �4  #�  ��   .�  �  6 �     	k    �   (  k   � ��H  A  ��   �	  �U   �
   �+    �+   Z  ѿ   K	  ґ   �  ӆ   �  ԑ   �	  Ն   �	  ֑   3	  ב   �
  ؆   u  ّ   �
  ڑ   �  ۑ   �	  ܜ   =	  ݜ    (  $�	  ��   ��  ��   �t	  ��   � �   ;  	k    d   �    +   Z  �   K	  �   �  �   �  �   �
  +  Y
  �   �
  	�   d
  
�   �
  �   �  �   	  �   o
  �    	  �   $�  �   (-  �   0�  �   8Y	  �   @�
  +  A�
  �   D!	  +  E&
  �   H�  �   P�  �  T�	  �   ��  �   �t	  �   � �   �  k   � y  3   �  "   �  	  �  �   �	  (�     p (     �   m	  -�   +  p -+   1  �   �
  8�   P  p 8P   V  �   �   _   ��  bs  r   �  Q
   ]   �ғ   �  �  #�  �  sbs $�    ��%   �  *�  �  sbs +�    H  �  H  ;  �  ;  !
  .]     "sb .�   �  �{   I  bs ��   #Q
  ��   $d  ��   4
  3{   �  bs 3�   #Q
  3�   $�
  5]   $d  6�  $�  7,   $O  7,   $F  7,   $  8,   $�	  9]   $!  9]   %$z
  i�    t   �  	k   ( &�  �{   !�"  �x  'bs ��   � Q
  ��   �$�	  ��   �
  �]   �  d  ��  8  $�  �{   (�  x�7   �i  )  W   (I  ��2  �'  )c  j  )Y  ~   ��2  *n  �  *y  ~  *�  �  *�  �  *�  Y  *�  �  *�  �  *�  �  \�   �  +�  �� ,˕�  ,��  ,7��  ,U��  ,���    -  �X   �)2    )(     �X   *=    ,��  ,��  ,��     :   �  . /
  x  0,	  ,	  A �   P  �  L  d  C��    ,  �0   +   8      &   :   �   int     !   �  7a   M  ��      �  �o   D  �   A     ��*  �  �Z    ^  ��   �  ��   �  ��   �  ��   �  ��   �  ��   �  ��   �  ��    	C   �   $	H  �   (	�  �   ,	g  b  0	k  h  4	�  Z   8	�  Z   <	  z   @	�  >   D	�  L   F	�  n  G	l  ~  H	  !�   L	�  )�   T	�  *�   X	�  +�   \	�  ,�   `	�  .%   d	o  /Z   h	�  1�  l 
  �Y  �b  �  �b     �h  H  �Z    1  �   �   ~  �     *  �   �  �   ' �  �   �  07   
  1>   �	  30   �  :h     �   �  �    *  1�  �  �Z  
  ��   C  ��  �  ��  g  ��  
�  ��    ��  G  ��  s  ��   �  ��  �  ��   9  ��    ��    ��  �
  ��    ��  
�  ��  %  ê  /  Ī  �  Ū   �  
�  lba ��   len ˪   ��b  �  �   u  �  �  �  �  �    �b  �  ��  �  �r   �   r  �   
 �  �  �   � ��5  �  �   �	  �  �	  �  �	  �  	  �  �	  �  G
  �5  �  �  u  �  �  �  �  ��    �b  #�  ��  .�  �E  6 �  E  �    �  V  �   � ��v  A  �  �	  ��   �
   �Y    �Y   Z  ��  K	  Ҫ  �  ӟ  �  Ԫ  �	  ՟  �	  ֪  3	  ת  �
  ؟  u  ٪  �
  ڪ  �  ۪  �	  ܵ  =	  ݵ   V  $�	  ��  ��  ��  �t	  ��  � �  i  �    m	  -�  �  p -�   �  �  �
  8�  �  p 8�   �  �  ptr S�   �  img S�   S  S�   �    S�  p S�  v S�     m  p m  v m�   �  /  _C  p _C  v _�   �  6  !�  ex !�  $  !Z   �
  "�  �  "Z   *  $�  �  %�  �  &�  lba &�  len '0   �  D�  2�    �  �  �  4  cZ   C��  �5   �
  c�  /  !�  cZ   �!�  dZ   �!k  dZ   � �  e�  g   �
  e�  �  "   g5  �  epa h;  ex i�  #wp jC  �  "�  kZ   �  "�  l�  	  #i mZ   :	  #dw mZ   Y	  "$  mZ   x	  sbs nA  �  o  $�  �   y�  %�  �	  &�   '$  ��X   |!	  %9  f
  &0   $$  ��   }C	  %9  z
  &0   $�  ��   �e	  %�  �
  &�   '�  ӗx   ��	  %�  �
  %�  �
   $�  ݗ   ��	  %�  �
  %�  �
   $$  �   ��	  %9  �
  %0  
   $�  �   ��	  %�    %�  3   $�  �   �
  %�  H  &�   $I  �  �:  %u  �  %j    %_  �  %U  �  (�  )�  �  )�  O  )�  �  )�  -  )�  u  *�  �+�   �
  )�  �  $�  ט   ;�
  %  �  %  �   ,�  �   <%�  �  %�      $�  &�   J  %  *  %  >   ,�  4�   K%�  R  %�  e     '�  ;��   �\  %�  }  &�   '�  X��   �~  %  �  &   $�  o�   ��  %  �  &   -}�M   �  "}  �Z   �  .���  .���   -Й>   �  "}  �Z   �   $$  �   �  %9    %0  &   ,$  .�   �%9  ;  %0  N    �  Z  v  /A  �h  7   ]  0 /
  R  /(  R  /�  ~  0   1�  �  	 �  2�  �  
 �   �  �  j  d  A�Z    ,  �0   +   8      &   :   �   int     !   �  7a   M  ��      �  �o   D  �   A     ��*  �  �Z    ^  ��   �  ��   �  ��   �  ��   �  ��   �  ��   �  ��   �  ��    	C   �   $	H  �   (	�  �   ,	g  b  0	k  h  4	�  Z   8	�  Z   <	  z   @	�  >   D	�  L   F	�  n  G	l  ~  H	  !�   L	�  )�   T	�  *�   X	�  +�   \	�  ,�   `	�  .%   d	o  /Z   h	�  1�  l 
  �Y  �b  �  �b     �h  H  �Z    1  �   �   ~  �     *  �   �  �   ' �  �   Z       h�  �  j�   �  mZ   
  n�  val oZ    �  <�  �  0      0   k  Z   �  	Z   �  
Z   �  �  �  Z   *  �  #  �     0   $�  �  (�  Z   ,z  Z   09  Z   4  �  8 \  0   �     �  �  �   *  0   �  �   3       KA�1  ��  rv KZ   � p  K�  �p�G  ��G  ��S  ��G  ՚G  ��G  �S  %�S  ?�S  M�b  c�G   M  �r�v  �<  L  �Z   � �  �<  �p  ��  �o �Z   c  �  ½���n  �y  �y  F�G  R�b  ��G  ͝y  E�G  m�G  w��   �   �  �Z   ��   ��  rv �Z   �  ��  *��  K�G  n��  ��G   A  �h  �  9�   �  GZ     PZ   7   �  �   �   �  _  	�  opt  �   ��    �    �  2  `��  �   1  �    �  IB  @�!  �  �  d�  �   �  �  �  
'  '  �    
��  �  �  �  
    �	  �  ;  d  ��  �  ,  �0   +   8      &   :   �   int     !      D  A   �     �  07   �	  30   �
  8�   �   p 8�    �   	�   T  �Z   �   p ��   
i �Z   �  ��      	7   /  _%  p _%  v _�    �   �  )��D   ��  �  )�  >  i +Z   j  �  ,�   �    ��   /�    �    �     ş   5�    �    �     ȟ
   6  �        7   �  ;Z   ߟ	  ��  tag ;Z   � �  ;%   ��  ;�   �p =�  -  c  >%   q  �  ?�  ��{(�?   �  h  P�   �  �  Q%     T��   ��  ��  Ԡ+  P�e  �   �   �  v   � �  ��    ��  �  ��  � �+  P�   m  �Z   ��   ��  �  ��  h  �   �)   �y  �   �   �)   !�   !�    +�   "�    +�   #�   �  #�   �      $�   R��   ��  �   �  %�   !�   !�    w�   "�    w�   #�     #�         ���   7   �  v   � &  #�  �e'3  3  .'Q  Q  2 �    �  �  �  d  >
  5   .   .   � D  8   
     @��  De   ��+   ^   �  F�   ��int {    �    �  �  �  d  }
  5   .   .   �� D  8   (     @��  f   ��+   _     �   ��int }    z   `  �  E  d  ���  �
  ,  �0   +      8      &   :   �   int     !   D  A   �	  �a      �   v      �  0>   
  1E   �	  30   �  :o   ;  }a   #  �   b  �   �     �     v    >    �   +  v    �*�  	�  +�    	s  ,�   	  -�   	�  .  	  /�  	�  0�   	�  2�      �  v   
 �   �  
v   � �6\  	B  7   	1  8�   	�  9�   	�  :  	V  ;�   	�  <�   	z  =\  	�  @�   	s  A�   	  B�   	�  C  	  D�  #	�  E�   .	�  Gl  6    l  v    �   }  
v   � �(�  �  3+  N  H�   :
   j  	  j   	Z  �   	K	  �   	�  �   	�  �   	�	  �   	�	   �   	3	  !�   	�
  "�   	u  #�   	�
  $�   	�  %�   	�	  &  	=	  '   u I}  $t	  K�   � �   z  v    �  �  n �    	�  �  	�  �   z     �  
v   � �  0   �       T   r  @%�  	#  &�   	Z  '�   	�  )�  	�  *0   	h  +a   	�  ,�   	�  -�   fat /�   	:  0�   $	�  1�   ,end 2�   4	�  4�  < a   �  �   }   %   �    �  +   >   �  _p  �   �   a  .E   �  _p .�   �   �  80     _p 8         ���  �  %  �  � Z  �   �fs   +  bs   U  i a   ~  �  �   �  �  �   �  �  �   �  .  �        �   �  kB��  ?�   <�  �  A   �  o�   C�  �  V    ��O   �[   K�f   �  �  !  qX�   �O  "fs q  �  h�r  #w�f   $$  $  	�%�  �  L$u  u  	�%h  h  G 9   a  �  �  d  w��      ,  �0   +   D     int A            :   �   �	  &E   �  0�   8   
  1>   �	  30   �  :�   !   ;  }E   #  �   *  ,   �  !�      "E   4  #   �     7    b  �   �  (  �   8  7    >  C  �   S  7    C   S�  �  T�   �  U  �  V  :  W  �  X8  �  Y    Z  �  [8  "  \  �  ]8     �  7   
 	�    
n �    �    �     �  L   /  7   � �  0   R       T   r  @%�  #  &   Z  '�   �  )/  �  *0   h  +E   �  ,v   �  -v   
fat /�   :  0�   $�  1�   ,
end 2�   4�  4  < E     �     %   �    �  �  80   0  _p 80   8  a  .>   Q  _p .Q     �  v   w��   ��  fs �  �   v   ��  �  �1    �dep 
  k    E   �  s �   �  ��  ţ  ݣ&  D�1   R    �   S  g  g  :�  �  L,	  ,	  A6  6  A �   �  �  U  d  V��   �  ,  �0   +      8      &   :   �   int     !   D  A   �	  �a     �  :o   ;  }a   #  �   �  �   n �    �  �   �  �    	�   
      v   � �  0   #       T   r  @%�  #  &�   Z  '�   �  )   �  *0   h  +a   �  ,�   �  -�   fat /�   :  0�   $�  1�   ,end 2�   4�  4�   < a   �  �   }   %   �    	�  h  6V�.   �-  fs 6-  � ls 8�     N  8�   :  x��   	#  �  }   ���   ��  fs -  � n �   �ls �   c  ���  Ҥ�  ޤ�  ��   u  u  �$  $  � �     �  �  d  :�5    !   +   int ,  �,            :   �   �	  &3   �  0~   8   
  1�      �	  3,   �  :%   ;  }3   #  �   D  �  �   s   �   �    >  �   s      �    A   �  7  n �    	�  7  	�  =   
     N  �   � �  ,   q       T   r  @%  	#  &.   	Z  '�   	�  )N  	�  *,   	h  +3   	�  ,h   	�  -h   fat /�   	:  0�   $	�  1�   ,end 2�   4	�  47  < 3   ,  �   ,  :   �    
  a  .�   O  _p .O   
�   �  8,   p  _p 8p   
�   g  �   :�N   ��  fs �  �  �  h   �   
�  q  6  -�   ���  ��  fs -�  � s .�     �  0h   B  q  0h   k  g  1�   �  �  2�   -  �  3�  m  }  4�   �  rs 5�   �  4   �   ml  D   U  4�   z�  e   u��  ���  ���  -��  b�v   
q  
s   �  �  L p    �  =  �   ../sysdeps/i386/crtn.S /glibc-tmp-ec9b8d6964164aa7972612c322780d61/glibc-2.23/csu GNU AS 2.26 � %   %  $ >  $ >  4 :;I?  & I    U%   %U   :;I  $ >  $ >      I  :;   :;I8  	& I  
 :;I8   :;  I  ! I/  &   I:;  (   .?:;'�@�B   :;I  �� 1  .?:;'�@�B  .?:;'I@�B   :;I  4 :;I  4 :;I  4 :;I   :;I  4 :;I  ���B1  �� �B  4 :;I  U     !4 :;I  "4 :;I  #4 :;I  $! I/  % <  &4 :;I?<  '!   (4 :;I?<  )4 :;I?  *. ?<n:;  +. ?<n:;  ,. ?<n:;n  -. ?<n:;n   %  $ >  $ >      I  & I   :;I  I  	! I/  
&   :;   :;I8  ! I/  :;   :;I  :;   I8   :;I8  :;   :;I8   :;I8  I:;  (   .:;'I    :;I  .?:;'@�B   :;I   :;I    4 :;I  4 :;I     !.:;'I   " :;I  # :;I  $4 :;I  %  &.?:;'I@�B  ' :;I  (1XY  ) 1  *4 1  +4 1  ,�� 1  -1XY  .!   /4 :;I?<  0. ?<n:;   %   :;I  $ >  $ >      I  :;   :;I8  	 :;I8  
 :;  I  ! I/  & I   :;I8  :;  ! I/  :;   :;I  :;   I8   :;I8  .:;'I    :;I  .:;'I    :;I  .:;'   4 :;I  4 :;I  
 :;    .?:;'I@�B    :;I  ! :;I  "4 :;I  #4 :;I  $1XY  % 1  & 1  '1RUXY  (  )4 1  *
 1  +U  ,1XY  -  .�� 1  /4 :;I?<  0!   1. ?<n:;n  2. ?<n:;   %   :;I  $ >  $ >      I  :;   :;I8  	 :;I8  
 :;  I  ! I/  & I   :;I8  I:;  (   .?:;'�@�B   :;I   :;I  �� 1  .?:;'@�B  4 :;I  
 :;  .?:;'I@�B  4 :;I?<  ! I/  4 :;I?  4 :;I?  . ?<n:;  . ?<n:;n  . ?<n:;   %   :;I  $ >  $ >   I  &   .:;'I    :;I  	& I  
4 :;I  4 :;I  .:;'   .:;'@�B   :;I  4 :;I  4 :;I  1XY   1  1XY  .?:;'I@�B   :;I   :;I  4 :;I    �� 1  ��1  �� �B  I  ! I/  .?:;'@�B  ���B1     !4 1  " 1  #4 1  $1RUXY  %U  &4 :;I?  '. ?<n:;   %  I  ! I/  $ >  4 :;I?  & I  $ >   %  I  ! I/  $ >  4 :;I?  4 :;I?  & I  $ >   %   :;I  $ >  $ >     I  ! I/  :;  	 :;I8  
! I/  :;   :;I  :;   :;I8   :;I8   I  I:;  (   :;  'I   I  .:;'I    :;I  .?:;'I@�B   :;I  4 :;I  4 :;I  4 :;I  
 :;  1XY   1   �� 1  !.?:;'@�B  " :;I  #�� �B1  $. ?<n:;  %. ?<n:;   %   :;I  $ >  $ >  :;   :;I8  I  ! I/  	:;  
 :;I8   I  ! I/  I:;  (   'I   I     .:;'I    :;I  .?:;'I@�B   :;I   :;I  4 :;I  4 :;I  �� 1  &   . ?<n:;   %   :;I  $ >  $ >     :;   :;I8   :;I8  	 I  
I  ! I/  I:;  (   :;  'I   I  .?:;'@�B   :;I  4 :;I  4 :;I  �� 1  .?:;'I@�B  . ?<n:;   %  $ >  $ >   :;I  I  ! I/  :;   :;I8  	 :;I8  
 I  ! I/  I:;  (   :;  'I   I     .:;'I    :;I  .?:;'I@�B   :;I   :;I  & I   :;I  4 :;I  4 :;I  1XY   1  �� 1  �� �B1  . ?<n:;    U%   R    .   �      ../sysdeps/i386  start.S     ��<3!4=%" YZ!"\[ #       �       init.c     i    -   �      ../sysdeps/i386  crti.S     ��>"�g//   ��    �� != �   �  �      /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include/bits /usr/include/sys /usr/include ../libfat ../libinstaller  syslinux.c    stddef.h   types.h   types.h   time.h   stat.h   stdint.h   stdio.h   libio.h   libfat.h   syslxopt.h   syslxfs.h   setadv.h   syslinux.h   stdlib.h   errno.h   string.h   unistd.h   <built-in>    fcntl.h   stat.h     *�1g��gX&��q�Ku�Yt[-=u=O"�f>�=;_X�q�Ku�Yt[-=u=O  0��fX�v��� � � �� ��	f�;/LX�;gK �� �gi��Y� � eL�� t[
"� ���5˽;/P � ;w�� t|g=�-g�-/�;/u��I!��k)�[9 � � ) !$��kfY9Z gg��Xt.Y/KgKuK׃�K k�<KK�K�� tui��[� Ju������]    y   �      ../libinstaller /usr/include  fs.c   syslxint.h   stdint.h   syslxfs.h   syslinux.h   string.h      Xg]�;/�]u;KWgW=L� J�nKW�KujT ����KW!�~��1�ʓ+v��u#G1�W��YWz�	f[W��u�K�W�M�	�V�e
�+gd�wttu�LVQ+g�
    �   �      ../libinstaller /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include/bits /usr/include  syslxmod.c   syslxint.h   stddef.h   types.h   libio.h   stdint.h   syslinux.h   stdio.h   <built-in>    stdlib.h     C�� �aA� ��_X'�g<<g<fbJXiV.0�P<0<P<�*<Jfd� �� H-�=h,�oXg>,�=Df�kJSwf.(Jf�� J�<� <�J� tP�1fO<1fO�4�/�;KI/K!�@g�;KI/K��<� t- Y Y s	<�<� <�X� < �   �   �      ../libinstaller /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include/bits /usr/include  syslxopt.c   stddef.h   types.h   libio.h   getopt.h   syslxopt.h   stdio.h   setadv.h   syslxcom.h   stdlib.h   <built-in>      A�� X=�mtWf
�f � X "�NYMe�X�Xiu$>,�A.;K�DX(�X�K��S�^�;Y���;Y�i��Z�Z�[�]Kg\�[�;YZ�`�Z�Z�ZYK�Zi���0���zMq#/��P�":���":�	 R   �   �      ../libinstaller /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include /usr/include/bits  setadv.c   syslxint.h   stddef.h   stdint.h   string.h   errno.h     ��)'yXJ9.Of Y ;�+fUȑM��X��:]=vM[N�M/k.tg�Xg[=;/h�;/?ic1�W/ZmJ��",LV>u/;XXp<�;��ntr�s���LgL ;    5   �      ../libinstaller  bootsect_bin.c    :    4   �      ../libinstaller  ldlinux_bin.c    A   �   �      ../libfat /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include/sys /usr/include  open.c   ulint.h   stddef.h   types.h   stdint.h   libfat.h   fat.h   libfatint.h   stdlib.h     ����� <�.�;u/h��� �	�H;=?I@�Gh�=xJf�F\8@w@�>d>0-ug�uK�;yh�g���/�t=ggI �    �   �      ../libfat /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include  searchdir.c   stddef.h   stdint.h   libfat.h   ulint.h   fat.h   libfatint.h   string.h     w��9i�9?����;/�=g�>i�n<�c X    �   �      ../libfat /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include/sys /usr/include  cache.c   stddef.h   types.h   stdint.h   libfat.h   libfatint.h   stdlib.h     V�6X?= v L ; = �NVX�� <K� �^�;/K��=-N)�x;/;>>/ "   �   �      ../libfat /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include  fatchain.c   ulint.h   stddef.h   stdint.h   libfat.h   libfatint.h     :�fgK>K�;=- .[�	X��/jg���>u����0:00K�1k7AAK�xfR�qY\y0�Ft<fMy>�Ct?f>Z��sU\ U    -   �      ../sysdeps/i386  crtn.S     ؈'=!  �,=! long long int short unsigned int long long unsigned int unsigned char GNU C11 5.3.0 -march=i586 -mtune=i686 -mpreferred-stack-boundary=4 -g -O3 -std=gnu11 -fgnu89-inline -fmerge-all-constants -frounding-math -ftls-model=initial-exec _IO_stdin_used short int init.c /glibc-tmp-ec9b8d6964164aa7972612c322780d61/glibc-2.23/csu sizetype __off_t pwrite64 _IO_read_ptr _chain st_ctim install_mbr __u_quad_t uint64_t _shortbuf ldlinux_cluster update_only libfat_searchdir VFAT MODE_SYSLINUX done _IO_buf_base fdopen secp errmsg BTRFS mtc_fd syslinux_adv libfat_sector_t __gid_t intptr_t st_mode mtools_conf setenv program libfat_clustertosector __mode_t set_once bufp _IO_read_end _fileno dev_fd _flags __builtin_fputs __ssize_t _IO_buf_end _cur_column syslinux_ldlinux_len __quad_t _old_offset tmpdir asprintf count syslinux_mode pread64 xpwrite st_blocks st_uid _IO_marker /tmp/syslinux-4.07/mtools ldlinux_sectors nsectors fprintf command stupid_mode sys_options ferror GNU C11 5.3.0 -mtune=pentium -march=i586 -g -Os _IO_write_ptr libfat_close _sbuf bootsecfile device directory syslinux_patch _IO_save_base __nlink_t __st_ino sectbuf _lock libfat_filesystem syslinux_reset_adv _flags2 st_size mypid perror getenv unlink fstat64 tv_nsec __dev_t tv_sec __syscall_slong_t _IO_write_end libfat_open heads _IO_lock_t _IO_FILE __blksize_t MODE_EXTLINUX stderr _pos parse_options target_file _markers __blkcnt64_t st_nlink __builtin_strcpy syslinux_make_bootsect __pid_t menu_save st_blksize timespec _vtable_offset syslinux.c exit NTFS __ino_t st_rdev usage long double libfat_xpread syslinux_ldlinux activate_partition argc __errno_location fclose open64 mkstemp64 __uid_t _next __off64_t _IO_read_base _IO_save_end st_gid __pad1 __pad2 __pad3 __pad4 __pad5 __time_t _unused2 die_err st_atim argv mkstemp status MODE_SYSLINUX_DOSWIN popen calloc st_dev libfat_nextsector _IO_backup_base sync st_mtim fstat raid_mode pclose patch_sectors fwrite secsize slash getpid force __ino64_t strerror syslinux_check_bootsect main _IO_write_base EXT2 bsUnused_6 bsTotalSectors ntfs_check_zero_fields clustersize bsMFTLogicalClustNr bs16 dsectors fatsectors bsOemName ntfs_boot_sector bsFATsecs bsJump bsMFTMirrLogicalClustNr retval check_ntfs_bootsect FATSz32 uint8_t bsHeads bsSecPerClust bsForwardPtr bsResSectors bsUnused_1 bsUnused_2 bsUnused_3 FSInfo bsUnused_5 memcmp bsSectors bsHugeSectors bsBytesPerSec bsClustPerMFTrecord get_16 bsSignature bsHiddenSecs ExtFlags bsRootDirEnts bsFATs rootdirents get_8 uint32_t bsMagic BkBootSec media_sig RootClus FSVer bs32 ../libinstaller/fs.c syslinux_bootsect uint16_t bsVolSerialNr check_fat_bootsect Reserved0 fs_type bsZeroed_1 bsZeroed_2 bsZeroed_3 fserr fat_boot_sector sectorsize bsClustPerIdxBuf bsZeroed_0 get_32 bsMedia bsSecPerTrack bsUnused_0 bsUnused_4 subvollen sectp subvol set_16 set_64 secptroffset checksum sect1ptr0 sect1ptr1 diroffset instance ../libinstaller/syslxmod.c adv_sectors epaoffset sublen syslinux_extent csum xbytes ext_patch_area dwords advptroffset subdir data_sectors raidpatch stupid nsect secptrcnt advptrs patcharea magic subvoloffset dirlen nptrs addr set_32 generate_extents maxtransfer offset_p long_only_opt ../libinstaller/syslxopt.c syslinux_setadv long_options has_arg name opt_offset short_options optarg OPT_RESET_ADV optind OPT_DEVICE OPT_ONCE modify_adv option flag optopt strtoul OPT_NONE getopt_long memmove ../libinstaller/setadv.c adv_consistent left ptag syslinux_validate_adv advbuf plen advtmp cleanup_adv syslinux_bootsect_len ../libinstaller/bootsect_bin.c syslinux_bootsect_mtime ../libinstaller/ldlinux_bin.c syslinux_ldlinux_mtime malloc read8 bpb_extflags le32_t ../libfat/open.c bpb_fsinfo read16 clustshift bsReserved1 bsBootSignature bsVolumeID barf fat_type read32 bpb_fsver bsDriveNumber libfat_sector fat16 bpb_rootclus minfatsize le16_t bsCode bsVolumeLabel nclusters FAT12 FAT16 readfunc rootdirsize rootdir bpb_fatsz32 fat32 FAT28 readptr le8_t libfat_flush free bpb_reserved bpb_bkbootsec endcluster bsFileSysType libfat_get_sector rootcluster clustsize ctime attribute caseflags atime ../libfat/searchdir.c dirclust nent clusthi clustlo libfat_direntry ctime_ms fat_dirent lsnext ../libfat/cache.c fatoffset nextcluster clustmask fsdata ../libfat/fatchain.c fatsect ���� ���� S        ���� ����� V�W���� V�W�        ��ؒ P�� P        ���� 0��� � �\�� �\        �7� �        C�\� �\��� S        C�\� �\��� V�W����� V�W�        q��� P���� P        F�\� 0�\��� �\�� �\        ��� P�� u���� P�b� u��n�T� u��        ��� P�� PU�_� P        ݋� P�K� Sn�֌ Sی�� S        ��� P        ��� P�3� S>��� S        ���� P���� S��΍ P΍J� S        8�D� PD��� V        Q�t� P�R�u��� P�R�        E�T� u�T�^� s 3$u�"�^�l� s3$u�"�z��� s 3$u�"����� t 3$u�"����� t3$u�"�        $�3� P3�T� u�        E�P� P        E�T� 0�T��� S���� t ���� t        ���� P        ��� W        ��(� u�H�P� u�        ���� P���� p�|���� S�� s��'� SH�P� S        !�'� u��'�:� S:�H� u��H�x� Px��� R���� p����� R���� u����� p����� P���� p����� P���� R���� u���Ï PÏǏ p�Ǐӏ P        !�5� u�W�5�6� W6�H� u�W�        :�ݏ V        !�H� 1�H�_� Qc�j� Qo��� 0����� Q���� 0���ӏ Q            1    � 1   @    P@   _    �            1    �         6   @    P@   [    �         �   �    P�   �  	 v�
���  #  	 v�
���        k   ~   V~  �   �         �   �    V        �      �        �      V        �      
 �             Q�S�  !   Q�S�        9  D   �PD  K   P�R�K  S   q �3�%� %�{     �P  �  
 �        �  �   �X�3�%�P�%��  �   v��:�%�P�%�        +  c   �@c  l   Q�S�n  �   Q�S�        {  �   �,�O��:�%�,�%�        c  f   Pf  i   pq�i  �  	 v�
���        �      Q  �   v���          w   �          w   V            {    � {   �    Q�   �   ���  �   �             D   ��  �   �            b   �s  �   ��  �   �        <   �   S        /   �   S        &   �    P�   �   �H#��  �   P�  �   �H#�        �  �   ��>��  �   R        �  �   0��  �   P        �   �    W�   �   �D        �   �    �\#�
����   �    Q�   �    �\#�
����   �    Q�      �\#�
���        <   U    s�U   [    r�[   e    �\#�e   }    �\#�}   �    �\#��   �   �\#
��  b   �\s  �   �\#��  �   �\#�        U   e    v         e   u    v        }   �    
��        �   �    p~�        �   �    s�        �   �    2�        �   �    s
�        �   �    W        �   �    s�        �   �    1�        �   �    s�        �   �   �\#
��  b   �\s  �   �\#��  �   �\#�        �   �    p}��      �H1�  H   q  �H"�H  �  	 �L �H"��  �  
 �H�L2��  �   q  �H"��  �  	 �L �H"�        �      ��  "   q3$v "�"  H   q3$v "�H  �   �L#3$v "��  �   q3$v "��  �   �L#3$v "�        �   �    Q�      �\#�
���        �   �   �X�  �   w
��  �   �X#
��  �   �X        �      
 ��  J   RJ  �   ���  �   �L#A9$��  �   R�  b   ��s  �   ��        �      
 ��  �   �@�  �   Q�  �   ���  �   �@        8  =   q 3$v "#�W�=  H   q 3$v "#�q 3$v "#�H  �   �L3$v "#��L3$v "#��  �  
 �������  �   �L3$v "#��L3$v "#�        �     
 �          �   �P�  �  
 �������  �   �P        �      0�  �   P�  �   w��  �   W�  �   P        P  R   RR  �   ��        �  �   �P        �  �   �X        �  �   P        �  �   �X#�        �  �   �P        �  �   �X        �  �   P        �  �   �X#�        �  b   �\s  �   �\#��  �   �\#�             V�W�        ,  8   V�W�        Q  b   Qs  �   Q        �  �   Q        �  �   0�        �  �   s�        �  �   R        �  �   s�        [  �   P�  �   P�     P"  �   P�  �   P  Q   Pm  r   P�  �   P�  �   P�  �   P�     P6  >   P        �  
   0�
     	��  8   SN  Q   	��Q  W   SW  Z   P                P   @    V@   D    �P�               8�   *    P               �g�   D    R                �/-Z�                P        $   -    R        $   -    v�        -   7    �d�(�        -   7    v��        t   z    ��{�z   �    S�   �    s��      P  E   S        t   �    
���   �    R�   �    ��{�   �    R�      R  8   R=  E   R        �   �    Q�   �    s �   �    Q�   �    Q�   �    s =  E   Q        �   �    P�   �    P�   �   
 s��#��     
 s��#�=  E   P        m  �   � �     P     �      P     �         u  �   �         �  �   R        �  �   Q        �  �   p���  �   V        �  �   R        �  �   Q                0�       P   �   S        <   �   P�  �   P�  �   P        c   t    �\   �   �\        �   �    V�   �   �P        �   �    W�   �   �X        E  G   RX  Z   Re  r   Rr  u   r 9%�u  �   R        �   �    p�
��5$#�9&�        �   �    p �        �   �    p$�        S   Y    PY   �    S        \   \    R\   �    �T�   �    R�   �    �T�   �    R�   �    �T�   �    R�   �    �T# �               �X$   �    �X           !    P"   )    S)   .    P               P   )    S)   .    P        C   S    PS   X    pt�X   i    Po   {    P�   �    P�   �    R�   �    �X            I    � I   J    SJ   N    �                 �   4    Q4   :    p�        N   �    ��   �    P�R��   -   �        �   �   S�  �   S�  �   S        Y  [   p ��[  �   �P����  �   R�  �   P�  �   P     P  '   �        &  I   WI  O   RO  Y   w�Y     W  �  
 s 1&s "#��  �   S�      S        �  �   s 9%�,�%�\#�%"��  �   s 9%�,�%�\#�%"�        ;  U   Pn  �   P�  �   P�     P        Q   R   	 �\#1�        �   Y   �P�     �P         ����    ��Έ �$� ��        ������	�        *�0���        O   R   U   [   _   e           �   �   �   �           C  �  �  �          �  �  �                  $          �  �  �  �          ����    ؈݈��                            T�          h�          ��          ̂          l�          چ          0�          p�          ��     	     ��     
     ��           �          0�           �           �          ��          ��           �          (�          0�          4�          ��           �          ��          @c                                                                                                                      !             ��            ��    �      !   (�      /   0�      <   0�      >   `�      Q   ��      g   dc     v   hc     �    �                  ���   $�      �   H�      �   0�      �   Щ      �            ���   �c     �            ���   ��)     �            ��            ��           ��  ��D                 ��'           ��3           ��;           ��F           ��U           ��             ��c   �       t  4�      }   �       �  ��       �   �      �  ��     �  C�     �             �              �   �    �  ��         _     ,  @c     >             Q             e             u  ��     �  ��     �             �  ���    �  @c      �             �  r�v    �  �e     �                w��       p��   �   �        Dc     ,             =  ���     O  ��0    W  X�     d  :�N     {  ��     �             �  @�     �  Hc     �             �             �               @� �      @�     !             3  ,�     @             R  �      e             w             �             �  ��      �             �             �  ��     �              �             �  ��     �                          !  $�     0  �e     8             O  `�@    \  U�;     d             w             �             �             �  V�.     �  ��     �   �e     �  ��     o  �i                   �  ��         �     $             8  ���    D  @c      P  ߟ	    `  0��    e  A�1    k  *�+     o              �             �  C��    %             �  �e     �  �4     �  @c     �              �  ��     �  `c     	  !�"    !             �  ��     
 2             C   �<     G             W              init.c crtstuff.c __CTOR_LIST__ __DTOR_LIST__ __JCR_LIST__ deregister_tm_clones __do_global_dtors_aux completed.6563 dtor_idx.6565 frame_dummy __CTOR_END__ __FRAME_END__ __JCR_END__ __do_global_ctors_aux syslinux.c sectbuf.4461 fs.c fserr.2899 syslxmod.c syslxopt.c setadv.c cleanup_adv open.c searchdir.c cache.c fatchain.c bootsect_bin.c ldlinux_bin.c __init_array_end _DYNAMIC __init_array_start __GNU_EH_FRAME_HDR _GLOBAL_OFFSET_TABLE_ __libc_csu_fini xpwrite open64@@GLIBC_2.1 _ITM_deregisterTMCloneTable __x86.get_pc_thunk.bx syslinux_make_bootsect stderr@@GLIBC_2.0 memmove@@GLIBC_2.0 pwrite64@@GLIBC_2.1 free@@GLIBC_2.0 syslinux_validate_adv modify_adv ferror@@GLIBC_2.0 libfat_nextsector _edata fclose@@GLIBC_2.1 parse_options syslinux_adv memcmp@@GLIBC_2.0 libfat_searchdir __divdi3 optind@@GLIBC_2.0 popen@@GLIBC_2.1 libfat_get_sector fstat64 libfat_close libfat_clustertosector syslinux_ldlinux_mtime unlink@@GLIBC_2.0 syslinux_bootsect optopt@@GLIBC_2.0 perror@@GLIBC_2.0 fwrite@@GLIBC_2.0 __fxstat64@@GLIBC_2.2 syslinux_ldlinux short_options strcpy@@GLIBC_2.0 __DTOR_END__ getpid@@GLIBC_2.0 syslinux_reset_adv getenv@@GLIBC_2.0 mkstemp64@@GLIBC_2.2 malloc@@GLIBC_2.0 __data_start system@@GLIBC_2.0 strerror@@GLIBC_2.0 __gmon_start__ exit@@GLIBC_2.0 __dso_handle fdopen@@GLIBC_2.1 pclose@@GLIBC_2.1 _IO_stdin_used program getopt_long@@GLIBC_2.0 long_options die_err strtoul@@GLIBC_2.0 setenv@@GLIBC_2.0 __libc_start_main@@GLIBC_2.0 fprintf@@GLIBC_2.0 libfat_flush syslinux_ldlinux_len __libc_csu_init syslinux_bootsect_len __errno_location@@GLIBC_2.0 _fp_hw asprintf@@GLIBC_2.0 libfat_open __bss_start syslinux_setadv main usage die _Jv_RegisterClasses pread64@@GLIBC_2.1 syslinux_patch mypid libfat_xpread __TMC_END__ _ITM_registerTMCloneTable syslinux_bootsect_mtime optarg@@GLIBC_2.0 syslinux_check_bootsect fputs@@GLIBC_2.0 close@@GLIBC_2.0 opt sync@@GLIBC_2.0 calloc@@GLIBC_2.0  .symtab .strtab .shstrtab .interp .note.ABI-tag .hash .dynsym .dynstr .gnu.version .gnu.version_r .rel.dyn .rel.plt .init .plt.got .text .fini .rodata .eh_frame_hdr .eh_frame .ctors .dtors .jcr .dynamic .got.plt .data .bss .comment .debug_aranges .debug_info .debug_abbrev .debug_line .debug_str .debug_loc .debug_ranges                                                   T�T                    #         h�h                     1         ���  D               7         ̂�  �              ?         l�l  m                 G   ���o   چ�  T                T   ���o   0�0  @                c   	      p�p  (                l   	   B   ���                u         ���  -                  p         ���  @                {          �                     �         0�0  �                 �          � *                    �          � *  �                  �         ���6  �                  �         ���7  �                 �          � ?                    �         (�(?                    �         0�0?                    �         4�4?  �                         ���?                   �          � @  �                 �         ���@  ��                  �         @c@�  `                  �      0       @�                   �              X�  �                 �              @�  bB                              � �                              R* �                      0       �9 �                )             �J �                 4             pc                                9v B                               �d P
  $   F         	              �n i                                                                                                                                                                                                             ./.wifislax_bootloader_installer/mbr.bin                                                            0000644 0000000 0000000 00000000670 12721137577 017375  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   3���؎м |��W����� � ��  RR�A��U1�0���r��U�u��s	f���B�Z����?Q��@��RPf1�f��f �!Missing operating system.
f`f1һ |fRfPSjj��f�6�{����Œ�6�{���A���{��dfa������}���  ��f`�廾� 1�SQ��t@�ރ���Ht[y9Y[�G<t$<u"f�Gf�Vf�f!�uf����r��f�F������fa��b Multiple active partitions.
f�DfFf�D�0�r�>�}U�����{Z_���� Operating system load error.
^���>b��<
u�����                                                                                                            ./.wifislax_bootloader_installer/syslinux64.com                                                     0000644 0000000 0000000 00000341300 12721137577 020671  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ELF          >    �@     @       ��         @ 8 	 @ % "       @       @ @     @ @     �      �                   8      8@     8@                                          @       @     �>      �>                    (N      (N`     (N`     ؕ      8�                    PN      PN`     PN`     �      �                   T      T@     T@                            P�td   �8      �8@     �8@     �       �              Q�td                                                  R�td   (N      (N`     (N`     �      �             /lib64/ld-linux-x86-64.so.2          GNU                   %   ,       $                          !   +       *             (      %      &                             )       '   "                                                                                                        	                                               
               #                                        �                      !                     H                      %                      1                                                                                      2                      m                            �`            �                      �                      �                      g                      n                                           `                      �                      A                      &                     �     �`            �                      M                      �     �`            �                      �                      |                      �                      �                      Y                      �                      9                      ,                                            \                      t                      �                                            �                      p                      �                      �      �`             libc.so.6 strcpy exit optind perror unlink popen getpid pread64 calloc __errno_location open64 memcmp fputs fclose strtoul malloc asprintf getenv optarg stderr system optopt getopt_long pclose fwrite mkstemp64 fprintf fdopen memmove sync pwrite64 strerror __libc_start_main ferror setenv free __fxstat64 _ITM_deregisterTMCloneTable __gmon_start__ _Jv_RegisterClasses _ITM_registerTMCloneTable GLIBC_2.2.5                                                                ui	   �      �O`                   �O`                   �O`        $           �O`        )            �`                   �`                   �`                    �`        +           P`                    P`                   (P`                   0P`                   8P`                   @P`                   HP`                   PP`        	           XP`        
           `P`                   hP`                   pP`                   xP`                   �P`                   �P`                   �P`                   �P`                   �P`                   �P`                   �P`                   �P`                   �P`                   �P`                   �P`                   �P`                   �P`                   �P`                    �P`        !           �P`        "            Q`        #           Q`        %           Q`        &           Q`        '            Q`        (           (Q`        *           H��H��A  H��t�[  �	  �  H���            �5�A  �%�A  @ �%�A  h    ������%�A  h   ������%�A  h   ������%�A  h   �����%�A  h   �����%�A  h   �����%�A  h   �����%�A  h   �p����%�A  h   �`����%�A  h	   �P����%�A  h
   �@����%zA  h   �0����%rA  h   � ����%jA  h   �����%bA  h   � ����%ZA  h   ������%RA  h   ������%JA  h   ������%BA  h   ������%:A  h   �����%2A  h   �����%*A  h   �����%"A  h   �����%A  h   �p����%A  h   �`����%
A  h   �P����%A  h   �@����%�@  h   �0����%�@  h   � ����%�@  h   �����%�@  h   � ����%�@  h   ������%�@  h    ������%�@  h!   ������%�@  h"   ������%r?  f�        AWAVAUATUSH��$  �|$H�4$����H�4$���  1ҋ|$H�H���  �y  H�=A   u1��@   �A  H�=�@   u&�=�@   uH�=�@   u�=�@   
H�=�@   tH�5�  �L+@ ������   ��+@ ����H�=�@  H��H�ŸG+@ �   HD�1���������yH�=~@  �   H�t$ ���M  ��x�=z@   u9�D$8% �  - `  � ���t$H�D@  H�=��  ��+@ 1�������   �����)@  �   �@�` ����  1��@�` �1  H��H����   H�|$1�H���+@ �������x
H�|$H��uH���v  �9�����x?��+@ ������H��H��t+Hc"�  D��?  H�ǉپ�+@ 1��2���H���J�����tH�|$�H���g�����u�H�t$�   �T,@ �/�����tH�=��  ���������`�` �T  �],@ �F�����+@ ��,@ �W���H��I��u
��,@ �  D�-*&  H���   � T` L��L���v���I9�u�L��   �   �`�` �Z���H=   u�L��������u��ą�u����  �   E1���	���'���Hc�#@ I���f  1�I�ź�-@ 1�H���  L����0  H��E��tD9�~H��L��K���C  I����L��E1�A� T` �d  L�8>  �>  E1ɋ>  D��L����  ���  ��	D9�~,K��>  L��   ��I��I��   H��	H��V  ��H�-�=  H���X  H��$�   ��,@ �z���H��$�   H��$�   �   H���  �U ��tp��/t��\u���   uX�G��'t1���!u;1�H9�sCH�W�'H9�s4H�W�G\H9�s'H�W@�u H9�@�ws�G'H���H9�s
�H���H��H��뉅�u�/H�Ǿ�,@ �����H��$�   H��$�  ��,@ 1��g���H��$�  �
���H��$�   H��$�  ��,@ 1��>���H��$�  ������u�ą�tH�/�  H�=�  �-@ 1��L����&H��$�  H��$�   �g-@ 1������H��$�  ��G-@ �����u�ą�tH���  H�=��  �{-@ 1������H�|$������M<  �   �߾@�` �  �   �@�` ��  �'<  �   �@�` ���v  ���G��������H�ĸ$  1�[]A\A]A^A_�f.�     @ 1�I��^H��H���PTI���*@ H��0*@ H�ǀ@ �����fD  H�=��  H���  UH)�H��H��vH��9  H��t	]��fD  ]�@ f.�     H�=��  H�5��  UH)�H��H��H��H��?H�H��tH�i9  H��t]��f�     ]�@ f.�     �=q�   ubUH�w7  H�h�  H��ATSH�k7  L�%\7  H)�H��H��H9�s@ H��H�5�  A��H�*�  H9�r�����[A\]��  �� H�=!7  H�? u�.���fD  H��8  H��t�UH����]����H��PH�=��  H���  �(+@ 1������   �����SH��������8�����H�=��  H���  I��H�پ$+@ 1�������   ����AVA��AUI��ATI��U1�SH��H��tJL��H��L��D������H��u�0+@ �H���u�k����8��t��_���H���G���I�I�H�H)��[H��]A\A]A^�H��P��9  H��|���Z�AVA��AUI��ATI��U1�SH��H��tJL��H��L��D������H��u�;+@ �H���u������8��t������H�������I�I�H�H)��[H��]A\A]A^Ã�H��u � R` �   H��Z�ZR` �i   H���Ã�u&f�#9  H��T�TR` ��  f��9  �WH����AVAUATUS�G<�t<���-@ �f  �G=   t*�� ����.@ ��   �D  �P��¸�-@ HD��1  �WI��H��f��u*� u$� u� uf� uf� u
�  ��  �{�.@ @�ǅ���  �H�����  �CH��u�C �KH)�H��H��H��u�S$D�C�>/@ I��H)��S����	Hc�H)���  H��u�K$I�Ƚ-/@ H���v  H�H��H=��  I����   f���/@ �T  �{&)��   L�s6�   ��/@ L���������uI���  ��.@ ��   �  �   ��/@ L��������uI���  ��.@ ��   ��   �   ��/@ L����������.@ ��   �   ��/@ L���l�����tLH�C6�`Q` H��6  �   H=����`.@ ��   �{B)�H.@ ��   H�{R�   ��/@ � �����uk1�M��tdA�$   �ZH���   ��/@ H���������t1�   ��/@ H���������t�   ��/@ H����������o/@ u1�M��tA�$   [H��]A\A]A^Ë[  A� T` D���  A��	A��A9��a  A�;��>tI����AWAVAUATUSH�oH��(E�{L�'I�� T` �sD�� R` �sI�� ��D�� R` t�Kfǁ R` �����fA�C
 �D$A�B�fA�C�D$A�CtfA�C �S
�CL�L$L�D$H�� T` A9�~H�5��  ��/@ �����   �����Hk�
H��1�E�B�I��A� �  � �  �1�E��tm��M�)tE�xA��A��	D�t$A��I�M9�u �|$��  wD�t$G�t&�A1�A��  ��tH�
f�BH��
A���   �I�́�   A��I����L��뎅�tH�
f�BA��A�� T` Mc�I��H�|$ J�T�H�� T` J�T�H��T` tIH�|$1�H�����C��9�~H�5��  ��/@ �����   ������CHc�H�t$H T` H���H�|$ tIH�|$1�H�����C��9�~H�5v�  �)0@ �L����   �����CHc�H�t$H T` H���A�C    1����>9D$~+� T` H����D$A�SH��([]��A\A]A^A_Ã��Ã�US��P��torN����   H��  H�=��  ��3@ 1��+���H�=��  �G1@ �J1@ 1�����H�5��  �I3@ �����rH���  H�=��  �T0@ 1�������   H���  H�=��  ��0@ 1�������G1@ �e��t\H�=e�  �G1@ �J1@ 1�����H�5M�  �I3@ �#�����uH�57�  ��3@ �������uH�5!�  �A4@ ��������0�����/@ H�=�  �J1@ 1��H���H�5��  �I3@ �ATUA��SH�H����H���  E1��`6@ �@6@ H��D���l��������  ��f�  ��   ��M�.  6����  ����  �2     릃��5  ��H�  �`  ��U��  ��O��  ��S��   �>  ��a��  ��d�,  H��  H��1  �H�����r�  4��i�  ��h��  ��1��  ��m��  ��o�  ��  ��u��   ��s��   ��t�(  �  ��v��  ��z��  �#1  @   �1      �����N1     ����H�=b�  1�1��q�������0  �ȃ�>�����H�w�  �h4@ �1H�=1�  1�1��@�������0  ��=�   �W���H�D�  ��4@ H�=�  1��a����@   �'�����0     �$����z0     �����0      �����p0     �������uH���  H�=��  ��4@ 1�������H���  H�50  �����H�=y�  1�1������:0  ����H�
0  S0@ ����H�N�  H�0  �����0     �w����0     �h�����uTH��  H��/  �P���H�=�  H�6�  �5@ 1��Z���1���������  H��  �B5@ H�=��  1��3����޿@   �������Hc��  tr��u6�PH�D� ���  H�_/  �H�=M/   u�PH�D� �u�  H�6/  Hcg�  H��H�T� H��t��u��H�D/  �F�  Hc?�  H�|�  �p���[]A\�USQ�=�.   t
�`�` ��  H��.  H��u1��@H���1�H��H���   H��H��H�4�   ��t�H��  H�=��  �[5@ 1��8���H��.  H��tBH���1�H��H���   H��H��H�4(�e   ��tH���  H�=��  ��5@ 1����������Z[]�H����/-Z1��g�+TH��H=�  u�H��   �Vǆ�  d�(ݹ�   H����AV�G�AUATUSH��   =�   v�w����    �   H���   H��wsA���h�` �}   H��I��I����  I��A�A�@H����t4A9�uH9�s*I�4 H��L��H)�����I����H9�wH)�I�H��w��hH��t9H�EH9�v������    ����QI�@E�0A�hL��H��H)�H��H���I��1�L��H���h�` �}   L��H���`�` �����1��H��t��H��   []A\A]A^�H�wH���}   1�H���H�������?�/-ZH��u=���  d�(�u11�1�LH��H���  u��g�uH��   ��   H��H���G��   �/-Zu@���  d�(�u4H��   1�1��  H��H���  u��g�u��   H���1��H���I�������ATUI��S�P   H�������H��1�H���'  1�H��H�CH    L�#H�k�  H����   f�x ��   �p1ɿ   ����D��A9�t����	u���   �S�P�K��u�P D�HD�@H�S@E��L�C(uD�H$�pA��J�<�pH�{0�����  ��	Hc�H�H9�H�s8vpH)�H��J���  �Kw���C    ����%����  w�C   �������w2�C   �����  ��	A9�r�{u�@,�C ��C     H���
H���j���1�[]A\�SH����   H��[�Q���AWAVI��AUATI��USI��AP�n  H��H����   H���u����   H��L���   H��H��t�E1��   L��H���������u5M��tI�T$�   H��H���I�,$E�|$�{ t:�C�S����+�; t!A�� H�� A��   u�H��L���  �a��������Z[]A\A]A^A_�SH�GHH�GH    H��tH�XH���i���H����[�H�GHH��tH90uH���H�@��AUATI��US�  QI������H��H��uL�������  �h���H��1�H��t=H�]I�}L��   H��A�U =   tH�������1��I�EHL�e I�mHH�EH��Z[]A\A]Å�u�w ��uH�G0�H�����~9w~�O��Hc�H��HG8�H�W8H9�vH;w0�Y  H�FH9��H  �D  AUATUSH��AP�GH)ӍP�H��H��H��t	H�F�  �OH���;_��   �GH������   r����   ��   A��A��A�D����	Hw(����H����   D��A��H��D����  ��	Hu(D�,�v���H����   A���  B� ��D	�������  ��E����  �Rۉ���	Hw(�2���H��tR���  �4����  �+������	Hw(�
���H��t*���  �4����������~1��YH��[]A\A]�t���H���Z[]A\A]�1��H����f�     AWAVA��AUATL�%�#  UH�-�#  SI��I��L)�H��H������H��t 1��     L��L��D��A��H��H9�u�H��[]A\A]A^A_Ðf.�     ��f.�     @ H����   �����H�a#  H���t(UH��SH�O#  H�� H����H�H���u�H��[]�� H������H���                            %s: %s: %s
 short read short write /tmp At least one specified option not yet implemented for this installer.
 TMPDIR %s: not a block device or regular file (use -f to override)
 %s//syslinux-mtools-XXXXXX w MTOOLS_SKIP_CHECK=1
MTOOLS_FAT_COMPATIBILITY=1
drive s:
  file="/proc/%lu/fd/%d"
  offset=%llu
 MTOOLSRC mattrib -h -r -s s:/ldlinux.sys 2>/dev/null mcopy -D o -D O -o - s:/ldlinux.sys failed to create ldlinux.sys 's:/ ldlinux.sys' mattrib -h -r -s %s 2>/dev/null mmove -D o -D O s:/ldlinux.sys %s %s: warning: unable to move ldlinux.sys
 mattrib +r +h +s s:/ldlinux.sys mattrib +r +h +s %s %s: warning: failed to set system bit on ldlinux.sys
 LDLINUX SYS invalid media signature (not an FAT/NTFS volume?) unsupported sectors size impossible sector size impossible cluster size on an FAT volume missing FAT32 signature impossibly large number of clusters on an FAT volume less than 65525 clusters but claims FAT32 less than 4084 clusters but claims FAT16 more than 4084 clusters but claims FAT12 zero FAT sectors (FAT12/16) zero FAT sectors negative number of data sectors on an FAT volume unknown OEM name but claims NTFS MSWIN4.0 MSWIN4.1 FAT12    FAT16    FAT32    FAT      NTFS     Insufficient extent space, build error!
 Subdirectory path too long... aborting install!
 Subvol name too long... aborting install!
 Usage: %s [options] device
  --offset     -t  Offset of the file system on the device 
  --directory  -d  Directory for installation target
 Usage: %s [options] directory
  --device         Force use of a specific block device (experts only)
 -o   --install    -i  Install over the current bootsector
  --update     -U  Update a previous installation
  --zip        -z  Force zipdrive geometry (-H 64 -S 32)
  --sectors=#  -S  Force the number of sectors per track
  --heads=#    -H  Force number of heads
  --stupid     -s  Slow, safe and stupid mode
  --raid       -r  Fall back to the next device on boot failure
  --once=...   %s  Execute a command once upon boot
  --clear-once -O  Clear the boot-once command
  --reset-adv      Reset auxilliary data
   --menu-save= -M  Set the label to select as default on the next boot
 Usage: %s [options] <drive>: [bootsecfile]
  --directory  -d  Directory for installation target
   --mbr        -m  Install an MBR
  --active     -a  Mark partition as active
   --force      -f  Ignore precautions
 %s: invalid number of sectors: %u (must be 1-63)
 %s: invalid number of heads: %u (must be 1-256)
 %s: -o will change meaning in a future version, use -t or --offset
 %s 4.07  Copyright 1994-2013 H. Peter Anvin et al
 %s: Unknown option: -%c
 %s: not enough space for boot-once command
 %s: not enough space for menu-save label
 force install directory offset update zipdrive stupid heads raid-mode version help clear-once reset-adv menu-save mbr active device            t:fid:UuzsS:H:rvho:OM:ma        �5@                     f       �5@                     i       �5@                    d       �5@                    t       �5@                     U       �5@                     z       6/@                    S       �5@                     s       �5@                    H       �5@                     r       �5@                     v       �5@                     h       
6@                           6@                     O       6@                            6@                    M       #6@                     m       '6@                     a       .6@                                                           c��Q   c��Q �  ;�      @���8  ����(   ���  `���`  ����x  �����  3����  H����  ����x  ����  �����  $���   F���@  ����p  �����  �����  �����  ���  ����(  ����X  ���x  �����  �����  ����   ����8  @����  �����  �����             zR x�      ����*                  zR x�  $       ���@   FJw� ?;*3$"       D   ����(    D       \   ���:    A�  <   t   *���q    B�E�E �D(�C0�S(D BBB         �   [���    EO <   �   X���q    B�E�E �D(�C0�S(D BBB      L     `���b   B�B�B �B(�A0�A8�G�ID8C0A(B BBB         \  9���T           <   t  u����   B�B�B �A(�A0�{(D BBB     L   �  �����   u�B�B �B(�A0�A8�H`28A�0A�(E� B�B�B�      ����"   D�A�C   ,   $  �����   B�A�D ��AB     $   T  j����    A�A�A �AA   |  ����?           D   �  #���   B�E�B �A(�A0�G��0A(A BBB          �  ����              �  �����           ,     ���N   B�A�D �CAB        <  ����    A�L       D   \  �����    B�B�E �B(�D0�A8�E@�8A0A(B BBB   �  ���%    A�c       <   �  ����    [�B�D �A(�F0j(A� A�B�B�         o���/           T     ����q   g�B�A �A(�E0
(D� A�B�B�EE(A� A�B�B�     D   t  ����e    B�B�E �B(�H0�H8�M@r8A0A(B BBB    �  ����              �  ����                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           ��������        ��������                                      @            �*@            x@            �@            �@     
       �                                           P`            H                           �
@            �	@            �       	              ���o    �	@     ���o           ���o    ~	@                                                                                                                                     PN`                     F@     V@     f@     v@     �@     �@     �@     �@     �@     �@     �@     �@     @     @     &@     6@     F@     V@     f@     v@     �@     �@     �@     �@     �@     �@     �@     �@     @     @     &@     6@     F@     V@     f@                                                     filesystem type "????????" not supported                                                        ����                                                            �X�SYSLINUX                                                                               ��1ɎѼv{RWV���&�x{�ٻx �7�V �x1���?�G�d��|�M�PPPP��b�U��u�����Ov1���s+�E�u%8M�t f=!GPTu�}��u
f�u�f�u��QQf�u��QQf�6|��� r �u��B�|��?�|���U�A�� r��U�u
��t�F} f�ﾭ�f������ �� f�>���Bout��f`{fd{� �+fRfPSjj��f`�B�w fa�dr�f`1��h fa���F}+f`f�6|f�>|f��1ɇ�f��f=�  w��A�ňָ�/ far���1��ּh{��f�x ��}� �t	�� ���1�������t{��Boot error
                  ��>7U�
SYSLINUX 4.07  
    ��>��Bo             �0�5�  �� ��� ��|��f��M�f�f���f�(�f�޾恀>F} u����� �6 0�OSf�6 �I�*f�f�Tf�l)�fSf����1��K f[�.|f��
��^f�|��f�$�f)�f�(�f��u�ځ� ��fIu��f!����ׁ�� ���f`f`{fd{�QU� f��� fRfPSWj��f`�B��fa�dr]f�f�� )��>|�!�u�fa�f`1���fa�����Q]fRfPUSf�6|f�>|f��1ɇ�f��f=�  �<��I )�9�v����A�ň֕�� f`�D�farf���|[�]fXfZf�)�u�fa�Muٕ�.,�u����;.,�v�.,��f`� �t	�� ���fa� Load error -  CHS EDD                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   1�������J��ӷ�D�f1��|�8� �Nf�0�f����fh��  �f=�u  �����!��0	������8�u3�f�_4 f��
9�s#����
R�� d]���D[X�� d$���D"�����f`f��h �t{f�`{f�d{�6|�>|f�.,�fhx �fa��}�骸�)��fhR �{t�~���H�� ��1��1��ar������8[u�>�R ���>�R���>�R �{���_!��8 � ���t����f��Rf��8f��Rf��8��f�&�8  ��� <tA< rw�� �t���8�� ����sҪ�� ��<�><	t8<t-<t<�� <t<u��� �t�O���� ��� �d���^���8��>�R u�W���� �� f�6$�f;68<v2Qf��  fhW �h)�YV�� tWQ� ��&�Y_u
� �G ���y ^���f �r0�&�8<0r�t <9v<ar�<c�{�,W�$�
� ,1���<Dw,;�c��<��[�<��U�,{W��<=��= t2�Ft-� �T�W���� �6 0� �ӷ������_W� � ���_���>�R u������>�R ����c��ɿ �� �f����� �t�0��� ��<IVfh� �w^�< w� �t�< v�N�6�8��R!�u�f�6$�f;68<v_f��  fhW �?)�V� ��< v�t�^�ـ= u�^h � ��Ӌ��&��>�R�<IW�ҹ �_1۠Ӣ�8<����s�)�>�R tiVW� �Ǿۿ ���R�&��>�R_^��8�<J �<I�= v:0��� �uO�>�8�ȹS�<Ifh: �[�� f��6�8f��D ����ܹv׋�R!�u����<I��z��a�� �VWQQW�_[t��ۍ������E �1���Y_^����7��/�����6���`u+�X;��t�f��8tf��8u�Y��� ���R��f�Y�e�Ë6�8f��8f`1���8��8f�8<f��8faWP�<I0�� �uOf�M�X_�>�8���\�f��    f��.com�cf��.cbt�Xf��.c32��f��.bss�/	f��.bin� 	f��f��.bs �	f����.0�	� V��fh4 �M^�
��������m���Vh �
� �1�^fh �#�� ���&�>�U����V�>�R�ش� �<I��&�E� ��6�8�� �&�G �t~< v�O����WF�u&�E�<=t�� wX�&�G< w���_�FF��&�E����==ntK==etK==at�==ct��r&�����rf��8���8 É�&�= w1���8Á� ��>�8f��8���7&f�>HdrS�&���8= �=r&�$��&��=r	&f�,f��8&�1f1�&f�&�
�8&���8�p���<I�&��!�u�@��8�f�6�8��	f� �  f)�f��   f�   ��^!�t���f���� ��f�>�8� ���z��<W�>�8��	f1�� �)����f�_f��8f;�8wf��8f1�9�8t�J�A�|��� ����&�>� u&�� ��8��8t��rdf�( � �t���d�$���T� �� �d�  ?�d�>" �t����� ��rd�$��vdf�( �	 ����89�v���d���>�8�� r&�>� 1ɌÎ�f�   ��8u"f�  	 f�f�   f�f��8f�Af�   � �f��f�f�   f�f��f�8f�A�>�8 tdf�f�f��8f�df�f�Afhn�  Q��8 �����؎м��������� Pj �1�9�8t����!��8��8�!�� ��.f�>�8.f�>�8.�6�8��<,t< v��PV�D� ��W�<Kfh� ��_�/ ^X�D�<,t�.f��8.f+�8f�.f��8% �f)�% �f���Ȏ؎�fW�<Kfh: �f_t%V�n��0 �<K�* �y��$ ^� ����f��8þ����<K��z��X��8 ���fho �I�ѵ�s��V���h � ��1��@ f1��f�&�  � ���&� � ��} �� � �&� �t�������,�&�� ^� � �fh ��f����  w����؎�1�j �  �P9�  Qf�j �f�����O�E��f�)��Y�� ����8f�f�CCf�D����`��8�� �  �f�a����f`��͎ݎŉ��d�
 �D��:F�����Љ��F,fa��ϋFf�v(j!Zf_���hs��$��� �3��� �*f����K����hx�1�[1��ގ�f�&��f�� � ��fhg ������<I�#�������e ����ÊF���ÊF�����J �ÎF&�v&�<$t����À>�� u�����ȈF��f�F  SYf�F  SLf�F  INf�F  UXÀ>�� u�� �u�&������Fà����������9����L����f`��͎ݎŉ��+��%r1�����b�������F% �F�F1 �N�^$�F���F Է�Î^$�v�0�Î^$�v� ��h/����h������U�ÎF$�vfh� ��f�F�N�vÎF$�^�v�Nfh� �s1��vf�NËvfho ����F1��R�F�t{�F�N"�Fp{�N �F `{�N$�Fx{�á���F����F�����&������Ru�̀�F��f�h{f�x �d�ÌN$�F�9�ÌN$�F  �F  �����ËF��N$�F���F �ÊF<�� ��8�^$�v����^&�v�<Ifh� ��fh: ������6�8f��8��� �¾ѿ ��y&�E�  �>�R��8�����F��w�t��N�V�LL�NL�u�l���àb� �t�`��F$ 0�F  �F�f�~  uf�Ff�V�F$�^�n�y����Ì^$�F��F�Ã~ u�F �F �N$�F<<��ÌN$�F�����F�����f�~ f�vf�N�VfP�{ � �� �� ���RA)��d��<I� ��� �f�   fX^1һ����f�   f�   f�   �f�> ��L�u�>!uf�8<1�f��f�   ��<I�����9�� ���>�R� �6�8�*O�>�R&� ��j �j3f�   f�>f�  
 1һ���Zf��   f�>f�� �	 �� f� |  f� f1�Yf�|  f�  �fPf1�f1�f�h{f�x �t{�x{��W� 1��^1�f� ff�f��
f)�f�f��f�j�'�� 1��؎��x{W� �_&f�U&f�u&�]�p{�r{&�E&�]XWf�   k�W�f� SPf�1�f�f�_���	 �f�f1�Y���	S�Sf�S��	Sf�&Sf�   f���N�3�0��&V�z����^���Vt`�<t<taþl��x���ј1��؎�f�&��f�� � ������R!��v���f`1�1���3��fa�!�����>�}t
�%�$�������fh: �	tS�x������:r�x��71��G�G@[�fho �t	1�[�SVW�>x��]!�u� �ƃmr�u&�F�u�_^[�K�A�]��f`�����:���]�5!��ut� fh �	�M�5�fa�fa0���P��r���X�SV�x��7fho �����x�^[�WS�>x��]�AC�][_��Z�r<t	<
t	< v��8����ÿ�:���:sW�7�_r�<-s���� ��:fPfQUf1�f��f��1�<-u����<0rSt<9wM�
��<0r% <xt<7w:���0��@ r8�s
f��fì��N� <kt"<mt<gtN!�tf���]fYfX����f��
f��
f��
��<0r<9w,0� <ar<fw,W����*��t+r&��RW�y�_Zr< v1Ҫ��<
t<t �u� B������ �u� ���������ù � ��r�3�s� �<<�@ �f������;��;�`��r<t�t���A��;���m�<tg<tZ<
tf<�� <tM<�<�� s<�+�/��;t/��Rt(��;�>b�	� ���;@:�;w%��;�>b��;��ø1�����;�þz����;t���; ��;@:�;w��;��1ɋ�;�6�;�>�R��믾}��� ��;t�1ɉ�;��;�>�;� ����r/����;t��;��;-���r�r��;t�;���;U���L�!��;��;M��<
t< v�>�L���Ms�G�>�L��
��6�L� ��L��Mfh� �,��t��+	`�>b����;a�$��;���;t-f�f`���!�tP�&���W� t�B� �8�u���X���faf����;t
� �t������f`��u*���!�t"�4<�;2<u���tB�&��� �8������fa���m��uD���!�t�4<�;2<u�W�t�B�&��� �8�u�0�����(��� 2�؊C����4<���<�u0� �t�<<���
.f�6�;�x.f�6�;�p.f�6�;�h.f�6�;�`.f�6 <�X.f�6<�P.f�6<�H.f�6<�@.f�6<�8.f�6<�0.f�6<�(.f�6<� .f�6 <�.f�6$<�.f�6(<�.f�6,<� �PR.������uZX��W� 2��.�>2<.����.�&�����P �8�u���.;>4<t.�>2<X�u�_��f`� �  ��;� �f���� �f��  � f���  f�������� f���������0<�W���怍W����䡈��!�6<��1��!�fa�f`1��؎��0<!�t7�W���怍W1���怡6<�!��桾�;�  � �f���� �f�1��0<fa���f`� 2��f1�.f�2<� 1��f�fa��Ff1��乿�R�
 �f��<<0��Ū����f�$�f�8<�;�R�L��R���S��E� ÿ��H���	�>�Rÿ��9����>�RÀ>�R w���#���ۉ>�Rÿ�����Ӄ�u	�>�-u1��>���@��>�R t	�����À>�R t������fh� ���P��^rf��*�f��f�f��P���^r��P��<Jfh� �fh: �uX�P��<Jfh� �{���uX���R����� Sf1�f�����r1�w���r)fS��r�h���s1ۀ����>���߁�����f[�f��%  _f��K�� f� � f�f�󣂶P��w�狽 �>�����U�����X�����B����怰BB����<u>J�����<�s1����BB�����怨t�O��>�� t��� �������ӷ�������  �P� _fh� ��� �<K �ѹ1���e �ѹ� �< v�����R�ѿ�fh� �G�ۿӋ�R�����/ �`
�P
� �# r f�f%����f=ENDTu�f�f%��� f=EXT u�ÿ W��� ^ÿ�1��
��n s������Ru�>�R tQ��>Ӏ><K t���� �<K�&�E� ��-ӣӹ )�1��f��  f�>8<f�
  fh� � f�>8<þ���	��s ��tlr�<#t� � f�����rW< v� f��0����p�1���~�t=r%�c��H��0 f�f9�t&f�������]	� �W	�G	뢾ն�L	� �F	�6	딭�����<
t��s��f�f`�����f���  �����faf�� �f1��،Љ&8�
8f��f��f���d �m��`�� �"���  � ���؎Ў�����1� �$�"��6�  .�&8f��ڎ����.g��    f�A�  �~�f`.�@L��s un.�&�.��o��$����[ uV�� uO.�������d�s ���`�l ���d�e Q1��0 u*��Y.�����$��Q1�� u��Y.�@Lu������Yfa�QfP�����.f�<L�  �fA�
C.f�<L��&f;LL��fXY�0����t �u���d�t���`��u����f1��0�0Sf�j �z� Q�  �?�G  f�G �  ��f�f  �����E��f�4�  f)�f�U�f   �Y��É���,�DL��faf��.�&DLf�f`��f��  �0�f��.�&DLf��f�6 ��g�fh�  ���f�f�ûƯ��fUf�.�8fhx ���f]pþ1������� � ��r� =6u�<w�1ۊ>��r؀� wӿ ����r���� �>`�� 0���  �����f��b��t��t���b�tH� 0�Ž  �>`�0��t�t 1Ɉ��NL���H��;�!��LL��H��;ù 1Ҹ�0۸�`�� �u���;���̈&�;a��h�u�8 �PL�x���r|f�>PL=�uq�XL�1۹ ��VL�`��H��1�:�;r��;�Ȉƴ1���VL��L  Q��NWW�� f1��f�_�TL�% ^�`QW���l ^� ��ǋ>�L�~ ��LPY���h�1��4 8�t���Iu��1��$ �tQ�و��Y)�w���� ���
 ��Ã�����t������������$�1�AVU� �����Ku��G��w�]^��v�ú���BH�W� �f�_�<v���t�<t@�t
�O� ��� 1������w%� ��c����t�f�LL���+���R 1��f`�Ȏ؎��t� �t�t�O� �� ��t� ��R���fa�f`�_�f`� �>t�u
�	� � �fa�f�f`f��R  ��f��R   ��R1��
 �f1��f!�t}f� �  f�PAMSf1ɱ��R�sf!�u`�uf=PAMSum��rhf�>�R w�f��Rf�>�Rtf=   r�f;�Rs�f��R�f;�Rw�f�Rrf�>�R tf���f;�Rv�f��R�o�f��Rf;�Rvf��Rf=   w8���r= <wr��f��f   ����= 8v� 8f%��  f��
f   f�$�faf��P�� �u�X�fP.f���.f�x�fX��fP�Ȏ؎��X��u%VQ�~��7���
� 6��JIt� �����Y^�f���f+x�f��r	fhO ���fXÀ>������>"�r&f�`{f�d{f��f��f��f���t{����Y�>���t� ��9 t,� ��1 t%� �f��/-Zf�f�g�f�f1��} �f�f�d�(�f�ÿ ��� �f��Vf�f=�/-Zuf1ҹ~ f�f���f��g�uf�f=d�(�^�P��1��8�t �t�Ɓ���r��
����=��v1�X�PVW �uYQ��1��8�t �t#�Ɓ���r����|�Wƹ��)�r�%^��^�NY���΁���s�ވЪ�Ȫ�d����)�1���_^X����f`���} f1�f�f���f�g�f)Ѝ|� �f�D�� �f�fa�fPf���f��tf���f��t�>���t���� �fX��fX�P�� ��XÈ&�Rf`��U�A�������r��U�u��t�˪f���f���� �� f���f���� �� fa�V�� fRfPSjj��f`���� @
&�R�fa�dr^����^�fRfPUf!�us��� �y��r �u��Bf����?f���:t{uJf�6|f�>|f1�f��1ɇ�f��f=�  w)��A�ň֊����&�R� f`�far]fXfZ^�Mu����f�p f���f�p ��  �f���f�p �.f���.�����.f���6�    ���f�.�t�t�i�.��Rtf`��.�>b�faf��P�����
���X�f�f`� �t����faf��f�f`f��� �f�f`f��� �f�f`� f��fP$<
s0�7��fX��faf�����1Ҏڎ�f�&��f�� � ����꾶�������t9��0�R1���� � � `�asMu��$�Z�� � |� �f��Ѽ |� |  ���              j Th   �5��  h0�  �   ���E$1�� v ��  �8  ��  �0�  ���  ���E)t��U.f�΢� 1����� а(���؎а ؋%�  �������%�  ��   `�t$ �J�  ��a���f�UWVSQR����t$(�|$0�   1�1۬<v,�"�   �F�t�D�f��F<sA�t����1���!������Iu�)�)ǊF<s�����������F)
���n<@r4�����W��������F)�9�s5�m�   �F�t�L$1���< rt��t�Hf��W�����)�9�r:�D���������Iu��1ۊF�!��?����ƉǊF�w�����&    ��)����ԁ��   �F�t�L��v <r,��������t߃�f����� �����t+)��z����t& ����W���F)��Z�_���n��������T$(T$,9�w&r+|$0�T$4�:�؃�ZY[^_]ø   ��   �ܸ   ��         SRP���t~9�r.����s�I�ȃ�r��sf��������tf��t�XZ[ÍD�9�w���|��Ɖ���r�INO�ȃ�r"��rf����������������tf�FG�t���1�����s�I�˃�r��sf����������tf���t������T����;�����  ��)�b   ���  ������  ��`�  �R�;�s�K����������Z0Q!�t����f�Bf�B���B�b�B�b �$��f� �ڎ����                  / `�    g � �  ��   �  ��   �  ��   �� ��   �� ��              `{    �7�0 �1 ��  ��3                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                It appears your computer has only 000K of low ("DOS") RAM.
This version of Syslinux needs 000K to boot.  If you get this
message in error, hold down the Ctrl key whilebooting, and I
will take your word for it.
 XT  
SYSLINUX 4.07 2013-07-25 No DEFAULT or UI configuration directive found!
 boot:    Invalid image type for this media type!
 Could not find kernel image:  
Invalid or corrupt kernel image.
 �|�_�c�_�s�v���\�
Loading  .. ready.
 Cannot load a ramdisk with an old kernel image.
 
Could not find ramdisk image:  BOOT_IMAGE=vga=�mem=2�quiet=�initrd=C� ��+�d�\9`9d9h9l9X�^�x9|9�9^��9^��9�9�9^��9�9�9�9�9�9�9�9�9�9�9�9 ��ʓؓ���	� �0�L���_���������ʔДՔ�����H�o���|������������������<�T�����s�I���������������   : attempted DOS system call INT  COMBOOT image too large.
 : not a COM32R image
      	       E          ?  �          i Too large for a bootstrap (need LINUX instead of KERNEL?)
  aborted.
 �;
         Out of memory parsing config file
 Unknown keyword in configuration file:  Missing parameter in configuration file. Keyword:   � �0  o�
A20 gate not responding!
 
Not enough memory to load specified image.
    	
           ERROR: idle with IF=0
                   ��            Booting from local disk...
  Copyright (C) 1994-2013 H. Peter Anvin et al
 
Boot failed: please change disks and press a key to continue.
    �7   ��t�;   �����B�+���9�  ��$^��<K)��YQ� X��   X�@�	�%�+���2 ��+����R�P���+�̴h�  ӟ�6� ӟ��0  ӟ�  ӟe�  ӟ��N ӟ��� ӟR2 ӟG��� ӟ��  8�t:��R�Y�   ��L�h�  G��1��R��2���Rퟩ�Q��Rퟹ^��  n���h  }��H�R�	 �R��6:�R����|���]��R��  <=)��  <>)��  <?)��  <@)��  <A)��  <B)��  <C)��  <D)��  <E)�� <F)��  <F)�� <G)�� <H)����  ��.cbt.bss.bs .com.c32                         �                 "��S  �  ��f�    ��faf��      $hi h �  �5$�  h� ]?s   � E�� j	���� f��������D$��[ ��    �SUVW�5DL  �g�>8T 
8��6gf�X ��ߋt$ 1ɱ󥫸��  ��G�%�  �G�f�f����XI6�
8�|$$���!�u���g�6�x_^][��*��L*`DL)σ����*8D$%D$	$��L ���������f���������
[]^_�á��  �xP �+l��v �� ��uf�=|P  t��Ѕ�t������UWVS���P�TL(P�p �D$j)�P L �	�L$�4$���  v�$b�@ �A;$r��v�5�\$�l$8\ t����vJP
1��L$�J�G��G�]|\6 NJ�2��aw�z��i~��Z��P��� ���f�j��W�x
�_�T)΃�����a����B� x�hJ�P��[^_]�R�XC�p�n �v�*���݊L;��*O��	�,9���u��T��)���=k�w
��y���s�����O��[% 
<�^��N�1���2F9�u��s��K�I&\
	��p��+H�H AX�f�'X; )��	B9�s�\����u�z�m��	
�X�ǋ@@6;� u����2�Ӊ��P#����t�h�pX���S�w��RZYI�X�" �ǉ͡w ��Y��tU�щ��Ӊ�]�Q���HG����xC%��@F�p�k����HIK	��F	�
�`R��QK��1҉��#�_��T�؜
�P���H�W ��P@ȹ_{ �bSS��n���J ��t{���\a � OY��P�X&�&��ۋC�x5Q�\iu%k�@ �DF�@�o�B ]�T��W
 ��
��H t�|�/t�/@=ov�x @ �H���$D�W  1���l[Ð��rx"�Hk���VR�zW�0N1�q(Y ��=4^�	��F�k��� �%�'�<I��9U#J� �@rB���t< v����@Y �\�l�~$j�x|$V1x\ �h�׋@!�UCf] '��N���T��0�Vc|��W �`F�9DE�x]]�l	1ɺ�� �AK\Q�A$A+�x F
) �T� �<$9�v�$�>�$D$�N��T$#R����H�WZ����)X	Iw#�j��Of�CM����@ �]\MLv� �!�IM�@X��NVX% k�{�C(%*���	��C(��$�YLw�^1��%���@�y@9�s�K��$NK�V�`�l�֍AX�*``CDT�p�@`��Is@TX��j��y �@u�Kt�DA�g�OcR�h1H�[�U  X�Y �P$1�Ch�^s�MKEX�@t3S(��ʉ	[	�	�Q9���T&XF@]  pMC�2N,w�8Y=K��SQD$P��G5��Y� uU�6P	�3�{ Zx�h�h4[�:Y
 ���A�Kʍ]�Q\A�X(���)�^�S��
fa�K,��8��* a���	^�Y����P�p�$�: t���$��pL[u��Et����<$ �F`��B�	�u|U|N��S[�xU
V��_A�2^PL�W�����p �Fp�Zo|Y�݀} /�Eu	�ý�uO�/r�TI�}m�C; u�C�</t���������!�zuV%|� 9�Z�@h�C ��p����S���'aa��ɀu�n���_�EI
)H
���� ����Q,W\eD���
�tN���C��n�wJ"]DG�G��
��dw�F]8D4�R  �D�,�z0 tk�L$te=T� ^��Bۉ�US�(P��U0��~:�F$�;�/H	����R���`@��_�CQSs߉t!�!��iRBfC�;\1��H
��tL����ZRG�����t&A>�|�@h��ǁ�xH��i������W���V�L
PH�	�݉��h	Ѓ����p@�l��e�n�y�^�C$x�K(@�%f�C3!@T@�C$�c(�[�����T�����[���
x>
؁�Ik����ɋQq�C���aHk��R�Z ��U���l΄ux����]!�#�Jk����Y���IK$ViRS t�e��'����w��H��x�P���PY 	Gl�x!-,fA�

hPK�Xb�z�4KG/1�#�1dt�c�I�3)�Lb �/
�u% *Q�	���}$U�D$PWV�D$�OU �s�q�v�t �$�R��Lb\�yM���u��Z���x N�6FHj�P(��t��ң,x @�0^ �S f��RX� ��J�" )x_a�`D��h�f�+C^�&-��L����'% |'% x'% tT n��}��E���'% �'% �'% �U ��'� �y(E @�/�\e��
-`0 ������dI�~��L�:!3�����v�H"0�y����Mu(| ��,$�9�u����L���	��i�Q�JLY	�!������pǊ:�K	�H	 XZe�@A�J�˃�Ku:�X��H	 
�<09�u+�����	ىH�J�Z�Y]JW�H$R<B[�-\U���7PS!2 �Pу�Q�r��4�S�,Tx�9�r�@RH@	ZV�BN	��X�
9�r	�R9�u���#t!1ۉ����ƍ"FLVu
�8u��LP�9�u�C��u�O���	�xy���,�P/^�~!�"��L) 9�ro�P 9�rI��{��D')�	�r��'sW	ƉO�Z	*z?WP�!�%	-mPW �P/�K�S��SZ���[9��zS%1��"�,�(��1��B\��~I�3y'9 $�Q�jw���|u ��\t��/u�U S���  /t�AEO�w�]��� wՍ19�u���� ��)΀y�/u�Q�9�u�W���AHM�X���XK�@[�C'�
"P(�xO��
4��tv���� �텟d�	���ՋK�����T���!�!� "x>A��H9�u"�<(�����")N�Hg��A�<��%M��
C�����<�!�L��1�MKl�8�#���)q .Q�%lt��X�NՋ"�"� �N$�L$��N(�F�Vt�M�Y:�x1���D�DD$9��S�Cd
h�@	������ t���!20Cl
p9�w-;Tr'w;G
r+U D0� �x�
�{X lh�G�;FrHN�����t[O
s�M��B�����ѽpr
��O����>UT�CH�SL�kTYQ�GG9��
��F�TH$r�i�Sd�Ch���R��(El	pt[G���,��%�6E��VJ�s1{Pc@��U��E�t	 9}�wr9�s�A����t +��!��x�E�U�)���EЉUԃ��� �E�U�C,��E؉U܋U�#S,�E�#E�	�tB	�=ЋUԊM�-�P�E��'
@N1�L%M�;Ks��_���&5%44R�
_�HV2V�
#.3蓝�d]N��H�f��4^x��AH�L�]@D�u��Kd�{h u9�s]=\2`��lp�2Er�跆;��L�A9�r�s�0�
�CpY4X�#�8����Z�#]�RiW��#~9�?B<`�R��!W()\ �| �" R #�Q !�9�hI���uJ:�dB�<���tW����H�è@�Wt%T�#��?���rS�
t���$*W�G^�:S�SA:W�IDK��k����x��M�&�!I*+P!�3%�EPf�
��t�ٍ4�4xWf9�
u�V�f9�pl[f���V�@�B��D� u݃���f?�!�>%��@��F�={���`�s ��"�a|Z$t+ 1����������B��u�Y#I� �0��~ 1�	�� t�Gt��pkR@Tu� t'� .@�`)� ,� �LJ��!=Ny6f6 �8	�L$�� �E �\:!�@8t�^NSlFJ�h"@0уCd�Sh �v	�,x(���XD�=E.ǄF@����]���d$띍N�W���G	r��E|O�B�A�BAF���
��M�f�P
p�o�OEP�H"LJlf&�0����k�"�-uh�~h�R �,"IP �K�Q �I�HX����u��!�PHU�"�-I�H:Xp\�X`�@�uñt(@Ao�*�BW�Z`J��Wl��������#�N@�		�UH �8.u%�@��t
<.u�z u�tNU$!�5L	)��OQx1!2;Ah�S  v<.5��D @��~��l@
�ي�pj ���uK��D
~���
~�j �@R1yw�t|Ҙ0����;VM�7�7�p �-S�~�!=?D�F�<]z�n�V�Ez^
8
���H�@t*�V�T$��?UL_� ��}D$ ��D8F���t	I	JA�o}T$ C}��!�3�xTt1�_f�
\J"�C/�9A���w;�?zxt�nG�eM\)h	��uŀ9 �	f��AuFN�k�E�	�7!);(�/���j�ڍu�:L!�+A(\@k�� �^�%YNťf!�?�PjFG��b	�D�R��\	�XR��/h6MXOR �S�P
��S�i KʉPX�ҋUu�r �R\�[�U[Mq��t[U�[��Us 
�Ή���	�u�r�z��������J���� �1�rz�pl�xp�p\�x`�S-�!�*�hrdd�r���$7*��tf"�_�Fp�OO��K�W�Wj jL q�,!�JS!JRfM'*RM���,I�J�8b���U(Ɗ$q�$E5E,S �G"I:2|,ME-@d��l$/f��u�l$<i*IA]%�W|���V"#<,�d5MV�Y�A|tJN��VN\$-!"G� K	����RO`i
���F �$���� �i�R]&�+VN| )�؉^$�WډV(�P��V,L	!J'F0�1�+B��-)�=�  w	�F4b�]���[M@M1 X�v�x PD��t����Y� UH!�#��L�1�$\HN�^�n�W�G�~RG#G'���@��!�N��!}2�A�v�u�&�#����f`, ˃�!	"�"�e�;���!R��?oA�/H&	u��r URSh]i@ ��HP�@%aYIL$a���"�)@t,�fO:�LO;ʸ!�,�3�0@u"�MJ�#�5��.!�O�d"Ej�Q�!k��x%�k�PY�&�K�����\%LU�~�!�&!P^	(�\$$�5���E�!�V��|ɈA �у� }�^�u
G,�1@��9�|ǝ#�1'�L!�kX'H�9�wr9�wE!�,�sR�	�qt['�- <�E��U��EԉU؍E�P�5t�@qhn �MԺrY�lN�3n �\i	�E���}� uD
���@�M�I��h $��Q�E��UĉƉ�qy9}�w�r9u�sˋE��U�+E�U�AQ�e����c@�=&'9��bD� ��k!D��[��EX\WV\i�/I  ZY1�#XIt�{ uE#�+!�J �����1a�]T�7�C�P\�@XQ1"D��t!����SQ��Hb
)�]!O�#�S�<U��.{W�Ð#Q"/!�HDxNf�  �J����m�h�!W.��!=I�$'H�|�zR+��ٓ-����,tX�y=`uhdS\�b0" K?��������J��h�o�9ʋ5b��!�C��f@�i
[�\]�x
V
�TD�wCrH9�w=Er<#| �Z8Xw2r-�H	�X�B	�RCKrILGrKL�!I2
�Y����%`b+�r$M�*�1� �@['֋ "�SX�M1,l�LedCU���uA=l `@70�G  ]Z��/a !�QY[�щ��2��@�$)�Q�0[
;�,vIC,i(��!Z&�:aS)EG�LxQ�(N
0^
u�u�+D*�~��LBHX։ϋ�$(q�
e�{L�d�_�Ch[Y�eMl ]� #.U���AY�tY߿nq�|!�L�e"RP�dbOЃ�e!�;RP!�3�����D��$�c�$�d@T�@�t� �|�L�QR�t�`h� Gv�$DJ�!X!6�~PC�m E#d	�T$t;D�`~H�/��Ok�!�o��[ U�����"�N��D��y� �R������_@�u
}Y#
�u,�)���l=��E]Th4Ѝ�w��eAw�p	��#Bf�zH1�-�L�WV�@1Ҭd�E�#��M�w�؁�ù@Ę@!JyNr�n	AUWtW!*.l!8$D?H$8GD�!�e�MWA�L8W'�<T ER�RZYGhzO��S�2"\x#�_�$�k�$�{ �$�{ �$�A�)H "#�$��Y �	
�pth�b��+HhP�# I^P Y�y�!�)M�(D�,��z��a��� �׋C�D��$���3YZ!�.��H�fl(�&XH@-6#CT9���O���1p #XJsX�{\"�)��-g�y@�|���t"�q`F�9�}�q`QR��I�_@p^_0��$$�xE�Έ �L�@��t1�T�`B9�|C��u�� �@�D�\x�ދL�VW�J	XZY�������m>�!�/("TPU-U�=T�F�QQ�>F>��e>|
W+���IrYu�UV�o8��XCY�NM/�fFE�eZ�C!_T�$�rA"�j!m
RCI�ne�5Nl����D %gN�İ,	�xM��]Y�N&�,] �T�QS3NV�
yU*j~��F[Z|V1��½RɡRI����"z=��$@�tΉxn�Ctz % �  ���C�����uvml.L^��\0.X��h�p���Ωaҩa�vuH"!$�zT~Qj�t\����CX�S\a~��%�`�1���L�(À=�{�XXF�'9�&��'9tYA�	}�h)�A���xA!m\���!�7�A D��CC��~P0m���$"�y���|D�{���4$�{�oL$M�E	�#�rt��y)Q س�h�f��'!*"���pI(�p| �+�UP-����-e�-iY �n3�l3Y[�J*"����oB��]Y��EGR�u�+]�",�'$��|UD;\i3Ћ3�=�X!�4�=�@vhrJ�&!� j
 ,��1�4V=�(�������l�I�����)*N ���b�鐥c����EU͵Ѵe� U���"u!(U�,	�,U0#�B;R���;���Y_%�h�)e ��?�)Є)��#:dp�"-S\�������WV`�!�|>\Z��DH2\ ,b$DZ'�\#�F��$�+#'51۾T�Tm�h�k�� @po,�B;=xr��N;5{
��L!v-+|�Y)m����=*S��d�|$Muu9t$Iuo���8P?H$Y��1wcuX�p<A9U	!C���!".�	8�7t�!W�er- �!\*9T$av"�`W�@Z�H]aE�e%�'A��'�+|!)�i !� !�D8!bjʾ��!�l ���ځ�x;��1�Nu��x�A��dTuՋO�K'kES� ]{T�C"���n��PZY:wT�(���f�0�z1��Y��qO(���X H���ta��tW��xT ��G�Wl�#>�G;?U#�]GCGUU!���AK�	g�q5�UkH�Z ���E%Eh )���"�U`}+�Bn�/j���|��1Ӊ�$ P��3��#!Ms�p-^��(�+�C�A�^A!Yf���h�I�T�$�K'p'͡0#�o	T$D�Z����ZG�>�489�w�> u��^�9D4��u��[��!��L$���
z<�N��@"]!�b�!�e�W ,1�-��I"&�"�I!ܠ"0������|D�l$(�<1ω|$����F dLT�!3(r�K�P!����!1g�!=9�"�GJsZ#aJ"���h��8 x1�1��"�6�NF'��(�MA|5"��	�[	N�C	�<0��JZ�J"�|�	�P"J�U �"�._kK'�p0)�Ye "Xv!�L^PHX �{t ue�����{ɉ$#N�N$oH�#	s,tI!/�v�^C"P%twCT��zkx!�G��t!�W�|����T "��~Exc�N)�E�U?��n��{
�N%,� �I
u
},hY;$F.��M�������1osT�fvCxF\M�E\-�	&�RSH�KL'�)�,#�r(��E	L!�3!�?U!!�)_-�M"�tZ�!��DL�܅	�|$D w9\$@v#�p�%0b\$H��K�9#%����	�u-LjT��V�-�z&�<�!7!e"_"�I&�9#Hx�L$D9�r6wd@9�r,�3Q@P(��*  �\$D���$�h`!"2��$u:@l|�E$ �%�&��4"�Op
@
Af j_�`"�5!=%)P�L$���RlBU_T$xQ9�rYX�]59!�N'L%�bK%�"�$��\��YZ$�q}tW|$.��`Q��GA�;H!6G
;R&rh6GL�!��X4P t�XP�3�{U-Dl ��4"\Ek4h"�,)0"�h��x�*�_$&�_i<H"�_"Hh"��L�I%�%I�&I�'M�*M�PHI4H"֩��P ��G���)��"=bM��\$T��y&��P�]�t��N��!�y눡!����Í�T$$P}���]�;b�H�$�g[
�YC
�4�H� �t�H��x%}�x)�J��H-"�f�P1yrz��]uV
ؙ`A!���QIX~�HL�L
����M��u|[hE!"��XA�%IX�s4|$H-d@-A -g0�x`m"	p�M ��XDI
<I
@,pr+�@K  wr���w�p!�o�@Q��	!xd
�@5�@6 �@7�7R�Un\{��#�3p�3�'$�25F_�P #�:)(% ,�
��INDXt��FILEu,�Z�f�;f�r��L
�1�N�Bf99uf�,Sf�)f9�u�)�DD�P\Uu#??�Hi���!�|�Q �5L~���X)",�#�O�AybA�2���!XeJr��!�e��HnNAQ"�`<A
@!�SՈ�����*�!�-N_4����1�+AyD�M
!�yv},M}0��FP� ��&X0R'<PNo8RF4PR 0PEyl Y(#l�� !_&��C`h�b�%�&��]�#'v�FB�菶��8�,`�	9P,u�|$ tr[
�9!"��jI4U8j�~�!�]9�}LE�\
r*!~X�r"E�,ؖ�"�!	���� +8h�UF�l�lh�_ 0�#)�$/D)q)�E3*�h5�7Ptqo�
)����zB��(	�B��As\�Cr��U7O(�8Y	<"�Ws��
�5�!I�O_7����	�+Yj"�($Y7wy(�x-X��Y
 L"!{8z74R�7Q ,y7 l #uh�!fHc��7�7%#+k�!,:I7�j7G
��!.�} �6y5�5��q�gE0XWF4�L�9�&DDr.w94$r'U(�5�b��j� �#��x'��QG-,�m�+@'�Pm��zP��  $H/9�uJ1ɀ{QH��8�|KR�9�u3"�/��(��W���w�� z�j	�z� E	gذ%��(��p�U��υ�t��Bu��`T�!���D�����@J�� m
;U�u�>|��@�߉e��K1�#E��������)ĉe��EІ%E�z �~!��)N�"p�	���U�9��|Q�9�r�h�H8!�/F��%���E��v"q	�p	�F {��U]�TP�M��U��E��V���"�Mh�tA  ^1��b#�% 	�t�E�t�딨u��t��E��U�$'o�E���y �#>YE�	�	�	���U��"�mH)�,�&@%"�+�`�����EȉU��E���x �U�RE�
�E�!�_�	 �3��!�8���[
�[�-|}M��F0���(t\'��
!��,`%���RPU3�h��!�[YY1U�H;U��W
��`�E�;E��F��` q�G,1�9Qu9�t�{�MЉ�"��7##�h�a-�!F�X����"��!���^ �P &�s$8E"�hP�9�u��bp�u��p
Z�PD#xY�V��lLJ���}0"0�N���vF'�	��a^!5.h!3A��S'����h�eF^ǐ�;2!�(��z��v ��$UVQ[h��Q�dNP� x!6y!�`�!|��D�G�{1Ҁ!���#8jW�Bt)�G#/*�@U�~1�@$VM@� y ���JщO"|�ZP��������\JR���SA;�or싞 Ƅ� ��x ��$t���.�wu7p!�A
J-���nN��`	"jX�#Z�x[t
h�|"ŵ��,0���n��m
�e!�����
�T �v��S�V���.��A���ip'BV��y�	R��f
��e���x�{
h(sMO���DB{��u�!���!TLq��t u����C�^th�8�A�Q;��t* w;��g�A�3A�3�A*n��f��~��u �pd��4�I%-N.@ /J���)�W ǅ��$ǅ����QD��P��P��k/����:��0|_V:S�����!"�"����xj�;#�(hHZ(��W[��h��1�o��	'��� �rQ
�C�5���z5};���a�)� A�<�J��r��p\9��dV��d�d5�F-��L��L�8'��CS�C�g�9kʃ�h!4vd4�@! �o
��W�JP���f�LBR��ff@;�r�Ƅ�i�z <$	�I
<Aj��>�"�}Ry�����#:.�h[�v!}��m��	G	}A!�{!JjA����v��^~!�՞�D�]��aqN!�kf�@!��f!J��b���f�B
�K��"���c�$�yz�l�hbj:B&�OBhs^���U#�Ջ8!I�^t!/%�R��!v�tj!�f�_+Vu��t�"�����Q���$Fn0��qu���!u�"d\L���F"V$N���V$!+����L!�G�_)�*8����"�$�%$��x"hfl##<�P�f�n�uh"#,f�B!2�El��%&��-zIE|�@�b��%�)�@AEz]	�"$����P�=[h� ^�xa �b�QU-��!�,�q��}
0iC�e��l�
�C�Et��Ep�{L�!M�CG�	x!f���mS�"�5!�VܦV9�(�eM L"
uExc�4$!2,PX�"�"�p�]���^#��#�#`@�4!���!�#]!�#Ÿs�̏�
��zE%`ъ.�d	ǋ4$�}x uT	�	�|� �B�| &��X!#G �lDM�
h�q!|uqCuE#�E$q�ʑTT��ʊg�FQPM��!����K�x^[�ih�����F���!9��mE~��8+�+l��!&! � �����������u��},�*��s%� ��V�E�(�	�D��u��M��4�&� �#	-xuǍO�w�;u��"�
�GȍV9����V	��u�Tf�FT2 ��E��M�������	51�F�뱨I�y*j(-����D!�X���n^$�~(=a~	��;�)&-,'�)&%-�O!�E�$$-
��U��E�����_u0�'�,#�,��DII�&�,"�-�,Bp uЋ}ԉu��}��u��}�u�L�u"lN.�, -$�.ȭ̘auЉ}ԍ}�W\�!-�E�'%-�'�V$=�-%-![�CW��HUu��>��
���x }������E�p;u��吟WB�:� *Y�U�uu�:��f:uf�9��	��5�.L Ew^%�.}�;}	�b�~)�.z��m���~�#��W�@��!ؿYBǀ|"w��'!C��I�#�s!��f���<F�m	2e����S_���%��.�\p�"ȫlgP�uht^�p�"��e�p�V��gh6muOX顔(D�ЋK�P�Q5�	 6�xu'�@	A)P&%�L	���u�~,u
��5#Ȑp���(&A�%��!Z+�Y�|�����v{��j������"!/�N��J
1�A�#��Ð!=3j	H	"��X�#��k$\�M��$X�`M����;ps^1���|� uN#sƋ��C�G�F��!n��V!|>!5�w�0!��TNN��G�,H&\�Dfy%�b)a� "�gPOs@�$9�w\P{4 t)Ѱ���9;Cu8�SX��VB�\.��;4$v�,#�]�y��"{)�]�\)���u�(�s(X�o�B�D:!�Gq:֋QNgr�hbm@qL�!Ʃ鬓6�q!�"Q!B�X"T%	
  �����p4!9[�]1A	U	�²�	t�
�r�u�b�<q8�y�%i�N	Zf!+���"�"�BC G��C(!hB!6��F!��, 0h4�V(�CX�
�#�����m�'e�$#?M֋v���$0lK�$��1��.&���eT��FM��#a]#8e	��+n9�v���o�E�X �B�\$$[��+L;�w7�; u	 !�� �C9Ru� v"�O�hHB_��y: "b㵃O�T@D8;~�"��![�h$��'#`-��#�> T%4!�cm �H!)W#���|$8S��"\3$
"�'z÷t&y�fZ�Mn	C�!-G�uDKU^!�J�`%#���
T8#6���L�{��"X�"Y�("��Q$�x�":aC!����$"@�w
fǄ� Ih���F���o"�H+p6!�ӉFa9	"e�X!$�CP�ak1�JQ#=K!	]!�ֺ#�.��&��|%V'Ð&�"�}suM܋�
r}�V߃�|M쿊��H"����!�(�!r��  
�M�1�1��O��M��8�M���u�}� tn|��E�8�a�d�cu܊��#u؋��M�M�T	���u���)�4���( �����Ǎ���9�"����	@�9�u�����Ea�"y�+ &�E��?�}��@2��q4�!w��XR�"N�U�y 38
�ucf�x �xtQ�X�]�1��k��M�;LsJ���u
�:B;U�|���k���_�]��E��W@
U�M�]����N��H�1��h�k�;te
I|	�A9�|���h%Z��O^�AT k��+1�y#�p9��.$�R!r"I��Ӄ}� t)��E�8`�"A@�#@�h �X���p�u�� wS��wN#��)э��]��|X�D�Xw	�Ņ��"�E!���[�_�t
�]��@B�9�u���P*
σ�����]��E�l
�� w9�sf-��w�u�jn`�J��@e��+M�]�X2��e�Eu���
�(�Ή�+u�}�mH�d9�s~���
�(S�Y[�&*�9U��p+p��v���Mʚ��
C$P�˸`��	�u�CH#ƔCLz �-c��!�	�K"��p
���!�)��CT1�_%���*��}U��K���̖!��[ P��� ��O~�`��>`!��lv",�Gڃ�
!I!a��\��� ��X Y�Y �"��[�[!Z@�C������2�L""W�͉�$����Z��"$�\�(���	�"�`UH�RP�ˮ#�3q�&H�$C���"<�$~�@%�O�pF�)�!>#��HPJ��9�Q��L|!ʆ�a��	�S"��SD9�r�{8�sH#��
�KD�49�rY�@	dDx6_B�)�])�KD!�7�S<Dur���w&�8	g<'m�S"�h�L6!%q�l��{T �s@t�09SPt	E�!��Q8I�To�sPP!~��6|\�!6h�zuD!>�CTh�]F!HP�LE(1Y�	%9N+uL�$u"�n}D"�loM1�Z����X���X��	u?u�1���	_!j !p�X"�$�P(K�s8C�	,L s@)sD)�u�i�;�vPWS>A"&�@ !�e#��@�&��$-%�L:��f�xŚ��_�W(hs	 J$��o��'�t��f�C�Љ�"��X4�AJk�"�F���lA� �4Y�$!�]p�$ɢ@�"�}A!%K�B�����{9�|�vًPdL@
"�)EJ!\.�%�[d!�0�^Z�x!�* 9Ku9t��@9�|�^E�E8!!6'�Bp`@"�&� Xs
 ^$T�ba��j��c�9xk
0t#���S�E�!��-^���Q
*^���#��"t� ��$�B!��*�M"�{�u �}$�E#'�$�<�$"�O"���E!?���
|]�"r!�S�}x��#>��!`�%��Q��!� �[��UQXZ H���'$�( )] �^�l#�t Hy�O���$��ƙ�!Q�!|�!�$ W v	Rd�~
�Mq�#$#\S^ utdqf+"�x\#��"rA9�S^�9�W �9�V �;!QT�
+�"
�t#MxlJ"�s��!�!!�PQIMQU�"��P@	�^L�D!9�I!���"��D e0R�Gw2�X#"��XS�,�e�!�*�$��t[Nu���t
d"ޠ��knB�NP���FL!�$(#�x�$�pԹ P"=��bhVy��! 8L#!e� -Mޅ�]+!��{	tP�#���PHyv��4$!��)��&K���!JZd��
$,�dL)���`N#��ANԣN�NcN�FiMUE0(�t�E�BKU�f)�L�$��WS'T$6�)<�L�~��9}V�N*�#��$"�D+�	�MHM�l$���\LQCQC�'r���/��Ё�Dw
����O@
�O�I�gHtE*@+�HdH#5X46�A[��#��#C�f�x"&<N@U�,
Ph[f�Rd����Tb$XT II\II0�I��It2!�l�|B$u�1ɍ��&��V��UK"�Qty��M0PLHl6�!Lt+F V$�����p�I�@e@�
9�u�F(�T �|�U�UI̵T��T��T�vTF�" �['�$UstI)�!�]Lh@�V,$EМ�?��
]UнU]UнU|UD"�#��U$��"��T��vj P�����L$��hn
����d$�RPS��V"�7(k�\��]���^]~Q	xe<IL|(;��B���A[ QI��G���"��ţ�\ "R�y5!y�)"y`0Q:�5�P��D$Xu~4M@�UfP��rAf[Z�UN,,����dNW�HU�� �PIE��g\IXQy J�
H'
�p,eU�t��N�L\U u���	f��Iw�Je4��!�8{� |=�v��P����Ch�� �	[w��?�1ҁ�B\5�^��|'����\ Y�p!�$t	�v)=�U �w#�b&��Q �jT��VR5WI�H!U�!`�C�hg��\��T"|�H�Q]Q� |n ��!F/��_��W  �E�dPEZ�l|�EFBa/O/�:/B/Z/�#/dQ��4VWP"������s�I�ȃ�rSf�!E4��n�tf��t�X_^_>WS^��4�6
	н��}��}����`X D�X[_����s�:FB)�u9�u�1�^�!v�B9  u�)�Ð�
�B��t@��}V- 1Ɋ�A��u�^�f��@@�8�u��1�'=1!,�!X@ ���0�L$���<2F)�u	M!;Ou�!!�6S�!�1���!\`RpP#�H*�G� Z[(��h��
u�TQ\T#��t$|#��L"�1�Uk %��*�K&�K�X����@!H9��������DU
M �!�4?M N <%��$A49J�sHW�G"į"6R�Dx	� <��@TP��+���o
ᐰN� �), m �-= ��a)] �N��� �֟ �Ο  �ƞ �"�"�xЉ���	wk	1

S�B#�"�'<*�>Q�V/��R�߀��k.�
  #,]&ҵ�e,cL$ Ac �I��l!�K6!+� ����J�)| lt:<ht+<jt<L�<tH*F;<z�| qu+�x4#S�H�U��`V��A�{����o~#�S���}|G��<n!��  )<c��H><PtR<X�Z��T<dtk<i�
@�a<s��`<ot<p��@�%<u��wx�	X�q�qI�f���l�Q0�!��&��V+��'��@�|TPt3	`�u�ct2x t8��(��s	�.���DW5�����#��(��
e�w� ���//+�5P���*����1�&��-��#���T&��N4(9S�s+$��$����L$D!�=��!h:.��\ MPDB��"�dt�,y�"H+U Am�pT�$��!fΉ��&0�A�0n �N6YYIH#-G�Mx B�� L8t��uOA;B}xK||�eIt`"ӱ<��f:t!�Y����D	<�A���|$<�Ta4�gW���}	�A,M8!d=VuBZ,toHu1Q,V~d"54,X!�<;P'W  @!��u�xJ	@��8K@�#g�T$@��t�*-�$!`��+�	(H ��+q&�0@�JW#$sXDɃ� ��X�@��HHu%xD@~�(� BMx@�@�t0!�5T#)�HD"�"}�4]7X!�-�Q\�~�S�I�(B4H]8L "ʹ$O	8sD�4�G�_mI`aOU`'� |L^s,AA\l '�F��c^!ZYPP�s�G�! �3� ;V�Y_�^Q`A4T#��QL�AH����;F`sXD� q�D!��uI
v��K@_ H)�X%,���#95gHj�O!�&g�LV�k�!W]��!|8"�c�������IY�~V~C �t�W~M wf�uEuK%���0V!q�)"��m(L$0DYbu�#�#bG)�O�L�U(��@Gu��$P��L~��dx� B@
"�Eu�v��'�AD�(�(��<��D�"�1�J&1���yvof�:Ed#��j�霨P�
���'� �:�nQ��'�_�lv�"�a#\8n!�Bp&A L���3h�M&L�sgGL�����t�#A��h�TOL�L�2��1L���Q���'do��9�(�5ATt�D�`���h&lI!�$�H�À  ����Q���`1��׉����_�Q菑S��M�oM�ȉ�Kܨ"�z@_!�[���}f�Z�RQR!�#P��"mH�A�$S�6��L[}j �w�7�t%�e�[�mV&�fEQ!De"�iU��}"�`h&%�e	�u#� "�_�|9 U��M�U�M�u��}�u�}�}� y�z�H�9	wr�M�9M�w"�a}�)u�}�E�U�����u��}�	���X}�u��}� t�u�@�M܉1�yE0$�_�!G,�7 z���Q� �'!w��U�� P$!r�!JU��P �� � @���M �N |i�� "=xi&	!�� m X �� )N O DM 
N� ���N .q�l�	|Q� x� ^n!���+�!��r�:,� B�T\,� �'M- �* �%\N�]t�3��A4� �G �D�\<i/!�cu�L,�.� K N �I N ,P�xudqxt|xI|U"�$Գ�X��Q 6   N	
 !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`8|  s{|}~���A�A��EEEIII�����O�OUUY�������AIOU��������������������������������������������������������������������������������������������  � abcdefghijklmnopqrstuvwxyz�8| � �������������������������������������� ���?�}�1�WE ]GMGMI	]F_G !�Q � @                ! " # $ % & ' ( ) * + , - . / 0 1 2 3 4 5 6 7 8 9 : ;L|  u= > ? @ A B C D E F G H I J K L M N O P Q R S T U V W X Y Z [ \ ] ^ _ ` a b c d e f g h i j k l m n o p q r s t u v w x y z { | } ~  � � � � � � � � � � � � � � � � � � � � � � � � � � � � � � � �� � � � � � � � � #� � � � � � �%�%�%%$%a%b%V%U%c%Q%W%]%\%[%%%4%,%% %<%^%_%Z%T%i%f%`%P%l%g%h%d%e%Y%X%R%S%k%j%%%�%�%�%�%�%�� ����� �����"��)"a"� e"d" #!#� H"� "� " � �%�  a� �*� �(��W9� �M=�T=
� � � � � � �MB�MC�E@�T>� � � x�EF�]?�\?�� � � �U?� T��_?��T?
�������_?�� �(<��h�(L ��X8 ERROR: No configuration file found
 .. \valid�system�!ino  ructure Out of memory: can't allocate�Pr %s
 fat_sb_info)	vX /boot/Qlu�ext�.e �.cf�%sf  t my	h&k iPEbfs: search Ven	#darr!!'� � c	'p	d�,{noty#t]e.� compress9� nDubvol'�w	"ngonly support sHT+device �
 _BHRfS_M� MSWIN4.0�1tfs1NTFS B  ut8_* E{ whi8rCdZ f	mHche.
t<attribut�?Qp*se_m_n()�MFTIc	d'L1T UW!  ?! $INDEX_ALLOCATION istBYlD B(idX2@*�hp�5Qs�LI�QQ
X�EIex l/�VCrVt ic. A
�rty	l	�k..L�'o!dirQt|S(El	)t*P~Kpp�'�`gNd o`, a���in�_�d_Rtupw(Cou�ZetBS$V�ume)!+� R v��='�!�c2_g_gup_descbMnk� >= �s_cHt - *u =�d,,� h�
0t	z m��h:Rm's�a EXT2/3/4*�Pl��,�pl^f*��'�thDUight�Bgriy+ �W CHS: �,%04%s^|ctxllu (%u/� _-EDD9� 
 (�ll)+-� H�� 3!�18N �p%1NPq�                                                                                                                                                                                                                                                                                                                                                                                          GCC: (GNU) 5.3.0                ,             �@     *                           �                        <            @            �*@                            <    w       P@     Y      �@     b                      ,    �       �@     �                      ,    �       �@     �                      ,    �,       @     x                      ,    T5       �#@                                :                           �:                       ,    *;       �%@     `                      ,    $B       �&@     �                       ,    �F       �'@     �                       ,    �I       �(@     �                      <    0N       @            +@                                        �@     @     ../sysdeps/x86_64/start.S /glibc-tmp-4da84b6e011d91753dd26471d5e4a31b/glibc-2.23/csu GNU AS 2.26 �z       g     ,   \   �       �  �  �      int          x   	 +@     G    r    R   �       ../sysdeps/x86_64/crti.S /glibc-tmp-4da84b6e011d91753dd26471d5e4a31b/glibc-2.23/csu GNU AS 2.26 �e   d   �  �  H  p           �   �  �4   �  int �       �  �        }  |4   b  }P     ~P   �  4   a  �P     �4     �e   p  �e   �  �;     �  �e   �  �e   �  �e   �  �e   �  �e         X�   �  b�   �  m�   �	  �;   �  xm  �  z�    u  {   �    N  �.<    0l    x  5�   ^  =�   '  >�   6  @w   �  A�      C;   $�  El   (J  J�   0�  N�   8,  P�   @�  [H  HE  \H  X;  ]H  hM  j<  x 	  L  
�    R    O  74     we   �  0x  �  �	��  �  	�;    '  	�  x  	�  z  	�  �  	�   �  	�  (�  	�  0�  	�  8�  	�  @�  	   H0  	  P�  	  XD  	-  `4  	3  h�  	;   pB  	;   t�  	�   x�  	I   ��  	W   �X  	9  �  	I  ��  	!�   ��  	)�   ��  	*�   ��  	+�   ��  	,�   ��  	.)   �W  	/;   ��  	1O  � �  	�=  	�-  j  	�-   �  	�3  %  	�;    �  x  	  I  
�     �  	  _  
�    e  �  �  
W  �  `9  �  P    �  P   S  ;   �  	;   8  
;   j  L  r  ;    �  L  (�  L  0�  P   8�  L  @�  ;   HC  ;   L!  ;   P�  L  X   P   \  �     �   $  P   �     �  �  �  �   die 1P@     (       ��  msg 1L      n@     ~  �  T	(+@     R�U x@     �  U1  �  7x@     :       �p  msg 7L  L   �@     �  �@     �  �@     ~  \  T	$+@     Rs  �@     �  U1  	  @2  �@     q       �J  fd @;   �   buf @�   �   	  @)     �  @  =  s  B  s  rv C2  �  �  D2  �  �@     �  "  U~ T| Qs R}  �@     �  @     �  	@     �     y;   #@            ��  pp yb  )  buf y�   b  y  y)   �  �  zm  �  �  |  6@     p  U�UT�TQ�Q  �  [2  8@     q       ��  fd [;     buf [_  Y  	  [)   �  �  [  �  s  ]L  �  rv ^2  4  �  _2  j  d@     �  �  U~ T| Qs R}  {@     �  �@     �  �@     �   �  �;   �@     b      ��  4  �;   �  �  ��  �    ��  	@�`     �  �;   :  st �{  ����  �;   �  �  �L  �  /  �  ����  �;   N  mtc ��  q  mtp ��  �  fs ��  <  s �m  �  �  ��  �  �  ��  ,  b  �=  b  r  �;   �  �  �L  	  b  �;   /	  d  �;   R	  i �;   u	  @   
  �@     �  �@     �  F
  T1Qv R|  �@     �  j
  T1Q
 R|  @     �  U|    �@     X      "  !8  �  ���!�  �  ��W"cp    �	  "ep    �
  "sd !L    #�  ";   3   �@     M       Q  $@     ~  &  T	-@      B@     �  U��WT	g-@     Q���  @     �  x  U���T	�,@      �@        �  T	�,@      �@     �  �  U��WT	�,@     Q��� �@       �  U��W �@     �    U��WT	�,@     Q��� �@       U��W   V@     %       S  {@     ~  T	{-@       �@       �@     #  �  U����Tw Q0 �@     .  �  U@T0 @     9  �  U	L+@      #@     H  �  U	�+@      E@     T  �  T2 c@     c    Us T��� �@     ~  9  T	�+@      �@     �  P  U1 �@     p  |  Us T	@�`     Q
  �@     r  �  U	@�`     T0 �@     }  �  U���T	�+@     Qv  @     �  @     �  @     �    T	�+@      >@     ~  1  Uv T	�+@     Rs  F@     �  I  Uv  Y@     �  a  Uv  q@     �  �  U	T,@     Q1 �@     �  �@     �  �@       �  U	],@      �@     �  �  U	�,@     T	�+@      )@     �    Uv ����T8 9@     �  8  U	#@     Ts  $ & M@       i  U} T| Q	�-@     R|  W@       �  U}  s@       �  U}  �@     #  �@     .  �  U~ T Y|  �@     �  �  Us T}�|Q
  V@       �@     9  �@     p  6  Us T	@�`     Q
  �@     E  Z  U	@�`     T3 �@     �  �  Us T	@�`     Q
  �@     P  �  Us  �@     \     	B   �  $�   � m  %  �  m  	  �  $�   � 	  �  $�   � &  �3  	B     $�   � &�    	B   .  ' &  #  &�  D  P   (opt (x  )B  .  	@�`     )R  /'  	H�`     *{  {  d*�  �  +9  9  2*�  �  �,$  
  �$  ,  �  �  *r  r  �*]  ]  n*    l-q  g   q  +q  q  }*(  (  �*�  �  w+*  *  %+�  �  $-�  �   �  *_  _  4-Q  �  �Q  -m  M  �m  +�  �  .*      �,X  �  nX  *�  �  2*�  �  >+J  J  �*;  ;  H*X  X  N+/  /  *
  
  h*    �+�  �  
1+~  ~  
R+J  J  
:+    
A+�  �  
4+�  �  2*f  f  =+    +*�  �  d*@  @  � �	   �  �  �	  H  �@     �      �  �  �       �  �      int       {   n   �  04   
  1;   �	  3B   O  7-     �  W   �  n   �   	e    �   
��<  �  �    [  �   g  �   w  �   �  �<  �  ��   �  �L   n   L  	e   
 �   ]  e   � ��  �  �    s	  �   �	  �   �	  �    	  �   �	  �   -
  �  �  �   [  �   g  �   w  ��   �  �<  #�  ��   .�  �  6 �     	e    �   0  e   � ��P  '  ��   �	  �]   f
   �3  e  �3   @  ��   1	  ҋ   �  Ӏ   �  ԋ   �	  Հ   |	  ֋   	  ׋   �
  ؀   [  ً   �
  ڋ   �  ۋ   f	  ܖ   #	  ݖ    0  $�	  ��   ��  ��   �Z	  ��   � �   C  	e    J   �  e  3   @  �   1	  �   �  �   �  �   �
  3  ?
  �   �
  	�   J
  
�   �
  �   �  �   �  �   U
  �    �  �   $�  �   (  �   0l  �   8?	  �   @�
  3  A�
  �   D	  3  E
  �   H�  �   P�  �  T�	  �   ��  �   �Z	  �   � �   �  e   � $  B   �     �  �  �  �   �	  (�     p (     �   S	  -�   3  p -3   9  �   �
  8�   X  p 8X   ^  �      �@     T       ��  bs  l   �  7
   W   k  �@            �  �  #�  �  sbs $     �@     '       �  *    sbs +    P    P  C    C  !�  .W   9  "sb .   �  �u   j  bs ��   #7
  ��   $  �   
  3u   �  bs 3�   #7
  3�   $v
  5W   $  6   $�  7�   $5  7�   $,  7�   $�  8�   $�	  9W   $  9W   %$`
  i�    n     	e   ( &�  �u   �@     �      ��	  bs ��   g  7
  ��   �  $�	  ��   v
  �W   M    �   �  $�  �u   '  N@     =       ��  (-  U   'j  �@     �      �	  (�  x  (z  �   �@     �      )�  �  )�  �  )�  �  )�    )�  �  )�  .  )�  Y  )�  �  �@            G  *�  	`Q`      +K@     �	  q  ,U~ ,T	�/@     ,Q8 +x@     �	  �  ,U~ ,T	�/@     ,Q8 +�@     �	  �  ,U~ ,T	�/@     ,Q8 +�@     �	  �  ,U~ ,T	�/@     ,Q8 -@     �	  ,Us� ,T	�/@     ,Q8   .9  %@     Z       �(S  ~  (I  �   %@     Z       )^  �  +;@     �	  �	  ,Us ,T	�/@     ,Q8 +Q@     �	  �	  ,Us ,T	�/@     ,Q8 -g@     �	  ,Us ,T	�/@     ,Q8    4   �	  / 0�	  �	  1	  	  A �   U  �  2  H  �@     �      	  �  �8   �  �       �  �      int     �i   p  �i     �     �  ��  �  �b    '  ��   x  ��   z  ��   �  ��    �  ��   (�  ��   0�  ��   8�  ��   @	�   �   H	0  �   P	�  �   X	D  Q  `	4  W  h	�  b   p	B  b   t	�  p   x	�  F   �	�  T   �	X  ]  �	  m  �	�  !{   �	�  )�   �	�  *�   �	�  +�   �	�  ,�   �	�  .-   �	W  /b   �	�  1s  � 
�  �=  �Q  j  �Q   �  �W  %  �b       �   �   m  �       �   �  �    �  �   �  0?   
  1F   �	  3M   O  78     �  �  �   �  �    �  1�  �  �W  �  ��   )  ��  �  ��  M  ��  
�  ��    ��  -  ��  Y  ��   �  ��  �  ��     ��    ��  �  ��  �
  ��  �
  ��  
�  ��    Ù    ę  �  ř   j  
�  lba ʯ   len ˙   ��_  �  �   [  �  g  �  w  �  �  �_  �  ��  �  �o   �   o  �   
 �  �  �   � ��2  �  �   s	  �  �	  �  �	  �   	  �  �	  �  -
  �2  �  �  [  �  g  �  w  ��  �  �_  #�  ��  .�  �B  6 �  B  �    �  S  �   � ��s  '  �  �	  ��   f
   �V  e  �V   @  ��  1	  ҙ  �  ӎ  �  ԙ  �	  Վ  |	  ֙  	  י  �
  ؎  [  ٙ  �
  ڙ  �  ۙ  f	  ܤ  #	  ݤ   S  $�	  ��  ��  ��  �Z	  ��  � �  f  �    S	  -�  �  p -�   �  �  �
  8�  �  p 8�   �  �  ptr S�   �  img S�   9  S�   �  �
  S�  p S�  v S�   �
  m  p m  v m�   �    _@  p _@  v _�   �    !�  ex !�  
  !b   �
  "�  �  "b     $�  �  %�  �  &�  lba &�  len 'M   k  D  2�    �  �  �  �  cb   �@     �      �Y   �
  c�  �   r  cb   `   �  db   �   S  db   �   �  e�  D   �
  e�  �  !�  gY  *  epa h_  ex i�  "wp j@  �  !�  kb   �  !z  l�  @  "i mb   {  "dw mb   �  !
  mb     sbs ne  �  o  #�  �@     �   y	  $�  o  %�   &!  �@            |5	  $6  %  %-   #!  �@     �   }[	  $6  H  %-   &�  �@            ��	  $�  �  %�   &�  @            ��	  %�  %�   &�  @     	       ��	  $�  �  $�  �   &!  #@            �
  $6  �  $-     &�  -@            �5
  $�  >  $�  b   &�  4@            �_
  $�  �  %�   #F  m@        ��  $r  �  $g    $\  j  $R  �  '   (}  �  (�  ,  (�  x  (�  �  (�  �  )�  �@     *0  D  (�  U  &�  �@            ;  $  �  $  �   +�  �@            <$�  �  $�      &�  @            Jr  $  0  $  S   +�  @            K$�  v  $�  �     &�  @            ��  $�  �  %�   &�  &@            ��  $    %   &�  2@            �  $  .  %   ,;@     I       s  !c  �b   Q  -c@     �  _  .U	�/@      /m@     �  .U1  ,�@     I       �  !c  �b   �  -�@     �  �  .U	)0@      /�@     �  .U1  &!  �@            ��  $6  �  $-  �   &!  �@            �&  $6    $-  )   -c@     �  E  .U	�/@      /m@     �  .U1  �  W  s  0  �W  ?   �  1 0�	  v  0  v  0�  �  M   2�  �  	 �  3�  �  
 �   �  �  P  H  @     x        �  �8   �  �       �  �      int     �i   p  �i     �     �  ��  �  �b    '  ��   x  ��   z  ��   �  ��    �  ��   (�  ��   0�  ��   8�  ��   @	�   �   H	0  �   P	�  �   X	D  Q  `	4  W  h	�  b   p	B  b   t	�  p   x	�  F   �	�  T   �	X  ]  �	  m  �	�  !{   �	�  )�   �	�  *�   �	�  +�   �	�  ,�   �	�  .-   �	W  /b   �	�  1s  � 
�  �=  �Q  j  �Q   �  �W  %  �b       �   �   m  �       �   �  �    �  �   b     �  �  �   h�  �  j�   �  mb   �  n�  val ob    �  `�  �  M    �  M   S  b   �  	b   8  
b   j  �  r  b    �  �  (�  �  0�  M   8�  �  @�  b   HC  b   L!  b   P�  �  X B  M   �     �  �  �     M   �  �     �   �  K@     "      ��  rv Kb   N  X  K�  �  E@     c  L  T	�3@      ]@     c  x  T	J1@     Q	G1@      n@     o  �  U	I3@      �@     c  �  T	T0@      �@     c  �  T	�0@      �@     c    T	J1@     Q	G1@      �@     o     U	I3@      �@     o  	@     o  L  U	A4@      @     ~  d  Uv  (@     c  T	J1@       *  �6@     �      ��  4  �b   U   �  ��  �   X  ��  �   o �b   9!  �  !@     d@     �  #  U| Tv Q	@6@     R	`6@     X0 � @     �  ?  T0Q0 � @     �  [  T0Q0 !@     c  !@     ~  s!@     c  �  T	�4@      �!@     �  �  T0Q0 "@     c  �  T	5@      ="@     c  �  T	B5@      I"@     �   �   �  �b   �"@     �       ��  rv �b   "  �"@     �  #@     �  U  U1 8#@     c  t  T	[5@      f#@     �  �  U2 �#@     c  T	�5@         �W  �  9�   �  Gb   �  Pb   ?   �  �   � �  �  B  	�  opt  �  	�Q`     �    �    {  24  	`6@       �   I  �    �  I^  	@6@     9   {  {  d!�  �   �   �  �  
"    �"�  �  
�"/  /  "k  k  
 �   �	  �  !  H  �#@           �  �  �8   �  �       �  �      int         �  �   �  �  0?   �	  3M   �
  8�   �   p 8�    �   	�   :  �b     p �  
i �b   z  ��    	  	?     _-  p _-  v _�    �   |  )�#@     ?       �  i  )  d"  i +b   �"  z  ,�   �"    �#@            /�  #  9#    a#     �#@            5�  #  �#    �#     �#@     
       6#  �#    �#    ?   k  ;b   �#@           ��  tag ;b   $  M  ;-   �$  o  ;�   V%  p =�  �%  I  >-   �&  u  ?�  ��{ $@     =       �  N  P�   �&  p  Q-   m'  M$@     �   �#@     �  x$@     �  �$@     3  U	`�`       �   �     p   � /  ��$@            �Q  i  �  �'  �$@     3  U�U  S  �b   �$@     �       �o  i  �  :(  �   �$@     `  ��  �   �(   `  !�   !�   "%@            #�   "%@            $�   �(  $�   )      �   G%@     �  �Y  �   /)   �  !�   !�   "j%@            #�   "j%@            $�   h)  $�   �)      �%@       U�U  ?   �  p   � %�  #o  	`�`     &    .&9  9  2 �    �  �  �  H  ;
  5   .   .   �   �   �	     	 R`     �  Dm   	�8@     �  f   �  F�   	�8@     int �    �    !  �  �  H  z
  5   .   .   ��   �        	 T`     �  n   	�8@     �  g   �  �   	�8@     int �    �   �  �  +  H  �%@     `      �
  �  �8   �  int �       �  �              �	  �?   �  y   �   p    �  �  0F   
  1M   �	  3T   O  78     wi   �  �   H  �   �    �     p    $  #  �   3  p    �*�  	�  +�    	Y  ,�   	e  -�   	u  .  	�  /�  	�  0�   	�  2�   y   �  p   
 �   �  
p   � �6d  	(  7   	  8�   	�  9�   	�  :  	<  ;�   	m  <�   	`  =d  	�  @�   	Y  A�   	e  B�   	u  C  	�  D�  #	�  E�   .	�  Gt  6 y   t  p    �   �  
p   � �(�  �  33  4  H�    
   r  	e  r   	@  �   	1	  �   	�  �   	�  �   	�	  �   	|	   �   		  !�   	�
  "�   	[  #�   	�
  $�   	�  %�   	f	  &  	#	  '   u I�  $Z	  K�   � �   �  p    �  �  n �    	k  �  	o  �   �  y   �  
p   � �  T   �  �     :     P%�  	  &�   	@  '�   	�  )�  	�  *T   	N  +?   	{  ,�   	�  -�    fat /�   (	   0�   0	o  1�   8end 2�   @	�  4�  H ?   �  �   w   -   �    �     F   �  _p  �   �   G  .M   �  _p .�   �   �  8T   
  _p 8
     �  f  �%@     N      �f    �  �)  @  �   *  fs f  ]*  bs l  �*  i ?   �*  �  �   '+  �  �   J+  �  �   m+    �   �+  �   �   ,  �  k�&@     �  !&@            <�  �  �,   �  ;&@            C  �  �,   �%@     �  4   UP �%@     �  Q   Us  T0 !�&@     �   Us   �  �  "�  q�&@            ��  #fs qf  �,  �&@     �  �   Us  $�&@     �   U�U  %
  
  	�&�  �  L%[  [  	�&N  N  G �   �  �  �  H  �&@     �         �  �8   �        int       �  �      �	  &M   �  0�   �   
  1F   �	  3�   �  O  78     w[   �  �     0 
  �  !�    �  "M     #
   �     ?    H  �   �  0  �   @  ?    $  K  �   [  ?    )   S�  �  T�   �  U  �  V     W  �  X@  �  Y%     Z%  �  [@    \%  M  ]@     �  ?   
 	�     
n �    k     o  &   �  T   7  ?   � �  �   Z  �     :     P%�    &   @  '�   �  )7  �  *�   N  +M   {  ,~   �  -~    
fat /�   (   0�   0o  1�   8
end 2�   @�  4   H M     �     -   �    �  �  8�   8  _p 88   @  G  .F   Y  _p .Y   %  ~  ~   �&@     �       �a  fs a  M-  �  ~   �-  �  g  �-    n  .  dep t  j.  �  M   �.  s �   �.  '@     z    U} T�T >'@     �  #  U} Tv  Y'@     �  F  Us T~ Q; �'@     �  U} Tv   Z  m  �   [  J  J  :�  �  L	  	  A    A '     �  ;  H  �'@     �         �  �8   �  int �       �  �              �	  �?   �  �  O  78     wi   �  �   �  �   n �    k  �   o  �    	�   
y     p   � �  T   +  �     :     P%�    &�   @  '�   �  )  �  *T   N  +?   {  ,�   �  -�    fat /�   (   0�   0o  1�   8end 2�   @�  4�   H ?   �  �   w   -   �    	�  N  6�'@     %       �B  fs 6B  G/  ls 8�   �/  4  8�   �/  �'@        	+  �  w   �'@     �       �  fs B  0  n �   ^0  ls �   �0  (@       �  U
 .(@     �  �  U}  8(@       �  U
 Y(@     �  Ts Q
 R|  h(@       Uv   [  [  �
  
  � 6   z  �  t  H  �(@     �      ,    �  �?   �  int   �  �      �	  &F   �  0   �   
  1�       �	  3�   �  O  7?     w-   �  �     �  �   t   �   �    $  �   t     �      �  ?  n �    	k  ?  	o  E   
    V  �   � �  �   y  �     :     P%  	  &6   	@  '�   	�  )V  	�  *�   	N  +F   	{  ,i   	�  -i    fat /�   (	   0�   0	o  1�   8end 2�   @	�  4?  H F   4  �   4  4   �    
  G  .�   W  _p .W   
�   �  8�   x  _p 8x   
�   J  �   �(@     /       ��  fs �  Uj  i   A1   
�  y    -�   �(@     q      �"  fs -"  �1  s .�   J2  j  0i   K3  W  0i   �3  M  1�   4  �  2�   �4  m  3(  �5  c  4�   �5  rs 5�   -6  <  �)@            m�  L   ]  �)@            z�  m   L)@     .  �  Uv  x)@     .  �  Uv  �)@     .  �  Uv  �)@     .    Uv  *@     ~  U�U  
y  
t    �  �  L r    "  f  �  ../sysdeps/x86_64/crtn.S /glibc-tmp-4da84b6e011d91753dd26471d5e4a31b/glibc-2.23/csu GNU AS 2.26 � %   %  $ >  $ >  4 :;I?  & I    U%   %U   :;I  $ >  $ >      I  :;   :;I8  	I  
! I/  & I   :;I8   :;  &   I:;  (   .?:;'�@�B   :;I  ��1  �� �B  ��1  .?:;'�@�B  �� 1  .?:;'I@�B   :;I  4 :;I  4 :;I  4 :;I  4 :;I  4 :;I  U     !4 :;I  "4 :;I  #4 :;I  $! I/  % <  &4 :;I?<  '!   (4 :;I?<  )4 :;I?  *. ?<n:;  +. ?<n:;  ,. ?<n:;n  -. ?<n:;n   %  $ >  $ >      I  & I   :;I  I  	! I/  
&   :;   :;I8  ! I/  :;   :;I  :;   I8   :;I8  :;   :;I8   :;I8  I:;  (   .:;'I    :;I  .?:;'@�B   :;I   :;I    4 :;I  4 :;I     !.:;'I   " :;I  # :;I  $4 :;I  %  &.?:;'I@�B  '1XY  ( 1  )4 1  *4 1  +��1  ,�� �B  -��1  .1XY  /!   04 :;I?<  1. ?<n:;   %   :;I  $ >  $ >      I  :;   :;I8  	 :;I8  
 :;  I  ! I/  & I   :;I8  :;  ! I/  :;   :;I  :;   I8   :;I8  .:;'I    :;I  .:;'I    :;I  .:;'   4 :;I  4 :;I  
 :;    .?:;'I@�B    :;I  !4 :;I  "4 :;I  #1RUXY  $ 1  % 1  &1XY  'U  (4 1  )
 1  *U  +1XY  ,  -��1  .�� �B  /��1  04 :;I?<  1!   2. ?<n:;n  3. ?<n:;   %   :;I  $ >  $ >      I  :;   :;I8  	 :;I8  
 :;  I  ! I/  & I   :;I8  I:;  (   .?:;'�@�B   :;I   :;I  ��1  �� �B  �� 1  ��1  .?:;'@�B  4 :;I  
 :;  .?:;'I@�B  4 :;I?<  ! I/  4 :;I?  4 :;I?   . ?<n:;  !. ?<n:;n  ". ?<n:;   %   :;I  $ >  $ >   I  &   .:;'I    :;I  	& I  
4 :;I  4 :;I  .:;'   .:;'@�B   :;I  4 :;I  4 :;I  1XY   1  1XY  .?:;'I@�B   :;I  4 :;I    �� 1  ��1  �� �B  I  ! I/  .?:;'@�B  ���B1  1RUXY   U  !4 1  "  # 1  $4 1  %4 :;I?  &. ?<n:;   %  I  ! I/  $ >  4 :;I?  & I  $ >   %  I  ! I/  $ >  4 :;I?  4 :;I?  & I  $ >   %   :;I  $ >  $ >     I  ! I/  :;  	 :;I8  
! I/  :;   :;I  :;   :;I8   :;I8   I  I:;  (   :;  'I   I  .:;'I    :;I  .?:;'I@�B   :;I  4 :;I  4 :;I  
 :;  1XY   1  ��1   �� �B  !��1  ".?:;'@�B  # :;I  $���B1  %. ?<n:;  &. ?<n:;   %   :;I  $ >  $ >  :;   :;I8  I  ! I/  	:;  
 :;I8   I  ! I/  I:;  (   'I   I     .:;'I    :;I  .?:;'I@�B   :;I   :;I  4 :;I  4 :;I  ��1  �� �B  ��1  &   . ?<n:;   %   :;I  $ >  $ >     :;   :;I8   :;I8  	 I  
I  ! I/  I:;  (   :;  'I   I  .?:;'@�B   :;I  4 :;I  4 :;I  �� 1  .?:;'I@�B  ��1  �� �B  ��  ��1  . ?<n:;   %  $ >   :;I  $ >  I  ! I/  :;   :;I8  	 :;I8  
 I  ! I/  I:;  (   :;  'I   I     .:;'I    :;I  .?:;'I@�B   :;I   :;I  & I   :;I  4 :;I  4 :;I  1XY   1  ��1  �� �B  ���B1   . ?<n:;    U%   X    0   �      ../sysdeps/x86_64  start.S     	�@     >.B#>M$ uvx[ #       �       init.c     `    /   �      ../sysdeps/x86_64  crti.S     	 @     ?Lu=/  	�*@     �  �   �  �      /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include/bits /usr/include/sys /usr/include ../libfat ../libinstaller  syslinux.c    stddef.h   types.h   types.h   time.h   stat.h   stdint.h   stdio.h   libio.h   libfat.h   syslxopt.h   syslxfs.h   setadv.h   syslinux.h   stdlib.h   errno.h   string.h   unistd.h   <built-in>    fcntl.h   stat.h     	P@     1K�� =X'��+ AYYugt[�===]"�H"�^.�+ AYYugt[�===]  	�@     ��YIid�Z�� � �� ��	X�tt9?XtXJu-// �� �K��k�;m u WZ�Y J?
ֻ s�u���;=4 � �[e�� J|g^y<=u�=Y-=��dL�Dx�[� � Y,��X ltu��Xt.Y/YuY�Y�;K/�Y k�XKg����� Ju���� Ju��i�hu]     y   �      ../libinstaller /usr/include  fs.c   syslxint.h   stdint.h   syslxfs.h   syslinux.h   string.h     	�@      ;=3�I/�]uջ� f�gWiKujT � >��W!�~�VK1K�?�_zXwʖ�KWz�	Xwf	<h=Wi��uW�YuW�=Wh[KW�fuXmLVg-
J+Y	��L0V5+Y�    �   �      ../libinstaller /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include/bits /usr/include  syslxmod.c   syslxint.h   stddef.h   types.h   libio.h   stdint.h   syslinux.h   stdio.h   <built-in>    stdlib.h     	�@     � � ��pf�hJoJ'XY<t.b.tV.0�BJ.0tPJ�*�J.r� �Z��� ��ta`,2[,>/�=+f<fJM>rt<g�(Jf<� J�<� �xbPX1tOX4t/�I/K�j��I/K��f� �- Y g��J� Je=�� �   �   �      ../libinstaller /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include/bits /usr/include  syslxopt.c   stddef.h   types.h   libio.h   getopt.h   syslxopt.h   stdio.h   setadv.h   syslxcom.h   stdlib.h   <built-in>      	@     � ;X/��tW.
�� � t YYett�w9[u�>-�A.;K�DX(�X�K��S�^u��u����Z�Z�[�]K�2�[YZ�`�Z�Z�ZZ�Z�v�1K0�N��0^?���P&��&L,_ V   �   �      ../libinstaller /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include /usr/include/bits  setadv.c   syslxint.h   stddef.h   stdint.h   string.h   errno.h     	�#@     )9<N� Z ��+tUȰ37�uX��HY@K�M[\i[=k<�Y�Xg\I=Lg;=I\�!�mJt�H>��pfp<&���n<tr�����hY> ;    5   �      ../libinstaller  bootsect_bin.c    :    4   �      ../libinstaller  ldlinux_bin.c    G   �   �      ../libfat /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include/sys /usr/include  open.c   ulint.h   stddef.h   types.h   stdint.h   libfat.h   fat.h   libfatint.h   stdlib.h     	�%@     {yXC� ��.�T�=LY�� s�?H?ICWVN:Lx.J�FN#9M2g>d>0-ug�uK�u@h�g���/[ =Y= �    �   �      ../libfat /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include  searchdir.c   stddef.h   stdint.h   libfat.h   ulint.h   fat.h   libfatint.h   string.h     	�&@     M[9?hg��;=]=Y!KZi�nJ�c�X &   �   �      ../libfat /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include/sys /usr/include  cache.c   stddef.h   types.h   stdint.h   libfat.h   libfatint.h   stdlib.h     	�'@     6#K � Y K �\V. JYYJ f c	�wX	JY;=/��-\ʃNILIM= 6   �   �      ../libfat /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include  fatchain.c   ulint.h   stddef.h   stdint.h   libfat.h   libfatint.h     	�(@     K>KZI X[�	 ��r�fo<.:>ג��ْ�?>ako]Y�&,>dj�0�FX<fM�>�CX?f>h@�� J=eUN��� .� � J ]    /   �      ../sysdeps/x86_64  crtn.S     	@     'K  	+@     +K short unsigned int short int _IO_stdin_used /glibc-tmp-4da84b6e011d91753dd26471d5e4a31b/glibc-2.23/csu GNU C11 5.3.0 -mtune=generic -march=x86-64 -g -O3 -std=gnu11 -fgnu89-inline -fPIC -fmerge-all-constants -frounding-math -ftls-model=initial-exec unsigned char sizetype init.c __off_t pwrite64 _IO_read_ptr _chain st_ctim install_mbr uint64_t _shortbuf ldlinux_cluster update_only libfat_searchdir VFAT MODE_SYSLINUX done _IO_buf_base long long unsigned int fdopen secp errmsg BTRFS mtc_fd syslinux_adv libfat_sector_t __gid_t intptr_t long long int st_mode mtools_conf setenv program libfat_clustertosector __mode_t set_once bufp _IO_read_end _fileno __blkcnt_t dev_fd _flags __builtin_fputs __ssize_t _IO_buf_end _cur_column syslinux_ldlinux_len _old_offset tmpdir asprintf count syslinux_mode __pad0 pread64 st_blocks st_uid _IO_marker /tmp/syslinux-4.07/mtools ldlinux_sectors nsectors fprintf command stupid_mode sys_options ferror _IO_write_ptr libfat_close _sbuf bootsecfile device directory syslinux_patch _IO_save_base __nlink_t sectbuf _lock libfat_filesystem syslinux_reset_adv _flags2 st_size mypid perror getenv unlink fstat64 tv_nsec __dev_t tv_sec __syscall_slong_t _IO_write_end libfat_open heads _IO_lock_t _IO_FILE __blksize_t GNU C11 5.3.0 -mtune=generic -march=x86-64 -g -Os MODE_EXTLINUX stderr _pos parse_options target_file _markers __glibc_reserved st_nlink __builtin_strcpy st_ino syslinux_make_bootsect __pid_t menu_save st_blksize timespec _vtable_offset syslinux.c exit NTFS __ino_t st_rdev usage long double libfat_xpread syslinux_ldlinux activate_partition argc __errno_location fclose open64 mkstemp64 __uid_t _next __off64_t _IO_read_base _IO_save_end st_gid __pad1 __pad2 __pad3 __pad4 __pad5 __time_t _unused2 die_err st_atim argv mkstemp status MODE_SYSLINUX_DOSWIN popen calloc st_dev libfat_nextsector _IO_backup_base sync st_mtim fstat raid_mode pclose patch_sectors fwrite secsize slash getpid force xpwrite strerror syslinux_check_bootsect main _IO_write_base EXT2 bsUnused_6 bsTotalSectors ntfs_check_zero_fields clustersize bsMFTLogicalClustNr bs16 dsectors fatsectors bsOemName ntfs_boot_sector bsFATsecs bsJump bsMFTMirrLogicalClustNr retval check_ntfs_bootsect FATSz32 uint8_t bsHeads bsSecPerClust bsForwardPtr bsResSectors bsUnused_1 bsUnused_2 bsUnused_3 FSInfo bsUnused_5 memcmp bsSectors bsHugeSectors bsBytesPerSec bsClustPerMFTrecord get_16 bsSignature bsHiddenSecs ExtFlags bsRootDirEnts bsFATs rootdirents get_8 uint32_t bsMagic BkBootSec media_sig RootClus FSVer bs32 ../libinstaller/fs.c syslinux_bootsect uint16_t bsVolSerialNr check_fat_bootsect Reserved0 fs_type bsZeroed_1 bsZeroed_2 bsZeroed_3 fserr fat_boot_sector sectorsize bsClustPerIdxBuf bsZeroed_0 get_32 bsMedia bsSecPerTrack bsUnused_0 bsUnused_4 subvollen sectp subvol set_16 set_64 secptroffset checksum sect1ptr0 sect1ptr1 diroffset instance ../libinstaller/syslxmod.c adv_sectors epaoffset sublen syslinux_extent csum xbytes ext_patch_area dwords advptroffset subdir raidpatch stupid data_sectors nsect secptrcnt advptrs patcharea magic subvoloffset dirlen nptrs addr set_32 generate_extents maxtransfer offset_p long_only_opt ../libinstaller/syslxopt.c syslinux_setadv long_options has_arg name opt_offset short_options optarg OPT_RESET_ADV optind OPT_DEVICE OPT_ONCE modify_adv option flag optopt strtoul OPT_NONE getopt_long memmove ../libinstaller/setadv.c adv_consistent left ptag syslinux_validate_adv advbuf plen advtmp cleanup_adv syslinux_bootsect_len ../libinstaller/bootsect_bin.c syslinux_bootsect_mtime ../libinstaller/ldlinux_bin.c syslinux_ldlinux_mtime malloc read8 bpb_extflags le32_t ../libfat/open.c bpb_fsinfo read16 clustshift bsReserved1 bsBootSignature bsVolumeID barf fat_type read32 bpb_fsver bsDriveNumber libfat_sector fat16 bpb_rootclus minfatsize le16_t bsCode bsVolumeLabel nclusters FAT12 FAT16 readfunc rootdirsize rootdir bpb_fatsz32 fat32 FAT28 readptr le8_t libfat_flush free bpb_reserved bpb_bkbootsec endcluster bsFileSysType libfat_get_sector rootcluster clustsize ctime attribute caseflags atime ../libfat/searchdir.c dirclust nent clusthi clustlo libfat_direntry ctime_ms fat_dirent lsnext ../libfat/cache.c fatoffset nextcluster clustmask fsdata ../libfat/fatchain.c fatsect P@     [@      U[@     m@      Rm@     x@      �U�                x@     �@      U�@     �@      S                �@     �@      U�@     "@      ^"@     #@      �U�                �@     �@      T�@     #@      �T�                �@     �@      Q�@     @      S                �@     �@      R�@      @      ]                �@     �@      T�@     @      \                �@     �@      P	@     @      P                �@     �@      0��@     @      V@     #@      P                #@     5@      U5@     8@      �U�                #@     5@      T5@     8@      �T�                #@     5@      Q5@     8@      �Q�                #@     '@      R'@     8@      �R�                8@     N@      UN@     �@      ^�@     �@      �U�                8@     N@      TN@     �@      �T�                8@     N@      QN@     �@      S                8@     N@      RN@     �@      ]                G@     N@      TN@     �@      \                d@     z@      P�@     �@      P                G@     N@      0�N@     �@      V�@     �@      P                �@     �@      U�@     �@      ���                �@     �@      T�@     �@      w �@     �@      ���                I@     K@      PK@     W@      SW@     b@      Pb@     �@      S�@     �@      S                @     @      P�@     @      PV@     ]@      P                0@     5@      P5@     �@      V�@     �@      V@     @      V                @     @      P                @     9@      P9@     =@      U=@     J@      VQ@     �@      V�@     �@      V                �@     �@      P�@     �@      \�@     �@      P�@     @      \                >@     L@      PL@     �@      ]�@     �@      U                W@     r@      Ps@     �@      P                M@     W@      ^]@     d@      | 3$~ "�d@     v@      |3$~ "�v@     ~@      | 3$~ "�                4@     8@      P8@     �@      ^                M@     V@      P                M@     W@      0�]@     n@      \n@     v@      |�v@     x@      �x@     ~@      \~@     �@      _                �@     �@      P                "@     �@      V                �@     �@      V                �@     �@      P�@     �@      \�@     �@      \                �@     �@      �����@     @      U@     @      ����@     @      �ķ�@     U@      UU@     {@      Q{@     �@      u��@     �@      U�@     �@      u��@     �@      U�@     �@      Q�@     �@      U�@     �@      u��@     �@      U                �@     L@      ��W�                @     L@      V                �@     "@      1�"@     :@      P>@     E@      PJ@     �@      0��@     �@      P�@     �@      0��@     �@      P                                U       %        uu�%       (        p��(       8        P8       Q        UQ       S        p��S       T        �U�                                T       (        �T�(       =        T=       T        �T�                               U       %        uu�%       (        p��                -       8        P8       Q        UQ       S        p��                T       �        U�       �       S�      �       U�      �       s}��      �       �U�                T              T      |       \|      �       T�      �       \�      �       �T�                t       �        P�       �        q��       �        P�       �      	 s�
���4      f      	 s�
���|      �       P                T       �        U�       �       S�      �       U�      �       s}��      �       �U�                �       �        S                �              T      |       \                �       |       S                �       |       
 �                             P                             R      $       Q$      -       x q �-      4       QF      K       RK      N       0�N      R       x r �R      �       R4      f       R                      =       P=      @       p q �@      e       P                F      e      	 p u ��                0      4      	 s�
���4      7       Q7      :       qq�:      �      	 s�
���4      f      	 s�
���                �              P             r�      �       u ���      �       s���4      X       u ��X      f       s���                |      �       T�      �       \                |      �       S�      �       U�      �       s}�                        p        Up       y       Vy      �       �U#��      �       U                        X        TX       �       �T��      �       T                        �        Q�       �       �Q��      �       Q                        v        Rv       �       �R��      �       R                        �        X�       �        ���       �        X�       �       ���      �       X                        �        Y�       �        ���       �        Y�              ���      �       Y                3       �        [�       �       [�      (       [3      �       [                $       �        [�       �       [�      (       [3      R       [                       �        Z�       �       Z�      �       z��      �       Z                R      Y       ��>�Y      �       Q                R      Y       0�Y      f       Pf      i       p�k      o       P                �       �        P�       �       ��                �       �        p 
����       �        p 
����             	 s�
���                3       T        {�T       _        s�_       r        s�r               s��       ~       s
�~      �       S�      �       s�3      J       s�                T       _        \                _       g        |  %�g       p        u                r               
��                �       �        z~�                �       �        {�                �       �        ��                �       �        {�                �       �        1�                �       �        {�                �       ~       s
�~      �       S�      �       s�3      J       s�                �       ~       X                �              V             Y      l       y�l      ~       Y                �             	 s�
���                �       N       QN      R       q
�R      ~       Q                �              
 ��      �       T�      �       T                �              
 ��      U       \\      ~       \                      _       ]                �              0�      _       R_      s       ]s      ~       R                �              0�      _       P_      s       Us      ~       P                             ^      R       ��\      _       ��                G      J       R                G      J       Q                J      N       P                J      N       q�                w      z       R                w      z       Q                z      ~       P                z      ~       q�                ~      �       S�      �       s�3      J       s�                �      �       Q                �      �       Q                �      �       R�      �       R                      (       R3      J       R                J      R       0�                J      R       {�                k      s       Q                k      s       {�                        %        U%       \        V\       j        Uj       {        V{       �        U�       �        V�       �        U�       "       V                        *        T*       �        S�       �        �T��       "       S                "      8       U8      �       \�      �       �U�                "      8       T8      �       V�      �       �T�                "      8       Q8      �       S�      �       �Q�                P      �       P�      �       P�      �       P�      �       P      Z       Pa      h       P�      �       P�      �       P�      �       P5      ?       P                �      $       0�$      m       Sr      v       Sv      x       P                        <        U<       >        T>       ?        �U�                	               8�               p�               p�                	               �g�       ?        Q                        	        �/-Z�                        	        U                        *        Q                        *        u�                *       4        �d�(�                *       4        u��                ?       \        U\       h        �U�h       �        U�       �        ^�       �        �U��       H       ^H      X       �U�                ?       \        T\       h        �T�h       |        T|       �        V�       �        �T��       H       VH      X       �T�                ?       \        Q\       h        �Q�h       �        Q�       �        ]�       �        �Q��       H       ]H      X       �Q�                �       �        W�       �        X�       �        P�       �        X�       �        x��              P      <       XA      H       X                �       �        
���       �        S�              S      H       S                �       �        Q�       �        x �       �        Q�       <       QA      H       Q                �       �        P�       �        P�       �       
 x��#��             
 x��#�A      H       P                X      i       Ui      r       Qr      s       �U�                s      �       U�             P             �U�             P             �U�                s      �       U                �      �       q��      �       q�                �      �       R                �      �       p���      �       T                �      �       q��      �       q�                �      �       R                                U       M       \M      N       �U�                                T       K       VK      N       �T�                                0�               P       J       S                ;       .       P3      :       P?      F       P                [       �        R�       ?       s                ~       �        Q                �       ?       Y                �       �        R             R             R              r 9%�       ?       R                �       �        p�
��5$#�9&�                �       �        Q�       �        q~��       �        r~��       �        s�2��              Q      ?       s�2�                �       �        p �                �       �        p$�                N      V       UV      [       S[      _       U_      `       �U�                                U       �        ]�       �        �U�                                T       �        �T�                                Q       �        ^�       �        �Q�                                R       �        \�       �        �R�                E       J        PJ       �        S                J       �        _�       �        `��       �        _                        ,        P,       4        V4       >        P>       �        V                                U       %        �U�                               P       #        S#       %        P                               P       #        S#       %        P                %       L        UL       �        ]�       �        �U�                %       T        TT       �        \�       �        �T�                )       7        P7       8        pp�8       T        P[       d        Pd       r        Vr       t        Pt       �        V                                T       $        T$       .        t�                /       �        U�       %       V%      4       U4      L       VL      \       U\      �       V�      �       U�      �       �U��      �       U                /       B        TB       F        t�F       T        PT       �        T�       %       �T�%      )       T)      L       �T�L      Q       TQ      �       �T��      �       P�      �       t��      �       T                �              S%      '       SL      O       S                �              } ��             P             T      %       TD      L       Tk      �       T                �       �        \�       �        Q�       �        t��       �        |��              \            
 s 1&s "#�'      @       SO      h       S                �       �        | 9%����u("��       �        T�       �        T'      0       s 9%����u("�0      4       TO      X       s 9%����u("�X      \       T                �       �        P�              P5      L       P]      w       P                /       V        u�1��      �       u�1�                e       �        S�       �        p  �                        ��������         @     @     �*@     �*@                     �@     �@     �@     @                     P@     �@     �@     �@                     E       J       M       T                       _       g       i       p                       �       �       �       ~                            R      \      _                      s      y      |      �                      �      �      �      �                      ��������        @     $@     +@     +@                                                   8@                   T@                   x@                   �@                   �@                   ~	@                   �	@                   �	@                  	 �
@                  
  @                   0@                   p@                   �@                   �*@                    +@                   �8@                   �9@                   (N`                   8N`                   HN`                   PN`                   �O`                    P`                   @Q`                    �`                                                                                                                                                                             !                     ��                    ��                     (N`             !     8N`             /     HN`             <      @             >     `@             Q     �@             g     (�`            v     0�`            �      @                 ��                �     0N`             �     �>@             �     HN`             �     �*@             �    ��                �     @�`            �    ��                �     `Q`     )       �    ��                    ��                   ��                    �#@     ?           ��                '   ��                3   ��                ;   ��                F   ��                U   ��                     ��                c     (N`             t    PN`             }     (N`             �     �8@             �     P`             �    �*@            �                     �    8@     q       �                     �                                          )                      �     @Q`             E                     Y    �@     T       p                     �    �$@     �       �    �"@     �       �                     �                     �    �(@     q      �     �`             �    6@     �      �    `�`                                     �&@     �       &     �`            �    �*@             :                     S    �'@     �       e                     y   �*@            �    �&@            �    �(@     /       �    �8@            �                     �     R`            �                     �     T`      �          @6@                                    @N`             !                     @                     T                     k    �$@            ~                     �    @Q`             �                     �    �`            �    �@     q       �                     �                      �   HQ`             �     +@                @�`                `6@     �           x@     :       (    �`            <                     R    �'@     %       _    �8@            t                     �    0*@     e       �                     �    �8@            o    `�`             �    �@     *       �    �%@     N      �                     �     �`             �                         �#@               �@     b          @     "                           1                     F                     [                     n    P@     (       r                     �                      �    �@     �      �                     �    H�`            �    #@            �                     �                     �                     �    �`                                       �8@            6                     L    �@     �      �   
  @             d    �Q`     `       h     �`             init.c crtstuff.c __CTOR_LIST__ __DTOR_LIST__ __JCR_LIST__ deregister_tm_clones __do_global_dtors_aux completed.6948 dtor_idx.6950 frame_dummy __CTOR_END__ __FRAME_END__ __JCR_END__ __do_global_ctors_aux syslinux.c sectbuf.4815 fs.c fserr.3249 syslxmod.c syslxopt.c setadv.c cleanup_adv open.c searchdir.c cache.c fatchain.c bootsect_bin.c ldlinux_bin.c __init_array_end _DYNAMIC __init_array_start __GNU_EH_FRAME_HDR _GLOBAL_OFFSET_TABLE_ __libc_csu_fini getenv@@GLIBC_2.2.5 xpwrite free@@GLIBC_2.2.5 __errno_location@@GLIBC_2.2.5 unlink@@GLIBC_2.2.5 _ITM_deregisterTMCloneTable strcpy@@GLIBC_2.2.5 syslinux_make_bootsect ferror@@GLIBC_2.2.5 syslinux_validate_adv modify_adv setenv@@GLIBC_2.2.5 getpid@@GLIBC_2.2.5 libfat_nextsector _edata parse_options syslinux_adv fclose@@GLIBC_2.2.5 libfat_searchdir optind@@GLIBC_2.2.5 getopt_long@@GLIBC_2.2.5 libfat_get_sector system@@GLIBC_2.2.5 fstat64 libfat_close libfat_clustertosector syslinux_ldlinux_mtime pclose@@GLIBC_2.2.5 syslinux_bootsect fputs@@GLIBC_2.2.5 syslinux_ldlinux short_options __DTOR_END__ __libc_start_main@@GLIBC_2.2.5 memcmp@@GLIBC_2.2.5 mkstemp64@@GLIBC_2.2.5 syslinux_reset_adv calloc@@GLIBC_2.2.5 __data_start __fxstat64@@GLIBC_2.2.5 optarg@@GLIBC_2.2.5 fprintf@@GLIBC_2.2.5 __gmon_start__ __dso_handle _IO_stdin_used program long_options die_err optopt@@GLIBC_2.2.5 pwrite64@@GLIBC_2.2.5 libfat_flush syslinux_ldlinux_len sync@@GLIBC_2.2.5 __libc_csu_init malloc@@GLIBC_2.2.5 syslinux_bootsect_len libfat_open fdopen@@GLIBC_2.2.5 __bss_start asprintf@@GLIBC_2.2.5 syslinux_setadv main usage open64@@GLIBC_2.2.5 memmove@@GLIBC_2.2.5 pread64@@GLIBC_2.2.5 popen@@GLIBC_2.2.5 die perror@@GLIBC_2.2.5 _Jv_RegisterClasses syslinux_patch strtoul@@GLIBC_2.2.5 mypid libfat_xpread exit@@GLIBC_2.2.5 fwrite@@GLIBC_2.2.5 __TMC_END__ _ITM_registerTMCloneTable syslinux_bootsect_mtime strerror@@GLIBC_2.2.5 syslinux_check_bootsect opt stderr@@GLIBC_2.2.5  .symtab .strtab .shstrtab .interp .note.ABI-tag .hash .dynsym .dynstr .gnu.version .gnu.version_r .rela.dyn .rela.plt .init .plt.got .text .fini .rodata .eh_frame_hdr .eh_frame .ctors .dtors .jcr .dynamic .got.plt .data .bss .comment .debug_aranges .debug_info .debug_abbrev .debug_line .debug_str .debug_loc .debug_ranges                                                                              8@     8                                    #             T@     T                                     1             x@     x      L                           7             �@     �                                 ?             �@     �      �                             G   ���o       ~	@     ~	      X                            T   ���o       �	@     �	                                   c             �	@     �	      �                            m      B       �
@     �
      H                          w              @            $                              r             0@     0      @                            }             p@     p                                    �             �@     �      w                             �             �*@     �*                                    �              +@      +      �                              �             �8@     �8      �                              �             �9@     �9                                   �             (N`     (N                                    �             8N`     8N                                    �             HN`     HN                                    �             PN`     PN      �                           �             �O`     �O                                    �              P`      P      0                            �             @Q`     @Q      ��                              �              �`      �      `                              �      0                �                                   �                       �      �                             �                      ��      �N                                                  �5     4                                                  �H     �                                   0               �X     �                            +                     "i     f6                             6                     ��                                                         <�     D                                                   ��     0      $   F                 	                      ��     |                                                                                                                                                                                                                                                                                                                                                             ./.wifislax_bootloader_installer/lilo32.com                                                         0000644 0000000 0000000 00000267440 11651254716 017735  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ELF              w� 4           4    (             �  � �n �n          D  D�D�              a���UPX!�    �� �� �   y      ?d�ELF   ������4�   (   {��d-#�j ���� do��`?��  ��Q�td  ��� R?�_���[�e? �� (      @��i �* I ���U��S�  <�� 
��,[]�����1�^����PTRh$HhԀQVh9�����#������$�C���=�� uJ�p��w��,-l���X��B�����Ǿ��9�rm6 ��t>���}h���~�����K�]��m���^��Z��r~��
�3�� 6Rj h�(;\�;��=td t&]�����P���j/P�o(��o�&�PSh@��50��ma��L��q��1<9���I� {�BI]�-L g� S.��� y�,J_J!���!9��'Kva��j	� ���n߸����G��-X޼��\~ �@t<P�e�����P�Љ���>�������YY����	�IOwq��l�>W\`\$y\`W�9�`,d,r��`,d,_�� dPhPd�Er�PhPg �pztzpz �Atzoy�lhvlvhv�\$lvw��9lxpxlxr�px�Ϟ��J��$�L�6����jh�>��j$j�LHh���a�Bh�ZYj3jOvk7=jM/,h ]��j6�p���n�L$G�q�WVSQ��4��ܾ'�1�Y�Ā�>�$�*7�w9	��	k;�,�� �jo������hT�ɐl�o��
��H�	�����L��M�N�����B$؉ǅ�Uk�I&�	����d�1�� �d��	�=�uA&���w�����w��J���A���!��PPsw�[ߡ������?26�nL��tF�Q�^���y#tF,S�66��|�{wSI����� f�?Vadg���K�MSSq�k�l�leb>8���؅m�F��o�~1Ҋ��A<9��>;�u����$�p]_�$�>{0't�S�����g�N�_�Gg8-<�bg��?X�5�J��W�	�>�B��[�'���6Q7�MT?J��v�լ��$[�k~N�M�	��'H�+� %��VS�5�"�q�J$�~�=D��(�{���W�7�F��6�zOy�9}�M��zj�T냂�=�;<TR�95��#d;��@Hk��xj=R���6�>�ht�*@u�܍�P4	�.h��7l��t8�uq��Le?QQh�-�d��ސh�-�,�-�<R80��?��P[�x�����	��?���t�>
�u�H.�����F�S�#���˅�u��3G1�������AQJ�z���@��/d�v�n)��%����6���4WW�
R7S_w���Xh��kVkn,��&!�	�����l݅�3����/ȏ�M��i wKÛ5�#H�`|� 'WlPÈurd��V�g�d.n(�AF���`�$u';t7���/~ж��94�K�,�44�CP�ң�d������	yAg�=@Z��G�����G�Nsnr!4�Z��¡+EP킜�IN9Wd��	���!%! 0Y|�:���> q�!��(��ح�c���?��!4�D�{��K��"�v�F�,�2�����*+�0��_�: W�F��� 10Jd�T�_u�']�%8y#@�f�.vZ�07t�P$��	���xPl���7�6%U���y �z(�_�!��vXmؕ�X��� �J��$��ph �G6����H~�l�s!G���V��6� �Њ�B��uW]D�r����l��h�N�"t�ǥ�@���h�td��+Rt"�z��|3�L~WV8ݳPDPPq��1�~2=�� ����ȆW<�u��$�P��6s��Iq:1j&''�
�g��{3�	�
K�����P�e���&�M{
�g\���P�K��&�-���xY���1�HH�5�ٝQ�+�������?�+�X!�Q�+���{/yRR��V��i��b�1ۀxL�B�߼��z#<�0ײu4���)�}��
,�e�~�dɀ�u�\h��� �V�@�t��:+�1�~�06���q���}�� �uB�9�s8�P0����t�Q�n���/�H$��(:B��VVQc��`�w{$y9�<%��O�!�XB�Չs�A�a9ytt ��M����>�^_��}��[.hN��X�̈́-�S8��(}oЈ�N�UQG� �DnH���&޸h��^�������Q��=�$[�8\	0��]u�8��Y�L$2�H�w���5%q�eþ��cB;�ƈXc0�����h�E~�]#}�APG��원#O��M���b�tpu�Xv;�"Wؓ&�Q�Y �W�#���G.x858����R5��ss��N�'@1Z_�S�]Ȟ�B�� ӅƲrE�+Y�f�PN ��c_P0��
�D>Mu�3F�	8,�~#��P�\��Z[BG?�Rr��#���N����a10� %t�)��=gk�o�SbVx(�]�`7�5����+�S;\=���t.XS��Q:��C��'Rjwl�_5:@Y2˾Ր:@ �E�g�a� eXW�U��j�er�ȅ��å!S�r�O	o�~)���������ڃ�D�u;�t38�&���On�S�S�ˊ�3�1���ZH�n�U��� ���>�V�����tw���b��<�6��!
��cݾ��<��F��6�0	4��)�?���v�8�PR�m�T����1�S1,�E��DP&�Y^�T��� (T�E�i��7���������L��C��
 
�R99�E�wr�
�f�#`T�[�!H�GBR;|�5�z/d��E� [�5a�4�˦y�q�VV���  �<�r���Tg	U�f�%�,'EPBHn�9e1U;d��" x0�P"�o�lE u"��"���.��U�"�d3��@�U��<�ED��KV�B�-<K5V��%s}� (_HI�8���ņ�n��u
�|*PV��nK��P�`�I���tT��(`�-p"�/�K�C��x�W�!�eB!W\rX;u�M�-�M���M�oG��~�L��F�̘8e�CC�4�e���	𞹺+��	'�����ɓ��_��WQRk�6��uY��)� \8 $�sF���w��`ti1Ƀ�`uN~�V���l���(� }����:����ƍ<9��1�����+�WR%�!6�K.8W�7"@���a�L,����_�B�7&f�Nf�h1���ݒOc!nW,�!�f>�2�y�����=��x����K�'�pb'�W�W��x��!X�!X9�;`!��C EXh��<JX��{��~Dg
O�°�9fXB�2g�>�F��t �t�#_��|/�	���dk�X�~����m�3�鶄Xo����H��J�Y
� �n�p-Yk�����m�@��P�$�@�D$�M}ўQ�^3��8�YYl�Qj�d��rY[�6IB�!�QEgK��ԕRנ�@�Y=RdV�C֐�$�Yl�]R���_��sl���ӁZ��dJQ�W-Z�� �#�fW�8�h[Z$�Zp�f,��򌌍ߋ�PbB�Zj�P1�XWX9R�}�¹!�#�t�	�CRn��*2H�����)P('��&h��CQ> y�WQDt5��e=�Z�)�2O����<8�W2=�P�텀3u2<.�G_�[\[�[��K��Q��d�7��;ؖ�7L���.��?]kW��¾;��egU�:�tiw����;���[��������6�`>���8d���h�T�)l��T��F9�u��~' �'_��d|[^s,�h\�g�; /Q�>(8�A�X�vQ0�r3�"\%rGqnu	�E,�l�>57\�&�rT����G<W 2`
َ܉�$B�M8lV�5�7G7!`����WV�(�YX��R�!3ˆQ+�x����;Ws4�"ѐ���T� ��t0W��������<�s% ��	�ȑ
��kd�\�26}�%�:p�f�ݤ-4ʆ܈A���
�#���I�v�uX)	ݒ���\��i���WM����I�Z�ːK���+��\@������L�B����v
SS�7]gI]1#܀*_��N6MZ]h"�7�ύe�Y�_ɍa�ÞhO�� �Y�?�LG�~BjhX^���U��������_��1ۺ��bn��Յ���<��|������'��	�@9�|���}���s���Cho�U#������,+�K}�x^F����ɖ��a�Sh�^ى��������M�'Ыۃ��ښ�hm�1��.��X��Bu �!k�f6ժ��<_�����ȏ5�_O	t�Ć���t���έ��QP�4�,�;(���h�F_;V|�/G������%7�2ۀ&o7�.U5�%��^��h����Ft��kV�u�PI����n6����_u)��NR�� _�כ���$�'c�%�����Ur0T_�Z��Nt�<��7�.-���"�y��C�3�ܖ��]5���!��J'U�^����O&���"�<��fI���夃Ԧ;��"P-���w��v����
�١�_`2��*a`#Ξ<!Kg��%��-E'���Ǖ�9�R<���uS�� ��CM��"��3��*��_jor�T�R �R\F�_ F�bI/c�0&��dG�z�}�B}�����`��!��g�=��)�!���)H	�?�����-h]��%��މ�����cG����	�t���.�QSdRRa� l!Bؕ'a��F�������\壭s�+_�u��
F�E���͌��%�<$��8g�Ro�rv�_W�Z��7hi���a�����,�B���А�M�	t-�NaO�.څ�73������X ���8/u�xMb�o%�z�g��Pj�Ռ�;&g��WW�1q��E��$�/Y4�yW�hp�-5QQ���Ts���y`�{Z�&b#)ƭL���@vEܴ�p��	�R9tu3pHz}�tu��h>b�}ܼ��T/�Yws!��~H���v	Hn��n�Ȳ�PLH�]G��b�*%hZS�J�����6�_�/Z�
J�"X0F��Ϛ��P�*X�&c�Ơd��,�&,�#Z��b��Wc���$�`X!�O�f�պRtLqY�5�AV3�[օ�,e�����1�u
~��d��g�'	G��� �� ��f#�!�h���K�Ѐ�	0���	�T�����v!��*��@�95��m|�F@��R�|?�p񗟳O����ʉ�@���S�P�D,,,h���|#�rd`�%>�c��?�R��9�s2�"�(��dC�2d56=�Qg��D�����	 $�+d/T/҉]�J�7�E��	��$T�xd�(�n<M���%ze��_�0���Ё�\	ȣsd����R�daӻ����]j}ȹ�1Qhە(��tcR�E؂ lX�o��K?[��� �џ5kvu{[ѐP�W���
s�Ь����P,��he��(l�'��'�+[� ���SKW���Rxꅇ����۽v�6+2�ر*�L��o��G����$���"<Q�'k C>~��Mt��;#lU��J!��&�"���7�<�	����R#-	;;}���^�K������1�^q��H�JB � �!�-ʉphP4�g*Xȟ��}N���ƅ' XZj�$v��c�+b�0�X+P(�n��������~��_��C;z-R�;�}f�b�{���
��g>DT&��Gt���3 �v��i�5�*ae�;��=1��w��d�� ^�QQ^l��E�[�".����� s�)|6%��u?u�8��(R(X*-2d��ug	<�?�0JTo��lkM2�2�C�����P u�'j䗈�/�PFQ��L���W�C��a4*dk+L"�Ahe1a�$n#{eaRg#Ƙ�0W�J�K�ω4�� ��sD
��	#K;$�9�"gGuM7<0%��H�ы9�;��9�7��'Y&���	G9v�;(|�U�;�ǽu�WΝ���=2���=#��KG��/@��>'�x������;�t���N�x y	�\f �b�v���P���v�f
�p�|�$H�Bf�u"�I�
vvf:g5�Z����,��Ũ��K� �uӉ�������E��4��Bq�x�F�M }�q�9E8Wg���C}�s�J�M��p�B]�%����6����
�31ɨ t�@t�Eᢠd"��+��	B	���k�U_����(#�K�V�K>b������������BgF���j?p������دi����Ǹt*Ox��� q��~vc���;�
��	�@ �����Pq��=�O�x~Q��dc=`Ht$:�{2~�	 8��./	R�g�Rf.�E���Ea���dPe��S���Byo��������<Z#����jB0�x����7g���փ�d��Ë��[@;���[�>�u������t����	��wJ'�S�H ��1/�Å��z6�����R�� m9`��@u	9�}{���`��S��a�m�>$%xu
!����q��mC�[G�$��b�K��y!B�9Jo�9U~�밓�m����;%9�DW��B2.�����9�t.��S+�Jc�t\���e�����9���CAi�_K���@��C�PPP3�F=�,�4��؋�SWۅ*�0�9aG5��(Z�oR�.
H�?W���h�grF���E-��)Y��1���68��}�ĉK���8�8r��Q�ˉ�e���
,��t�M~S���H�P�
�l�gh,��U�<W�"��
~C�!h	���D�젽Z�(�n�Ph/m�j�@(. %h��P��P������4ƍF
�vI�ߤ{V�P�[H�3�E��� 5��)9>�6�g0�����vP�+�Ï�0���t��0�M�1h���w�e�\7�O/S�!+��A�ɨ�R�w]��H�}KS���)�Ë�+�d�"���']j�#�˽�@�(��/i���G��S�y�FI+���9����:]��	�Xt��Mu���f��'5�&�D��P����a-�F���;w*̑u|��&�AS�JhS��� �2���"�o�'Z�o��e~�`vcv��󤉽�Pf��A�)�B��lR]����A�p��bhĶ�s)e�}o�r����B�>C�7*�b%����b���P9����	��/�j����	PG7h�p4��hDR1�� �<)�aP�!c��E;\�˰б�=��)��[�co�W<݂��gd��F��V��8�����+*�1;&Ӫv�$�S�]�S�ie�1)�Ռ��`�uU��aYCD�V��9�tB��&i $2f"�e7�Ҧ�+��`�B̈́.�Āh}�S/�} ����©^E�e,��bR$V�����$�I����1�Q�
�H�F���0C�����.����PڅZrC7WW�d��n��-��xi�=�V-�4i6ԲK	u�zҰ����7Y�n0G�Sh��VBq��C~����kP����Z�t�f���mk�S�`7��0��
��|��YYU��#�lY���*�R���h���%���;U�`;9΢t����#���!j�P��\X݄`��ShM��h�j?]�G��u�W�E�U��Zp)�a3�BP�]�o��ӟ��7�I����v�,S)F��V�I���P�-���Q�P��@�T�AtR������EH�Vh-�7���B�<�����`!iRG�����(���7��hk�6qa��g���%$�����	[�?tA��u���1&`��@��X R&&��u�6�8 ���[���f%��f�PG�SBS��x%�N~�j$j�W�d�"��lM����=9ʹ�d�lJ�O�0� c�o��M/t Z�9Z��K�4Fu�@9�|�9
B@��.Ʈ��pvU�k��MB=�"���� >���I�eC���A[~{����-��;��W��;_IC��-_,žli(��s���X�q���u���C�"�/ktsl�6"��\�Pn4jT&�:k�PAZv��uG�]���h`Dښ���^x�s��e�D|�]�h�9�ߣԢ��[�X������O��N~q�y�/H�o��:j,8a|7�8�� �E'ݾ����	R��KY:�PPyY�lW��ua��QQ;lf;�f-�K�w`�HF�0]l��aD�0r�}�rh�9�أҼ0�ω�W/0�@� (�l���ju�p;�;z�
{  \�u���V�6{EC?�{|�R�F�����|4R��E�sIeRu@q����@�
�R	9�m�-���r'h6m+��HbS4vQ�ɖ��Rm�DRRm!f. $63dG�5I�mE�9u��PP�.��Y$��t-�%8BGJ��Iͺ�_�(�K,�p�t�~�D-����/ŲuI����U뭄䀁�R��:u�oɶJ"p:܉M�_��M*��D�Ī1��;��m��C0��a�آ*�SA���x��ь�o���u1��uc������ʀ� ��,̚;m���GԪ��Z��	��˨�$旑�{}����I�K�N�"��j�-�eD `Աv�����c�n+X����c�xX� ��@���$�ߖآ6E	ȈF�n��'������˷��ޠ��Y��~= b�@�~3�O��=2~#��;Ph�m42��$�n<��*��`�p�On�[6�Ap*�T����#�,P���G1�n=@ۻ�c��Ʋ ��&[L��93h�n��7�{B����V<+#�V���=�7�9�|!ݨ>S�	o"���0 l�֥�=o%�F�v��iU_�sd�n��s��0�Y�''�ؤ�
��
X���Z�V�:�q���n�
Ů�d�[�MX�j7�{��v�O�u_Sn�Y:��`tX[�
fdi�8`dϖJ��˟`B��EbX���UGM]�0�����	�J�t�w�o��r.T��`cM�o
sX��;l�N3�"��7�xZYh�|-�J9�*�ްb	�in+�֟SK��	� >�ׁUwQ�)z��	�j)ZIm9��~��2J͈� ����t-t(?t#�+T&p�"�5^YA��]�����Q�r��8[��x�	|+�J��(�@*��\ �4���WKx��d�HY|����QB[�`I�f�W��gk=��u�.$#�^��*�+5�j���x� ������A����;;L q�z��R��K�&�/n&0�s�%�Z 0%q�,�fKKKY[��NHv�����2̈�5s�����H��@P|C��0S^c�x� I���.乄D-rڴ�	�V�O�ײ��Iu��!�!�T	��{2zHq����DsMCDk)�b	�g������R\5��3'��[;5?��H$qq��u��@S�]@=� L��48���V�\:ʡ��m!?mu@�O��w�|7h��;7�)��P;)���é��s7Pj
Snl/���#�s�@�ZrD��	>��/��.9�c}�5�Ǎ�P�GA�M�PD��/�c@0�u	�G!��q�!�4нF���Sݤ��Ά��GT=ʃ�����v�w�5�n�?\>C��Yne��_���O60S�S�I8et��I�dF��B26�Q0���SVV���$�E�&jhr��G��@��gVh:`�W��X��L���`-l��`C�p-4�mbW��rn.���$@�LvA��a�m���ĢW�2�$xP��5ı��u ��a~�@u�*REb V%�����3R���"��$P�
txj�����D<X�Hu�1��E�r#-ty�һzM*0Y�4}x�C���e��F��B6
1.��%l���������P5s${Q~����`X�
��< l�&�4���H|�GO����LȵL\2r��HL%l��H&�1�HPV�r�����y�rF- �B{Wb�t�T�,k�k��5�����, ���T)��6��U
���C�W ��r�!"$,,|Y~5V\07U�a��89<w��?5AG��r�H#WXG[v�!]td,ew�a�hop,�𞿏r������]WtR�%�e��.Y�H"-P��.Jć��*e�Ųl��}�`�7hWb!kt�hG:Q8HLN"n,���W�3�7������&M,���k�vIV�J��s[����pJ�V8�BK�/V�� ��Hsq.B�Q�@.BR!Cv
xnmތD�[�ذ!s�fY�/t�USL�h�US�q����7t�b��C��I/�uBM<?�<��T|�<v7�덆�v=�x2wa_þ�{j��@F`��d`�#c�u2ȑ@E�uM�f�dd@�,uG��[���$P�� qT*�P�`	�f���\��"���ǁ�R ���S5�'܍`
�\Ԗ�+�$�ڑ'�JuY��Gs0/�#x4X���lO A�uu2o������u�	���mr�1�S�{4�[W��a��BF�m��S2���D?Z�lS�Z��K�$'	��x�3�w�M�QU@�MKb֠��ݖ:ݱ�y61��R�p�+>.ԋx�M?1$A"r䟠�h�&����Bt��T���3��Yw~��X؁V�RF��ϥ��i��0��X\\�	��\�X�X���PH�](&c��h���{�����D
����8�|����:";�6������ծ�u]� ��]4c@��Q �0�P&Y�,�S�ڃq}�տ��E��97	^��������^�TW��VI!��سF=$3���.{�]��R�Tcoz�䣺}���<3@Pl*F��Ug˶!A �o���.\wOu+�2�P%���R�u`Q]S�R�V��W3NƟ������X���9�|&�; -a(x���VtI�K2�u�H�%ꏋW����	�x�
u_�UG2�;lX���q ��,�C�&�9#�^+W�U���$v���A3T{ K�A�����l,TeF ^�~o�~v�?W�xh�v���ɝ�@~Pj@+	�Đw�hAfŲw(��K+\��Ͼ�H)��tcE*o�3x��<0�`�{��#�� ܖ�x�O۲�G<��"�ڵF�K$��ur7^�:�?�����#i����=[��H#�o�[p��e���q�E��eY����@�,Z��8�_�.�}�_�u�^ЈS��M����`��	RQWS�|�M`��t>,/��X�8E�u6��u.����u&��u��V�
a`zӭ�:@�����Fٴp�7"ѿ��|�HtTH=�`yBC\kVP!^���%@�@���=5�~ScU��l��M���� (Z!��, �	H����/gV�y���P��n�dCvs(�6�E(b�~G]�F�$  �R�#h_�� ~'j:�o(����$�ߧb�5ɧ@�	�����,�2�	�U�l���P��w	���w�Р����$tE�Fu�#�CtS,I� �PU�`�,��e+!�! c�!c��f��6*���zD�>�<�&(�_�__6�:��xQ`۴. ����3���Z9t6�[�z�Qm�:ct�;x>jR�ؔ#E>�l?�ǋ�t	,��$CD<f00�A~B7��s�M����Q*�<�Cx�Ѕ���}�#����>aƫ�0c�ed9��C�%!rk"�Y>�$0rT7Mzy{8rF9vh<r<�o?��vrAr2WXr([vJ////]tYdrevOhrnn/ovENptrt;�
ǐg��p+%�	�\���*�G�c ��A��=@�D�?��kb2�nS�Z+�����9�\�}�@�WfW<��񠬶ƶQ�`����Z�mS��f�A����!�J�[/�w/R!�w<q�,:VX���G�mÉ4$ľ�p0�1��=
Υ+�R%�v� vT
�1�O ��R�8ySF|YU�!�6�&��EK��KD*JtB�tC-Ԋ=>S��.�w,�C:�^��!�ҡ�����nT�P����=�)���p��	��\nц�y�	[�v�ruj�VE;P�񢷻�],�	���9��4���hҏ��C�L��	"��Wq��a_T��E|�f�3�D<n"7���ǃ�PW�Xޏ�͂{�rQJ���⍉Ё}�3a�6�e��yP�HP�N N�pZ,�� sk��'z5���#UI�#,zAGQ��W� rY��@�Y�i%�oY�*1[!���Soe�f��U�!�lp˧z��"K�}g��Z��gm��;7DL?$)yr�XZ$�K���h1����T�!լ!��7j<����_���p0P{�F�ߍ�T�v�v�x�g[�{�K�H;豻m���~2h}Iճ�E��g-���W�9g��6�8o]}�W��{�xKX׍�o��N	�f�f�Hp	����f�T�
P�Ow� ť�5V32Td�#A;zd�бw|�������x�W���t�� 
��m�[|�t�;�!?�5������5�����
� a6n��i�%���'|�i�R
�$ʋo�<�q��SI|P�ɓ�$�V�Sx�Ju2W�3�V!���@t5�#�ׅ[����1ɍ�>Ϡ�7`�L��t����^";5�t��t5t0�Ub�t+�D"b�O�G��F�C|5Ѯ� �2'���u��[-p��!�1fV'��hʊ����B�ԈȈ��
�Ro�0/�$�|I�T��h�N2L�����vQkL�m���t���N����C�2뤱���[�8c�%��\	�M~�^��u�����B[W<V�zT��˻ ��8-�y*lq`�'G�
����|�7FC�]�~�T~���9�ZC��V�G-h5z��ЀtB�iqÄ�V��<֏4h�|��w�AZ�$0�)"&�I�j��tb�|��`pll���clǟ�ـ�BVsW !_��QQW��3h�l���[���Z�����"l,�5Ό�5�"`;}�:":�Q�}�b���9��'�(��-d,}���f��u|�!kwWGY}�E`l�]�ɜo@%	��Z[Q�j(9Q+��}�z��5pQb�_���}�-2]MR���)��U����G�<�w���*)�yIO�!��p�+;YA��u>/��[_j<�I6��(�!�A~��R~:�`���*�����J�9)��HP'8�,�2$PP�(����8�
���b�W��XYhH�������	b�ˋ�p�Wb�9�S�)�%�,X��p&V�E����D�T�_mc0�O�0u��P�E����VL�mvf�K2���`�N���
 �!'�Q�Q�-�L�}?~~?0�l�~en�P�tX� /h�PlAh�ZY�Gp�[5�}D�v���h�-�ԗ�p�d 1:~?��~��\�U���^tm��B�Itҭ�n� �)�k�O����B'+C���HV1���b���M+�VRr�xz�0��~�J�+%�(E�3�q�؆��.��b�~Q,�qBYZ`w�Xl��C[8��3�R�^X3C(/H}���%�V!~zV0���#P{e%uWB��T��c�<>��?��V� '2t!�+2)E����0���J�]�/�iHа����LbY����jhX��{h�H�i)��Q� �H3϶�7p,�C�tG��;��N�<�x<s�/���#�4�ċ��\���fFMJF��C��~�oRӝ	�8C@i/�$|2L��"�mt�|�|B���[�6)9~Op��_W�^1v�]���	�z+{h}��$�,�މ$���v�G�b�Fk�$0�K��J�"������>��2}�V3W�d'JĀZ%P�T��
����A�����J��`�~ē؃��o�GaM���Nt6nt1Z�,Y�y�I�����!#���$�s�������#����,���h�U��B=t����]�r�[�J��F|�[YV7�����Էx��0Ɂ��B�>��Q?�Eg�QJ�M��o@[B&�������O$sV",nE�V&�ԁ%P�I ��	qa����u�J����)<��Y^��DG�%4+��^-'j A�#mNV�~*�=��X0y�aF�6C�1M>8�v��G��#��*ǡ�Z���K�P�	�\���03�G��a�����Ю����F՚"t�8*ޱ�tO�$����l��R�����G}�#D�-�n�����Tt,���J�R &+Ln�k��~��՝����*(���U���^��r��	�8��f��CN�u�$U��}�l��a��eg�b���f�00���`�E	��d{oc��  ��([��,X�ۡL �N��ZĂ����F���u�O��ܺ�<��v���W��{�~r:�F���t�3�� cR�.�.�l�<E�g/Q{[hNu�ZY[�ѐW�D`�4Y[ik����r[_{E��Xh�Xh�y@9h�9h�pH��8h���<��S��7�`��N�%`+,�RǫӬ�R�y��A�K�b�Za�2b�h��>Ovɺj"hÚ��y"h�!h�C�`H�o���r��炍� ���J��C���wth �h	�qȶ�h���+#�����(����HN�fW�pw�z��uY�01��˃l}j�}ϐ@�**5>�S��=�+q�xe�)@;�rW'���S �L����5�Q?�l�uN|�h�����#�?/%Rv.dh_Q� {DC�Z�h.���Z��u�tb�@�-Tp,�lQ��	��t`h����&����F�H����;�z�k����CR�*�ʜ`�5��'t.�p�,Y_Vi{'
Vk[���8r]u��&1̄���[t�sm���7����1����#��;4��"%Bq/�i��=� F��ɉ�}��@�/�`�Q@7�Sah�j�उ�2-XU����z%L����GX�k�ǃ�ecW����PR�V�S�����PDRCF����0hQ �r�j1c}��i��4ـ�a�Å�����M�M��<M1�ь�i�F��6��5�
�J>S]K�P�I��s\��{`�[��4�$�B����\���K�X7�\q�+�� ��ňR���d�W��e��<�	г#E�?8H���u3!L�{<���U$>� /@	d3��2�*PmP^��)$�����1�LƑ�'슥�|�"����;���Q�z�/M�Q��n�X7�9���~���Zk�m�A��K� �i9A(O~[;�3?hQ$�m?p
x{�y.t.떠l�B�R�l^!z�{tLV7��l�|t52%Le�����'�]��H�6�����OW�7>�X��ƙ2@<x����_~�-z2p�"^��7�O�*��/�dS��� }��#$�b|>V�VhK��$9pY*�������3�'�C`���@�WFԮ���e��V���&ǌf�W�5]MW�
]����}��X�`���"�����3��%�Es�W
G:��YXX��e�PxB��3u��r��%�j�a$ g��X X�a�4Z�����W��F��!����z		C7y�"Xl��>H�1���J;!x��,%x �90�Ʋ��0���0�B��ut�h���(,"<ZO�]��s;�- jV��HA��|g����ՀQ��WE�&QpS�� F�
DK�Y���]�z4Z�= Wr�q��,
���L�P#1���5~f�15ߧ�]*����SX�u� y��<Q���o�U���:_ f�%� �)R؈��Km�9�u�ͱ[8��f�  :���"6 �Mft08رu	'��W��#�<VuP$fѣ|�T���*���C�b��Ȅ?�Y�|�ngl]h�ŕ0����Ȉ�D�(�P�������DzT�4�G�$*#�S���u؅��˂e�+ت��3��	��`��70���lذs9G��Wp��vo]�,�4�R�� �`��
�6+	e�U)[�$�=;E�uBT�� BSh���Rۅj�@v(�6V�o�v �����$� M��w�%D�<���&�� fv�}�y�9|W}����1ō����8<!�$�����J u�܋�/[C�E��	 �Q t�p3�����j����$�*��}8�U�2�>Ǡ%��pdev�/�P�0@��f����.@�����hg�	���� cǮ��9s#3���A��pa%��j�scY�P�!F����e�اY~����s$��m~'!=2!/��~~h`�^�w|�e�Q��P���La�l��&��!e���z�Rz��QV����(��ۤ���|�!�Y^U�Q��5���!�"oO69uwx�,0'�[�fgP��F�vd�����/��p ���/�W��k�,;��6X�u�x	�[�hK���e��̲+˰�2�u86�F�?~��Y��-�ql�W�S�����!�'�����&�}_O���+�C{�V""�˂U���G�H��1cM��z�;�/p &/�À��*�@�W�#�&Zt��0�`�����Xru ����k�,��=�=����N@ᔓT�uA��H!��f� �3aɥ?�����P�����H�:��k�,J �A׹o�wf��uo�����ణ�s;�B�k�����,��$�H�3��,9�u�Qk�,�����O�k�	h4���V����nL�!A�Ʀ{�h��'h��\ɏh,�M���4��"8I�S�Z�0�z�L��]jpS�Ppx��S���7�{� �t6_�k�.�}����"9x�h�x�H�A��l�ݗg|��܃�-!�e���wG� O1�wL������@�m:O����=�n��=���0��:�7=�����Kb�����>���UȒ+��>V+������3a��J�d��
�F��,��|�1 �$Q��hՎ�K=��t��k��t�u�	�ݵ��U�;H,~��o�$�p�����
X��m�$	$w��a];�u�K��I��A����}����|�k6�H�y����=zɺ�`�/�� ]T��`�2�)(��������� ������&�;�P��?4�k\�k�47kWf���ȅ���v�nkى������'5��QL8E�6f�NхQj�Vf�X�D]�Q�̇|���Yw���Q�^!��X.lHhH��r����V6C�Y��ĸ�6�T4_v�U�6�s��M�0ɢ�W
�`�Ģ4�狕��ɉ���ȉ��� B)��F���[\����	����LB8�u9�-����q��G;��m�I�����
=_%" `�Rb��A�_�H���� 1�F� Bu���h�]���H��k�Y$����5`:GGt=���5������k����FdR�mU?z��a���B�����`��2;��N*�'?Z۹C͢Ց�ŵg:-,�-B����T�L��|�"<��)KC;8l����%�R1��;=��a;�G* 7<���tX�lC��E���nԭ�HL���5/4"�������=�sEP��P�LJ���R&#�SGr�n^R�D�����z��}��?�A'3�5Nk�5�C�m��	+��a��V��K-;`�y�SI�ƿ��!���t%���L@,���
�:��ξ�
�	��1j�jg���@�ҙ��QY�16b���-_j��b�ķ9�R?�Դ��N�,�Q����������%_��0��ِ��jAr��d�7Վ�ؽa�iz�ك�e��������S��1�\,�\�!v�S���-�:�T��}������oVx#;�ɇ� ��nD;����Y����&�9�	'4˗�9FMx�ޓ�B��/��y~�Kx"=y�SkB�=�R=�b��6�I�<�	��/�ANVV��^�����3���-	�~(H"��E��Cԝ�r�ƺ��$�B���/��|�d�[ȸ�^�-��;��˃{b�MӋ��gZ�r�u5�tF�P�<�Co�à:QI�h��=`Z��l{�8 6FS�2�+�9C�ݸAm;�ՉB�#h��g��A�U	��NK�����I��Rj�^�h��Tk &�Ӵ|�1���J�4���H��[r����H2�� �]��-,3��m��K��R�者ҏ� qof�C5l}�tp�X&�����l�pHWR4����j@�G+�$g�%���R�����e�p��!Ã<�UO�;��x�Vje6�O��&����lQ=@���G����1:z��%�A����l�;�)Ɩ%�����M1��}RL�^5An�ު�\�hJ��������K�t������a��T� ��x�x���+f�T���p)μu�(�+?�q�='P@�P<r�-�9?ac��}9�h�Eu#�&}#=94eu�8�߆��uΉ!�4�c��9ؕR�a�$l�I����� �� ���Y^K�:RA�4G܁�$��p��&�� lÀ�6�pzqk�w������%)�	�}?vPՕ�����#P�SEJ|��}Z;X{�[�t�R;P7Y�X[�/N��]J���,Jt+m�wu���Zh���1�q�i5��_���1�B�B[(6�	�[mHo8�Z�P_E3U�����`��\#�� �t�0��4�4 ����ƫ (]lY�A�����!T=��m�j�<9XZ`���'��u�T�	�~�xH��Ps	�
���B�))V��!}l ���{ufO�q�rYXjRR��KQQ����%�l'n�����rw���n@��Gh��Z���	�6z���{��1���x�xC�y�`��M$P%Wt1d+Qi�A�a�6{9�tA�j��
��f�[
f��� �����n70�R�SC� �%�t{���s��U��@��9��3��H//o��Mt#St!Tt-///htmtstt���.��	8<
��-UEv�AtG�cWql.�G6_3.��
Z��V�J�%0��t|L�&{�	I-&~� \+�&��B�Xu��(^r�憎ЂQ� �_H� �=d�nH�hO���%�q~��u)}���PSRHp(�`ah�ZԜ���t? #����!NK�~I�ϓ95ԛWW$y
*Vݞ=�+�C3h�[V8���� �������P�<�T`d`��Z�2�;�^{-9�#Y�:�v�+j��uh��i�KT8C�W����v##�	�����$D��X���� �b՜*@� �L  Ni�@mGI?ʞx�g(!	m��X'&��P{@����}�W+=B�z����B͡<�:�&+�a��!fw�)�WW��6�i�U���`吪)J�)�Ga��(6R�,���r�p��G���~E�4�ͣ b����<��،O	~Z�$��AQZ1a�I�EhR�Hō�Y_���6�@R� �@�� ]�H*w��=n�~��tK����+��\+W�Obـ��,�a��ǝ�Q/v<�K\RR����6KP:%�hD����P��Y9��,B��(X�Tc�E�\Ơs"�;��6֬t�R5�'ID⣕T�8 �<F��iޚ��QQvo��2vl���Yԭ�� ْW^�D�}aVM֛�%X<a2�;bHC>[�o���.��a,{�eY��%#��]��x�����o�%E��G�j�^�k�G�t��:
^��z�A�;�7�-�K%:T��6��@R7�/of��y7 �@0����|�S�g\u/'@���#���t��Q5h���Ӓ �R�Ұ��.�[��f7�zO~��~��nڔ�kz���t0&xq�X@/h�R�_�n`d�_X�oB���Z�ޢ�� t�(�vߗ�_>@���J(t'kǗP��6pP��[A�u��jʂvF;5\�|�m´ƉӉM�)��@
�? Plo !���t�
h��G��s]�-�u�_���]L�����?����#�1w�m��8����yYk�6���޷8��xk���� :=S;��AQ�!�F�� ���f�@3t�}�C�"�F4�;�������u%�v,ʾ;NΛ<xf;<H�H?�uR� �Џ7�6;j~�# Fx��J�#iyu^B�
�ë�;�z�G�=���nMh�g�49|�`��	�E��]!@�5kU�6����6"��u���
ز*�u�V��0�V+��X��W �{��p�d��$��2�mk�6;�@˕u'ְ	��y���;V��F����z���?�S�$Q/��M �
_͸�BQDu�2�l A��ΨT�ǌ�B��]�%V�Ȕ�9OY=A����D���'C���\*�k�����5c̍��37���p�T!BXѵ\A�Gv"p�#(���B�Q�b� ��_ <�P(i�h� L/G_vk��.���/u$�Lxk���	l�,@@F�)9ʢ >�Qjv�d�$y
D�i��k:N�At:JHP64�S �%(��͈�Mh���IW�-P��t.0�q�H��~ �O,H�P���� ���5�K��SSa�e,z�A��Iq=�ɘ$ٷҘm@���Eޫ\��XP��~x5���Ĝ��z rq�K�RC?i� NK��!ַ%�g;ם�
�IZ*n[�H�/� X_����_V$�1H��D>4%a6&�W^$9� �w�5�E�q�/W?�o�Z�`�6�F9ǔ	�]]0(��v?�ڠ~�~�oj���k��d�v0颺��h W�HI�`T�X�F/iJ�V�$F]�)�(A~t�!e �M��� ��u��_2Y�_XC�~�ZYd�-k�å�K�a�(���dߥ(S��5IљAcF�|8�����*�}r@�x����
j�[_�j`��<VQ����"�	.�9X��G� �!�Ü�Y@g9CfT<�!�(` �i�B}җ��DѠ_�P2Q�X>�?���h����r�2�(�XuRU|ńW!{VdB8a���[�/��������E��ߔ$z�����:޶�q�y�'��P����D#5
�
K&��_'	����/���~�hk�waF����Ճ5��[���(S���^B�L��o����xB��P�y�:�hdz�f|G���l
��6�=�=��>K��#$Pp-ep�gM""�f�D
�Ȑ���K�x���ۙ�p���@� ���y��f�>Zu8�y3�<t`n��F�v�<�|��&0k\����x��V(,� ��^.҂R�fSPR6�E�bj��pEu{����t��ݓ������)ځ���l�����:@{������m����ƅ�B���l�	���|���f�������-ܶN%�D'�a��u��f�#O{ɏ�E����(I�G�L��D�gf�� ([ ��� �@Ą̵l� {F�:@\��GD���dضz�E��HE&0>/�T6oo���6:u��QVCr¢�ܛ/O�Ｐ6v�@!]�c9�H@�>�����E��1�f;�A��0_P1�!h�%�JX���k?VT>��[��p?q�F�C�
T��VƧg����HVe��fT���ض�� n���xE#x��#h	�3Xk��mt5N_pE�-=9�F,����_FH�xഈa*"�������=��1�)�P�f��M`5��4��u�� ēX��b��?��J�,��lk���DJ�,�*#US	Q�)������2�%([�������.���8�APtpuR��ŉȧ��Fk�do�G�O�)So����;{�}ó�G��2X-0�Po� Tj �ҋ�/�rQu	RhL���rkdkQK(_+`_'���xT"8�Ag�!�W�{p?��C:P����voˍ3Ck�`�4ső���Gv���6�53<YXR���>Wo@�\r�@	t�A�<kB@f,�D�=2!�{�]�m?�C2��f�f���`��w�A�b o�2_)0� ��0�n �Ʃ44�t��a�PK�%)$\�ms8{6�����Y���UW�L�@�]6(8��sV�^��f��ϭTd[<P�Y��a��k���P���Nӵ(Ď���j(��#�ƖP��-v+8GK6�bwwd�P6���S0��} �=�!2k���H;8"���=�=��.�����H�(�_©�˹#�� V���eluCNUL:�	Ͽ&�\c Y�NLN�@��LL���o���F�	�3 �C�H��H$��ZYFJ5dQpWƴ��h]k|�_��`,FӴ
~Ǫ�rx\��m��6F��1���AM�|���dP��"��/�8*!@d����uӵ9�گUu(2 ��c	85�)��k+�'��ś�ŏ�^�	H|����b��ʳb�<��`�)$6S�l�`	h��
�@�/�b�Cx*����̜*�Z���`R^����'�u� b���?pQ_d:ç�^�U�[^��hS��1fVr[X�#_Z�7SR�:�_���>�y�WnE�\I�(���K�7�UN��dU��av ��`,�\�f�T1Ix��l�0/w�f@���S�h?Ւn��+5��g+�H����FT�c��/�o�l�LILO��'#~%���9��P	�⩁����%C#�hw�T]<α�� �9��Z3��^,�*� �b/NА��(�C!;/u#��Mj��.��䵃gŲ/�@/a���
� y2��D�)�{d�w�(g�/F��0^Vj��H�ל1~h0��<�Q*��E�v�%��XE٤�oh��c�!9���(�P��Aq����_X7d���tm�D�2�\td��|*z�YJU!��AL�U"+�ɠ�'ݞ���ط�c(���v�I%z�t��B�h��$�H�	%��-,ث�"�o�w���5�V�`��U���j�cͰ�O';�j��!�E0�I��3��(2U;�P��ao��h#�/o���}�(u}�fu_�����5V4U��m��D�A��7��O�x�ȪK~�O���o�O����@�� OX	���^վ�9�=�)�,o ��q�3�G���%��Q�BH�x87�#ď^;\zhF5��z�:2�C�� `%[;�P��J��Z�= ��\�i������gH��$vEK��lr�P��AE��/� .���2B��xL�PtD�u��~p����W_��)���;�(�@�nF�o��F�����^��<,Y�<y�o��F��k��Q?Bˀ;�@�A���ŵ-�k���K�qdl��u�,�T�t�3���������R�	������t>f�0؊��w∊�e��R�j�1�IW-)Uݨ���Q��4��!џ>����_�t:@ɀ���3f=<71�g7��)�-�~�<���I~�d�"P�����/U҉�I�ȡ�f�@�}4R-މ	ؔ-�	6u�U� ��t��&ع�	�s-bf�܎���C�mD<^�N̢ `[ QQv�Đ6�f	�\p���ݶ\�=3i����0Ο��|��j��������r�65���@�����Jp� =�H�v�>���#�����B�ሀ�@�u��e�� ���h5([bP�HHP��XÐ,�����u��
�nu~�����C��$N"��MO-���+�2���-!Z���T��w?nd��+2PPGz��-/�v�
m�þ gM�����P Nv�B�C5�(�5���I�o�h@l]MU~�J���t�!h+/D
�v����V� J������Cu������NLp��T���Т v
��v�wwvP9�wMENUt�A���PvuMK�gth���R����ta�]FВ�c%ڀ��vo%h�!V���6yk��	4Lr[�2�x�9�2�z�L9����<��ɒ/oqn���A�4�]T��� s�z�8�WW�4������ �1�
��A���$	�aJ'3��}|Gk������������V�>���;@���߉��J8����$�J��L�֔�b-�c̈́�u-�8�٭B<��u^/s	�% 9R �M��2��\�l�x���T�{��	h���sCB.T�,Q,Q��{��~{�Vũ��=��
Y���LQ�p�8�Iv�v�j}��6�bN�3����Rjh��u.m�6,H���f!ds��w�:��&��/���BD�O�CPҷ�vA)!y�٥�&��V݄�,x��<!9|�����q/�_���]_XZ ᅜ"�.�׊��.�t}ZȆ�y�2�lG�-TC4\X�� �k$Th��/r�u��,j9K��	��)�wZ��R�4� L.���Z�u�^��8��z�A�c �����M˓W%t,yV�k]�a��@:7?�
v(�V�������(����#H'��I\C�Ɔt�C&'��F�`Cx� Ðh7��@�(�l��@�������'%vZ耍��� 8Dv��=�4�t��v;ts=��@4�	VX�(G���n#x�7۶�r�#� |�ke������Fqe���0��+����t%/;	����h<$Lan o�<C&�熑y$o��vC��W�u$�;�QQI��aC%�Gc�^ pPP�����V�B�l�� 7�{�F`�a�t$Ս����l��1ɉ��J5����f� �U�.N��lҩC�H�4�E�ƺs0��
B9��.,��	W�+(�x�� �n� ��� 
�fK�$�[d�2%�HE�cb
���>A�ƌv��(Z+��x�\eJ��R��[@6@��rv�{�y#���4`��-��hat(�(I�	�'(���]$�&��p%/��٨�֍ ��5����5��Y���� So��\�!c���@28Ba���ht0"n�:���� Yb��;��C����A�j87�C�� �� -X�ɺÅ�)LlC�Y�	H����߼�ͣ��Į��v6���ܪXY|����t$M��닒>�)j�/�}�>р�ld���P�=G�|�60���Lhȁ�l@ȼ�W�bïW�[�z~���b�z~�q�˂��P�`RR�	PP0�P�e�}��J�Y[P�(s�u^�.f�Q<n�M������Yѣ}��s|�I�n��"6��#DlΪL!|U�^����,������	 ��(��h6������V�^��8��'��,:�+�%�]�S1�"���0��^Ʃ�ҵ��o�)�uld��(;~#�@ ��<=�if��!���DP�&1�l�Q={Q���jp8�N�H}� ��qo2D4"�8]���܏_�H C �v�(H�O0�B�x<J��ة�R�G
v��$�S^u��!L�!��Jp�!�E�$tP��@�L�GTH!�@��j>t)?( /��־��G$(�xH������m[�����;u�0'G6��=bC.�r;$OaSS����.�{gr34�g=����J@0��<ck[1�R4���lyn��s4Xuuf����,C&r��XbtT��߰'��,�LcH`U˃���ɘ� Ԅ��@��4��2��K.#��� �xP�����������w������n����Z�}x���}�z��JJ�A�J�	D,]j��QV
e)��A�Y8\uX�ډj����Y��>�Kظ\D�s]�}#��{%݅Y`�#����.��	���)� 3�!��f@)�:$~��(������[y�"� }����u	���sX�'����cB��� _t�B��(�-1G��|\�����CGM��'�B>'SЇ��䬣��/����k�o��搉,�}�1�l���|��7  b��ݟ��
ކ��
u����G;�#t	�Z@�4�$<�{#�}K:�
]���*	vdj=(@�;P��"���v��	X��ݕ�p����E�22똝�/1WC�a)�n�\t#s3!��Z����3	�/�*���b��]�@����� P�!�\wT���1�?�=������&����t9@��?�9��� <����C1^��a�=��
St[1��'[x�R����c�����5;����#����+������xݱ�?�%Q|*�Q��BE2��Αq���ߍ�{V��=Q�W�1@G{�=�6�7!��*0��;��hqb��y�ҙ~��9Cuy5*ȹ�+f_D�����HV*q:(}i���m����b�.tE��g'� ��S��������mcl3���w7;䣈S�5���Re���������ۋ=,��%K������L�=�����=�RՍ0Tí2-*e�hV.91;�n���t���?_�G��%J��kW�b �`����WShv�Pt#��ԝꞑޑ�9�&?���}FP	��u�������LGj܋UTر��<u�
^��S���,�nWw� ӏ%LA��8;@�M��Hr#E�T�5�w
]9m��d�9��h�U uB"H�^,u�£�=�zx3�S�P���ƜNR�{�f�ST�O� q�^��%L����(�4�-*wS[A6�	�@8wMHh
}�ߋ剀�:����H�6�"����n��	QR��NWWZh�Y3��$���$U�aT����E���p�c}?[�}��4c���RƖ�P�S[a�JC}�5ȓ@�W-�U�!�C�`U�Kn@�"CVs�+A;�ψPҐ�H�A�D��+��S��9���ۈx]�д�������Mt���{Qj:uzƾыIU몰��K*b�t�V�g�QK
Q��}֎}}�!E�u��Q5V҄������	Ѡ�<�T%��Q�^y�/8� ۑ�����#�^����傋����������ź�6%^��"��w�9y>���9����JnRU�R�
�9PM�Q)��?�E�<[<Z<�t�B����8�������n$~:08���
D�9`F�V,B��;lᡕ��Q�
Y�0!�ѤB�U����oUg�FYL"�P�~ � ��rH*bG�|�>(=�B�*j'u�j�x�-vjXl2<���v�XhEVG�,[a���,�JI�
�r1�-�Q�\�����Ȇ�$؞�u�Wj��o��Zx�bWV��!�n�
��!��9�Գ�m,��>Ѳ2��<,b�G�RVDM�B�Ca?�"�=����j��F�R�'K�A}Qx�(����,�ˊ�)7�=�B��fȎ���VP��G�H�@��L�F�@kJ�d9�b3��S>{#[�i$H�`�E�VMxQ���<N"�!�e����p"�@Qh7d(9=`M�S��*�Į�EJ�'ˮ) E�ф!(e��pf?��):
��� �͂3���D� 7+jqCh�B/|�T\Cl�?��zC�&|�U�a��`~^jzРL���(Pn��N��&������Ztzv�-��^N�H�?6*�x3�U�'((�#�z�i�����z;�J�H�����s8F�tn���m4*�<q��L��ݴ��A�Wm <�:�倯&�",�� E�H~{z#�Q����YhQu�@�`����бF��t"�&��������U�̯[�m��D���*�N'�7i_P90M���a����'�w��*��������9m�~�Jȃ��OAX�����l�GuD��Xc�X/���q�@~��u���9�g'�y-29��@<Q�G�H��������DoX�� /#h�yOX6[ u<�2�V�Ӊ΄��	�.� � hN��@�~*v���-�t²��bS���s�ћ��K�m���.���oKo�u�ء��	���Q�+t�
Z����㿿-�� ��c��;U�uu�X��Qnu`{���;��)�i9���u2���h�~"SS2o�1"GR<�����HC;]�|��@��D����(��%�$}w"������-��/r`ኣ�������R��X�d"�SA<��L6A�$3�!�dw�$W��Oj�?%�!�tC *tlMPB~����F�#R.Buj$��1��H�� �lwH OqH(�n�t[��w1��NC�.]_S�5*���U��#h6�RU�a�[�V���t$ˉ�R!#Z"e�e"X��vP�w��P+=�* }��t
�_O�t�]�	M������;r	v�S�5��bHA,(�b/�4.l����4�1F@�V�����&�'Y������|�x`^��]�gծ�G�B�!�h��>4�Фz$Y[�ek���"2��X�6�b[F�	/MUª�&�B��щ��8]2����0��!k@�:��:kpl8�9��W 	6'�.�8��d[�<)> n���T�2�l&�R�@#Y�;�Ι�J���(�c�M���.��$�$�H��t�)�%g��`�D����Mg��P�l8VV'X:HV��58�hjE�<W�d�'�D�kY@�J�6J��Z�7V8�АzA#��b�]��}+!�j�'�#�"U�P� =�Ȳ�B	^2� pW���)��!X�ⷜu�DԄ����0�o�g%9	��2���C	�0[�R`Ί
���8����HGt	-�j}��F!�&uۀo�I��ϟ� �w�H~��5:O7{�iRGGF��R]*^�����X��ŶQ9a@�l9z�(��W�pr����b�.�3��ڌ��<1�VtXP;�JMpY��
��H@��rP�D�  �NiX�	��l{��=��#0���A�!��v@8�hI�#]+&�ȵS���\�1�Mh3�����U@nV�=5�RA���$��P�FSb@ƈ/uQ�VTo�TLm�<�}�W�54gumU�Z�� �I*"��VP�g��u��HV쑃�R����}q%gDs���V2BP5E���!^h�HuL��?�M���Q`�������-#އ�x{O���7I9�uҋ�KK��cP7�	�� �k�C�4�6"B?��u�R�[� \Q�+��RWX#�O���a)��\KZe(��}*v���}�B5k���9�~|�����Q��+( ~M������l��ѱ��?9A)�	6���xBi�6@~���!˺(��wSч�=��*=��U��#=�ms����=�m������a�m�@���D1t,����t't"ttW ۷
:�3ۡ�Tח�����C>uE<������u[�\�E��t{-�:��x��n��@L��ZwP������Y����@�ӈ�����v8"�0�������X{�"M�E����f��D�;xPw�Q"�XSӺ,ƏT����)U]�7`n��	t�H�S�1��V��d������u08��"��ɔB�PBU7I贆�\D�,U�䳌�-|{��1��u���lliu9Z�%~�#����G�WB��S�1���lͺ߱*����rDt|�52JMB5XG�u�� ɱ^F��PDU-Ò�t𩵈] <�bֵ%� �@���d�����3��� �;�{7�}	�
\����_W-z��f!�ˀ����W�X	Lv��B&�����S�V�/�CQ?�}���p��}f.��E� [��A@�0�[|��)���@��V�m�Z����+{�O��<iG��2��)�P�/� RQ�)'��M��$��^�A�0�u�(��9F�͆�%V���H,dV��X	
b��͢����f5���C4�)�#�P+�X����8�)������J��[,��%��o��`%5���-<�v h�3&�}���u(�H<w
������9��E���ɍ:6�S3QV >�m�����RP 3��}��#���j�W���h�!� xH�����[���B	����U��$��Wh�bF$![O݀�*���%C�G��EK���P�4��`o���-�D�"�Cף���z��F�$�K���@�{�*���� ���A��*FP�Hį��;�d;�T\Hk��U��ViS�g7"Y��jrZ�+��Y�jk)�ja6Z��j�:�A��>u-�)e�>��#�������T�ۓ���3U���F�E�~(�� �Y[�����H��\��J����u䬈�m�o��x�;��aQ�H�vg�dLj�SPhSNE,�G�'�&!��8Ѐ1x �Q�&D�u�dp�5�:T, �	;@�S�� `z/���E���	~a4+2��V��WZ��D(B�!U�����#����U�S4�ƀl����B\��8R�~8W�<tZ*~��@tɘ�9��� �,�v�4��N��*�Jz5���u.��D�SMc�@��}C5��q����|Sg���������&����^�j�"�����(<��5��y�@�D,��T�ۜl������ (D<x��B�����r�B UG�P$��I�����|
���Bp<ts�F&��
t��.}vC>�z���PQ�/�F'���?�=�kZ�G,���nWCzW�^P��钂1.�3t��RA{�M�v�U
@,����� �2f\v�Q&rM?�]Aa	& BE��3�U�E�P
����?Ua�R��	R%��	��+~ƶI���E.Rd@&�,�(S튨)�f���E�*��Rb�������z" �T.����A��(�M��M�86�o ۧ
�P�H�@��K5��������~��R-㒈 9Y�	���!h�A!V���i{�� ����g(\�؍��(:R��Qx�,����ɅAx�W���4�3��:'��T�ڧ���J�j��Rr�I	D?(j��~�?�լU��yI/�7�����sS��F��Ԋyz2 �A�z�O@KB��t����5�=���CRX�A]A�����͵���������U6y ����(@Ŀ�����B�	.	V7��I�;��|��<�d(��e����6���(�?�I��ǮF;@Ƹh�P�W �S�%��[�h�kC��4��>����/�����
A=?B w�=�v,A��b ��q)��!���AD[5/��pwM�Sz������ ʚ;�C0�:���9�r�QRln0�[�}'��3���4z���6��'G�?��b�4��5�U�5*W1���,-J�0U��6h0��:l�'D>�Z���5�,���DLۉ
��h�����<�bx��W��/Y��\���pz.��W�$�&7]Q&P`�@�y� �u$C�Ö�A��� �sf�<���!��6C"#��z��sX��z	( �W`׶�D�~;,EV4�0�������7�.	�6�M2�%<h ��6tZ(>�N~����L�5}�C0��%J�G4���~�H�K$���{�Q��S�j	Q��nɅA�kBP�$��X�~NE����|f�P�ЈT�f���U<�uQt�/�<v&���٭h"�wP��zq!������i������k�9�}A�zs#
��[��[�K���	�� �QN��0�
�Q��h�)^����e�@�,�%&y�(�v9�s��k(����e�j���p��s�*�����f�M�Bb'l�Y)ڀE($T�����~��� c	�ڈ̈5xF&k�ߚPK�Ѓ�v�/T�
�B���n�B*�(x�bǈC�WD�b<\�B|��n�Jȉ)�z�+
ыB�M9x/D@�i�p@��^��JA�bÅ�K�zk-x�����B�mt�	��
#�mo ����;v���X
�EC�r��5�B�;�i���D6��,�lLF�w-�]y;�ؿ�@����[��+���_��A���f�zU�*j�/]}�B��[aK��`��Qԁ�Q�W �s��	AG�Pͷ� 	��cۣ/�;Gu��� kR��k0(	L�j������w�&�꺓YQ�
'���F.(����صN��T�[O�� �vW�/�C��@��x0����9����Q��|9���٣���#T�h��ǆ�����~C@���X��j&)�x��B���G�y���c�1f@����ٷ���JU�8_��C��P�P�y}��Bc�(uE�����"�����xF<�+X �m��S������Q��f�<�E�C�`���u��mĀ�К�M1�#{늕8��v��u���bnR�gbld�}E�\��V �����-���I�g;+����� ��D��G�[AS������Z(�eSWr#_��@�.�U��05"hA
�t�~�d	o�v�}�;K��!�A���;�P|�!֣�5����� ��ؘ�B)���C+�CC���NܟB�L���'\BU�-"�=	x �}����K���qp�Q6�`�R�!pX����* ����h(�R�)�PM=3�����Ö�
	A��D��pG�� Qlx ���4)�R��K�ߍ� �|5���s �6��;+|j_��� 6�u⥆���
;�ݢ�BvX��|
1~��ъhX�eK�dп>EІ�
7��p�>c��t����R��ĉ�,�J�5g�ey�u�m>$��9G�~�VD#6"������!��������F+.�-H�&�Β� tV��J��B���_]P��\�=��N��QjLAp	�Vg����dB��zZL�������W��3�����V�  ��,h�Mh!��[�ExP� �Ö<,�`J6�*؟UL�ZP�I!�����p�<U"�Z9�b-�5v�@��u�[�' u0���El�Tc�!P;, ��x*IA�A-�����>��/v�܋&���2ŋ{ �9ñ��͗�+����2����N��u�8�V�$�O��u}��9�,��J��M�8�,�!��/$�~��,��0�9�S��E�[d�#h,�����@��s�ʸ�hNf��3������䐚�(�*��� @���� �,�����A>�+���'DD[��i�Q*�-Gm�`�zM��
�N ��jA���4������V!+��L� ��Djv������<�MۍK�6��F�w�����u���^�LL,G(��!!�ܰ����`��@k�e�}U�9£�5��gq�.%�������`��4¡ v��.eD��
H	p�5P׀��@@�L�ui
��,�+�]����,8OKkt�@&d^C �5
b4�,��{�f�@e5Z���60uL?%���
j����@��"୧%�H�w,�}��l�b�^�Mv��	yC����	8����F� �r�jx �DV�W���8�ַc�).x4��瀻!C�% ��VbhɅ��(\��	�;Ou;SVj������eu9�u���n�U=��n�����	��XE��z��"�hi�L��HDh�����0�1�
���)z�{���!4��
��� q
$�l�w��4���b����w~���a�J	��XvK>4�[�~FaO5y"�A ��<t%_t�D'r}�,<(�����t/��"���]��l��àp#v�J���>��P����~����b�yq��4�S�`B��<�Q8���ݔ�� 9�����A^H1=`0��@HR,��&�
�I�;����#Eg	�����7˛��ܺ��vT2�(Uo���Çd%M��BQ�l�''[�8�3L �j�7���	XBwPuԡ�������1�=�T���5s���؂�}3����������y�Z���!�n���!�	�]�)��5h#�@�o/5l�Iu6����}k�[0U��
u���/�T��ʌ���n �1�1�@l� �"�kom�@�F�:E(u�Y7��ddu<���ܼ��߾!�	�#M"�!�	�\�Z�M�"Au��(�B<T�-��:�7�ZkBN^���\��`����b�p�1�1������6��J��6���J8�8]P#χ�=<5'�B�����"lը
z|�EP�g�8� Z����	ىbS��[��Ɉ�P1����s�	�&���%��9pK��&c�������W�\���)�9�}�5l	3��d��X�1T��ۈt� ƀ�@���B�8��
�H�,�)sk�sp��������oذv�8,�8)c�h��r�%���ʅ��v7p��Z[��N��gv��Q�ИX�M�$�ۿȈ�BQ~|���]��0�*-�0���Ƃ��2�F+�� �3��|$�HD,�rJ@�#�����#����CS!\�Ȁ�
2F��u�ƄM���,�tџA�Z�P���F��5��YX��Q��(�X��E;s��H8N,�XZ��H8��(;�@P�
+�h|���Y�r�-�&�R�G�A*Ov�s{hg�P*��ɢ[�u��{5KQ4����!�eÒ�SS�� ���*��N�F1�$"�'ݳ�&��3!|*(�5',���!7#TH0I4 x&��s�U0.2[l�3�:4,@&?e4?H�6�V�ɱ$�%���Jv[1�޺ܶ�JM�R�9����t���9�U�������;���D�dHS]��Ɉ���h�u�y�}���fk!�P��E�+ڙo���D�Ծ�HPuIvL�� �.�Ǌ��_�.�bd�0����k,�B�T�m�x-�
N6h7�[��0�9Q��PWT�P'�׮�����;rs�W�. !�@f�4Xo�zBK��]˜�Ay��_8���)Q#��ʪ;���M�+Xꗪz���G��j�OTI�����+E�ְ@�ECЯ2Uk���v�B�Nu�&�\h�a��Ѐ� �|�~*�h�0󅮢+ 3�pPh"���}A� t	"��Y /i<a@>�B2+ʢ���$Nz9l[�;�~.0"433U�� W�]��8NF��5xF�jB �*��,ccm��(6���3���к�-lKV)0��wо�B�"���"hf�&�!�N�cX~*QP���f�uM���t�5���a����&�F����5|W
�w uW�c���{�� R�t'k�bEI"h����nf���h�P�%c�l��_XY�A��z7�	����ȧ&;��K�,Rd�P;�0v���8�4I#x�~)�')L��f�:BMOQd�"D�*�K��f)�f~uj0��I�
$ډ�&
�nD�@�E��K*����f�q�lM�Kd��w�6�$ ��B+B
�*W��(��5X�u'�t(�@&nra�&i`ï��v�\���l)��KC۫�Ȼ��oI�z &��_�;U���e.��Ӻ<C=8�Rm�0�Yc�p��tr,P5�((M�4���Z���fy�9�ud���VOuf��}�0u`Sj��.��.uCpCq{�E���QD)d@Q!KX�zD������h��A=��zW�:;�G[�����'_ZSPGZY�T�q�c��8�#RS���%�I�'Q�jU�I�A(��d,��a�����yC�� � S�"��|^���%�۪h��IK��*wH�$�,cP��-@}-W&�pQ�����ĚA+���t�Fə&���R���$�G���3Q#��V��A1hb~��񓀜[@1�r�ba�W6�Vk�]Nx��5�uJ&W�xg"�Q %ޥMGYt�	��J�f�/�t��㲪��T ���l]@,sGhL�+��Q�y�U|ZR�"-��<4�t\ �S�U��	�<�Av��*WW��H��.�G�˼����\?�˖ &x�/���t�¿�2�� �>/�@K�
[�!����#ݢ���D�U�)Yb�R�_2V%��f��B/^yZ���4�}�o�dXr�E��aTBX�V��_XV.,�]ɹ�`�C.�c���˸Ԙ	+&�T��05�� �DI��ˢ)W�%� -�����P��m�pY[�4XZ�IN�h�^_��ѽ��c&�[��ʈ��6pګ&�)	̩�'>~1��]���˾]!�/�8"�*ƮV=���(	Ŧ�PO���Ct-L/b	Q5��|��T0|W�5�6�1��%��,�snx�C`c$���e)×�N�|BtHt��K�O09�!�C����{���B�
�(�N"��&a=ߓw�.&��6"�,�Pl~/G���.|5��I�cӲk���DtPG0G�j�K��E�0W���H�|*���:�w�" _�<,$O/3��
C�8890V1�9I ���{�Z����/gc��g�N~D �v�Lr�O҆ͣ���7$c�1;�;�0qxt�J����p�B1�	�x��f�w����@x��xf-�Dy��Q&y&�g6�4����&0st+Eu�~ۗRx�f�,�I��S4oM�^��0���g��2�h[��!��"Y^ͪx`?K@� vde�w������W���xVh�3T�h���C����.?��6�x	�c���R����$U�e	�c?6�E�+(��=�T�*�wBAܾ�VIu� �uM�W��VQ�%���)�x,�="N�$���>6;tW�4k?T�"�C;����C ,@�P���j,C��C����OR;��,OWW;[;O%�Q�([�M�c*�(f���PPWW�G�d��NV
K:*8<S�(��SA�ړt0�=b�yv.|�l�L�5.!�/D�f�� �˒K���6id�U����r iF�0 .���-z2.��*��&���ΐth�(	(ɝ�D�&T$´��!?C��&��0;`J112�ILY-�#�M����T,��^�d p,/���3ą2g���%@���1l� ���a/����G'4�#�4��/}�ge��Xw�&�� Vn��hU�@Ќ��
�dL��`	�ϊF�kA� �No
.�Iщ��&�j��7�3aP��BWu��3S��Sq�{�����u���pFj^Z%��,��͢F�d���^���Ķ[��fG�T$����L$�Ӹ!]̀�#�`=1v;�����މ0Z�@W?%���&|�	{���<[��;߉8��d�e�_82�F��=n�iB�ri���VDf9���/6FP���l�6�W_�t$\Q�>6'�EDF�9>dB6�Edj~�o?~�|$ $�m���$�O(㜩�6(�/T �Q��v��LE48�ۭj�/��$�uw�܍l[0�$4��x<O��hø��݉(V������Q������Rt��]{��!�:J��Dn�<t'�����|A��t9E�3���F2��b!��s&���
�΅r��WV�K6<�t)D��@u�AxV}�(���]�YW�]�\W��hA<Ch8D�"�����;f�C�4�E�;CU��X��;�.C$��	&G�L��<.�Bjb�f[W���$Mdl��K	X/W�e�5�BG@�-;�*l�
dz=�A;l�
j�A�ȕ��SW7j`��-nB��F@UG�J��X�W\�FX�V\*eY�em�T�UG  7eY��$,0,0�e[�4488<�eٶ@@HHPP V�t^�X׹�]�m�
��Y�9��|g��,0� ���͂(0|��p��>�U\@ق#��p}�?�x�5� ȁM��*P9���Z36��ܠE{@s�5m5 ���:X,$�z�4��
n6g�t?D�?8�Q���$L�)8������1�bPUn�I�x�j������,���OW@5U�>�u��x�0&�"
�lN��F�e�Z�DkE��|w�	�� ��v�}����� {���m@��ыaPE��P/�l�L=/G܆����>�wo^$�LPo��n76;w#�w��|�W�8p&� ��'��GB�wDVY���
�Z�[�mPŹ�_�7�E� ��Y��G�������E��@�_�	�����k6A0��ڲ�;X,A(Vc^i6�] 4c�=lP)����_*��3�N�E���9yB$ō���g7�P<s�XZ}���a�`,sV�i��t���-8h�>�m�/����u%���B�<	��x�Am�_��1�k�
��nw߶�2�*#9�r<��~����ō,8�9:�AJ���N����/��/ɇ���/�3��<Ǆ$�  -�-��p��������c\�զ�t�1xF�Dl
g{U/T�e�|t�)�u������$9�o�~�Q����FUcЌYxǹ�m �u/p��-9�m0p�}� ��0x�P�)5��E8@߭p:u����5W~ÀP��	UjDVW-�)��{����`�><t��~KT�F>k���{x����M������L�EG�S�~'�ыE�PЃ��P�"ؽ
ڀ|At�Qt��΀�+t�-t��Ec��g�8;"�c8�����&&<-�e�/"��o��v��$��+���*��G�>@����
b�?�X?-u��ݱ�kT���rm�Z�hV:�	ڣ�����[���E�ECR3�0,l�$y�w"i���V22 ,o���N��Mu�^ 'W�7��JmN��%ߋL�rv��/Th�jf[�f�BZt�V�����}k�
%�FOE��6�	��A3v睙�5&@��/45A1�)�;�����a���qa�8��������m55O��0܈�2 �/uK�~r�w@l��v5���D�dlW��A�6pPNDm��􋓨��wG�F���߀���l(� x�k6�1�'�����ļBDb @`��u=�_�f�$1L FT��&��8k(h�p�����:�+8`����0P������o����[�e0HW���Q�T���l(]Р-ut�o�*�H7.nI��s�^R��~QQ��tL��'U�A�<��ow8J�|.�%��,���R��
�U�B�1뻷J��dP(���5�I,�h�y(Aoc�I�:�|ju�梭�)B���cXB������lU��r�z���'�Ȋ*�d�ȉ� g�P@yP��,-��9�w�D��"Z�/{wV�4,I�E�4���T��)ƺ���L0�]�t�5u��K8�(%v7�f1
n�fU��D!���$���;�H��4�c�x��{�n��#��oz�A�k�)�1�[cb~��B)Yw����Rz G�-�fM~f ���v/vȺ��)�ױ�~x��^F
�,;*t��[|��G(�ƭ�F�f���Vn�9TuGi@�Q��m�E9|��0�a[
z��$t�q�t�t�} di�HfFc�dL���,�I5�]�;*�E �K�BLU("��@u�u��i'?'/d
�4��%$���wF/G�%�Qy�lS�B6�U���g/�
�bf�����' `�0S�}�M��G+t���|!Qf��;db��� _�l�5rh0�<>p�jwv�5O�^��d��J`�V#NP�X��5�tk���J�_4��~�8e�4ʉ�07�6.X�P�lgO��0���`7[�GKJ�[>��0uoH���VJ.Prd����<�l�
TE�W ���5>Og!^I^KFv����c�3 �����T�Z�u6�zM��t�tK80�4���Q߬s��m���	v��8\�[��A�S�%� �^Pw'[�gW2S6Ɨ�v"�ʨb+�<j���%J�W�Wm�<�%��[c�8�'��v$C�2�1�Q�l��L�W2�0��=K(�:CYT�("(0�i,,ֈ̀A�  �pM,S�G[��А�Ptpf�0� A���@�DHd�LP ��u�;n8� \�nd��tR���f@�����m� ��g7�]�p(
,0q�8�a1Z��DD�d�V�����r������ �^g��A6��N �0{^�l��R9�g�7Zr�v1M#T��� �rP��)'6T@� �UW0�IT�X�O�J4т�5�g��"9�6�W]`�\@ �G�Ud�
��o�,�B&,�����i/;L1�Ƌ.�u�J7DT�T�̃t�.y�y�s�A�t��A�gyy~�j%�E�xk7�A�+A�,ۋ�@�Rx"}��X�@�T�+��(�\r469y[� �1���EyE*��K*��%�,�@���p�T�lQ�_�	rtC<w�����>:<a
/��ҋe���E 	�;�5d1��cx��O�B3bt��ޚ�P
x+�����Xp�����x'���T�6�2E��C|d��*�^j�3��c�@L���K x��E7(��iSB�!�b�cP���xW�)Ņ�t��(|�XX`�(yϵW�<	��V!�=`�P W�n���e1�-e� 7v�����a���� �uE�� 5�8O���`�}�D&ܕ3�J�>.񄲝El�VM�t@5-�� U���Z��k��E���A�ed�(�,bl�G�0P4�E�C@�����]H�t鬅�xW3��ZB�#%��#!�]�Z4�^(*Y^Rq�96RCZ���X��,�7	7/R��,E��j�K�-,��<+��«Q��2dke�\1�&�F�	�t(������c�sؐ≸w�g�M$jXb�\`@�%"�fS�+�C�1�X�]���*=0H�L���C>��hE��0�F �������FH�*�Ջo@v$��J!�O.�V6�Q�V���tF�St>zI�:;��OS�E'�kF+t��υ�u;�bu	�X����0d�@B4$��nc���"&����&���j�{fV��>W�_V~:��v�C+9Zq��)�Ē�Y)��=%k"襵6/�' �x�3:�sm@h`�dG=`;\l�%p�T�0*��0��|��t�Dh��ॠ��I|�ZqWk� �����B�Mnŉψ�7ί�5�$N�0RU84M�WԤ�k�)��[�(H=y������[��bn��F���R�(ߝڀ�" U|��9�6���!���J�Q:h?m��9I�V��V)8���<�(V�*N���,\�7��� 2��v(��\sR��3`M(�0Ǟ%s��{P�L�LM�W� I4�B�)�K%u�9�t*�����)ׅ��7�R��m;�9��q������_�V�~%k�-�h�x6	?C�h��^��,Q�]@�&VvF�m�N�0p~k�$����uK<؉��\A��q���|�@g��*�'��um8%|��ih�h v���`�����=Y~���z��
tC]�%�W �0����`� 
����oA���,��G;wڳ�h/7�)��I
��wE�)Nx� ��;
���b��$�In?�j?G�	��D_+D칦L��
w��&8��@v35Z��x�EvR�S����Y���wt��$�Խ���y�$��G����6<�B�="w���� �K	��7.9�w�} 0�:;,D��1n�~�@���m0�|�pbxZ�w<v�n�1
M���)�[ �I<�1"%���s�*��WWS��ʖ��P0�<$s@'ux��|Q�cd����^p�8�`�Ou[&ܓfyZ���kE]�Ɋ�
e�O�ypQRR���
M�ULuݡ��ً�V5[�t4t�2���U��;xƄܝ1�k-{wq��*�� rA	�dmH��4Fv�+[,tψPd��,��)�Ax.�"cu$�.�l&��Rq�ёsLK%"oy�X��t����;�2P)��`��L�������AH�)	��Dd�.q�A
.����M����v֣�GWe7@t�I@� ��̊�'�w
Ƣ#^ts)�&X�ׂk��c��
�#�
�p��"� pج.y��-7�k�����c��}�K�0>��kȠ�����,P��Nu0�U�c��Rx��	��|v��q��mR�?��&Լ�bV�uo�H4)ǂ��
<8uԔV��A�D�����0��|/�m9�t|Oh���� X�N�>�½.(�z�z)z)�Ju��n���'�(�&@S���%t4�נ�0��hg�M��ING��0o�#�B��FL�~�~'�~��0;'[RTs" ?Xmm�fW�qyP���2r^�y.��ѥ��AL�P�QL�APS-�m|ۆ�[s��(yi�
�)�}R~P�?��K�+=�tB~@*��n	=�2�K�ݼB>F�R)��k�=��-3�����>���"/!�G;y|�o�a�p��$k�_�.0��%�j�$1%�؇���"�Ia��A�.����^Z� �jo�����i���0t�
�]jvw�	����)�%�|B��+�-H pt��TXu@�1�W� �j���p����Q�V}`�G#`_��o�� ;U��
��D<4�b���}�;�c��*���v�8C��S5įh����:*t^ן[W���T�z9ʵ�x�h����-���rk�
<-� mз��@��sz�"g�H���oIՀz�%�`=�$E�wQI~,�W� p�m���xF 9�~Ǻә� �&(~�ۿ=mtO�09�vݩ0t�'�jXx�7�∹&�B8�� �G	���� �_������
�d!ŀX˵g�_K��a/�&�t�?$-�
�"tG�p2=�W+��R꾝�3-�7.uG��`�0�\��ٝ�!:�^�B��zo��p�����H
��	G�Dr	��6�X!?�Z3�7dͰ~��V���A���H -����B}9�����{#��S�		�S��`�A!\[��t�6�4��HA.$C&�()Bւo[���0����K��J
	��iBw���Grmu N��c�]�B ��0$%�:�3VkPP�"D�ș&N��P L�b1ґ�)ܖD�#��.gP�bǐ���C�Ôp��Uu#�
$�z-tx��~��P ,�M�����("�l�Tϖe+�>��2B���9�t�Tuf��9�q6Lv�f�M�(�E��]���}2�b�Tr?�@&P2��_�t��1dP�(IpI  ���0��y)N����h��|c޽v ����#�uBA3��E|�|9�Sc`ct�4m��e٠'48����<@D$'Ms�PX�&s�h@80(54��ϊ�����,"�0��|����I`��7dY4$�$�R7)�7�fla��c��K@���Q;�R��6tIo<$�$Hy�k�!�j�lƂe�h	������~�0@�]D�j�jM�	sn!:f=dޒ�K�QO�l��|�{�@rQR��@n��k|D�� �f,��m�kd�S��ud�x"sl����>�aW$4�jUT|Q�MH|ARRq�KgF #���4-@x�lu8́o��� �Y�C�ٌ�$h;��)�ΠTW���h�H� >�i2�8oHٺQ;�����9�r �P��%0�$0j#x�g]
&�0��w �ڪ< >R@�������@jp����)U��J�K80����>�i�\0;�xgM<�u	�
�q�#Eej_k���I43�?|E W(���2�nP�E @tz�A$�{�u'�bu�f�����5f5@�@k �I�U��^�m���e ���]�Ћm ��������~�RV@�:N6I2�fj���l� C;�A][6�aK�%9�sV��m�k�(��¥h�oEЊT�8����U4��D�����xU9FuH�~��g��_���D��2ك�譭+t%�ͥ6經x.LT��Q�-�@P����&����Ql];���U�T���/z�w��D���e�B8B����@�hL>_
�$b0�$D7��,��� ���Fۈ�
�Ou�%(B��� vWD.�-k�+���9BS� P9Y�B��5�@����$����U���tlא��$#�#M@#<uwab�Dm+��mD�@�¢B�dMa{��a\t5��!���@ �Ne!,@c"41k� 2�ff(�1�A�DiW'��~��?m�<�wI�����܆W����<�D�R8t4Q@9F��w���'��"E�� y�,�P�u]P6�f)
A{���DnOO\=,x����ʴt��f^+Bf>�H n3*�s�k�:������oXl�'o{�/C;U�R��c�O��\�_��co��Ĭ8�t	����H��H�?X|4�+]��p�X.�FA���0��"Z��eq���2ؿdO�AItW��{�K.*	_��,v�I�b�����\B�L@J")Ȉ�{CB1�/��]*�N�D�/?�U�#â�4�t�FA9���t�)���8h6}�HLLaPwFr2��*�(.��r;AF�kU"T�G��A�.������ p}�P��W��t1r)9�����������j���Ų[0��#��eE�1����/b�>���Mҡ��9�u]�y���*đ�`q��K�R���!y4��QQ0�,G���9uX4��o�l��[�X;��q�:T�2m���,�ĺ�]��)�ʺ�`�`���Pr>öE�zYݻA]$x 8��)��}V�o=�u��y:�J�B ��.��I��{?LS�`�u,a%5Q;:(�Z��@��=P�
��	s9h^���X�Vr<���1�>0�9�>W�]���*uqnC&k�;('$�"
�;�2���h[�b-$�#��^����9,��"(A��l��йq�����0�	���]M��	i�L�5cG,eP���� �m��d1�d��u���k㴍�8��X��8���B�
���3L�K�G���3�l�3^����Xb�s=NF#nsrA;u�?E�\@RmiV���(�`��F��+
��n�h�l`7t_nS� u��u�Q�k�E�y1A�P�rf��n�L�1)GWUu�L�hjA�Dm�u7�p�R�&&Z�a="��Nlˈ��DslC��"�Lx��`���|w&�,��j��?�� G�>
��CP*¯j��T�^�g��x�]�:j�7PŔ�=ĽϤdfPW	h��K�R��;�v����"žj����pD:xߔt�D0�H��Q,E�R��ˇ�����t@�
_��a#�t�o(�9�n�Gp��GB	�9���N�]RTG����:�U���.+zL��UV_���<E&~�<�Nj2������J�s�`T'��#p#�{����6�T���R�D�
���O��}TTߋ:�d�`V�s\h�!�8H�Ph�
�ǉ�9t_�u�C��3F�2[#F	D��-mƈF�@)hn@�FPh�H,��P"�4@D�2W(��p��v�_����H,����B� �ݫ���@v	Tv%K�d��8���>��v!h�j�z}�Gv�+uZ(�����l�l�2���yp����-
�	jw�E�t��KQ�y>C&����C��8[}��A!�+$����+>�4/�L��4���ڂ�w�8��Ժ�L2ʊ�H�r�f��@��B��/{�^��N�Ev��Q�o_����&;~0��+K����B�}�JhQ;\�c�?T}���/�Ww�7�Q[�l*|�_w��{��8��D�pt5 �Z�[p+�Ox!rs�Ѷ�Mt�7vW�ڶr�~�D��Y��`�=3�{���4s�EV�m�S>P��"Wx�V*�+����}�w�vލT��?��68�n����;�Hr-��P�u93�������+9��[��sP����0�VVk���u�W��XjDn�Б�: �x���Q�|�	�A�:�,���w+-ᔨ˃��D�'@9�w�0EލC�uq5��1�B��(�0�. �5A,2 o,��O������N�u4�\��Y�h�_�"o-�<n���l|���1F�pwD�v��>��=��`c	RP0�D�7�Ae~���G�vw,�o��n�bv�ԓrcFn�ݍW,8�+L�.�Z�	_<��\cK���!ѫ[Ы^2�P*�@[h�Ju�7��;�L6>z���P;(\8߇T�-2
��ph���:�" ��*Z>�� ��K����C��ȯ����Z�(ǵJ����T
����v@��}�Xm�Xk~�d��L3�dpv�ho�����t�yh��
	�	r�-4=ݡJN�R�H�/��\��`t)ʞ�։|�D"�:�!�~:$� H�,��-��_V�]��?�8���#]�r)�2����DQ�|6}�RRm�!�W�*���8��P���T��������[��B�������P����߁[�z5s	u�%,v���i|l&~�F5)N�f��
7�ui-
ʣc?Ѝ,t <>�AX��(_�/����#�2°X���p�:Z;��6��� �tl��n]/)��A�ޛQ'P�'�h,)�{EK$��8;�X�n�&l��'ɇ�����v-W��Az�D=Ǉ\!�8�T��l~�����hc�M~��l�dt�
� ��O|�x;Brz��V����G��h뀏�+ �mQ����V0Q?fj�rh$j9c�[*��D�]�����0%$n����8$r8<~@ύ0t��`����L�S��ķ��9�t�~�V�rd-��]��s�@��ulg�P����h��"�QR�	M���y|r�m�4v!�|r�v@�s �,F�Y�� D#Da ��WE�`��Ryu�#�L*U^�	4(�UCd@v`p�q@�� Wh-�D+Lɱ�J�7 �h9ȵ��4��;u,u8}�E������V�TZL K�4ER�SHb����@�Vf��D�-F��a��3rg��N�v9q�p`�E(O;��!�t~���.���<�hM�9�'�f�`�5�����V�{H}:HR��G��2�[�>*�m�F).�eyY�v�FY� �e[  ��u�L�~|�7މё?��|��	h�p]�0t\/�`}:��[d�v%�"�/l�3���XD�I5��*��<\Hp�����uC�+),
E��+�:rt�+@.6�;a P�^���$y�d�R�l�K�F��Pr=b �u֋��p��c�p��h��%Sg�e�R���}s?®�Kw"Q�VPqH�ZM���óT@M(����e�ey��\)Rz������(D
�`�plKE���]�X#�	���B,��uA��VBKR O$x��"��)��)�������σ�x�$@C�BL ���0S��}S��C����Bή4L��8�J�.�S�j{�D�������ń �d"0p��`NK[5��7��)bS,Q��(s�m����ëx;P�/�`�uC9�u>l�Go�W�zm�ڈ��߃;p,tS����!q=z�iZ��xB��(�BP&��ЫS�G����N����n�n� �H,j3��o�S �]��/w~��1�?!4�n"��@G@_~����:ǀr 	T�4#�LD������P�C!R��Hvr�6N��0P�\ ��$�� (��I&��a� p(����QW��M�$����o\�w����f�kXx��BvA3��@�����y� "�1���1��A,'�m���l�)�h�M[���HC�U"jp��p$��;zdd��X��WX6�Bj��&i�h�M0������b�����1(�}�J,��1��12Z�0=`�%�mm�8>Dr/�H@� `�*��_�[�P6)�g��F�)�Q��E�� X�a�����Cw�sT�l}7-����k�o �7�W7����t�t(�,��B�g�gǄ��  Hy�Ţn���*W'4��.x�ա$������|x�-�ƍ�\VH<�R�<��-��,<�X6Rh�C<���˶$	���Rv���X,^�}/�4�[��6��)`ٳR��<�[��}�t�u�����@]^F���d�ڈ�ݤ�: '#,�!��Z�����.�8%@U�R�ٸg�Qn�_�(�g;�$'n��C�Y0��YA��^�P����G�,���&MW�9F��5t�`�JX҉��C5Fz���Y�`�;�$�(�4��0\�Rv�lOm<��Q��lY��weY*ٜ�R���f��� S�4��U�t^� �Nh� &	ǰ(��C.)��
 lw�*��M���=��؈hw������-TN)���	�p��AV�.)���a�`� ꗉ�Q���(%T�7U��ޒc,�~fimN�A@����%�/�<l��5��A�����nrw�nI���9��]��������9�rT� ��Fx��hK��ڕ+�v�z�v�U��-�i�4��r�ko0 .c��
�A�7��iҧAi��߷p�y�¦�g�).��E�|�D|[�����wk�
ӏ1���W�Y]Ny�=\NX�׋X���r�S�(���5��� ��d��w	o�h�d�@�?l��������Bu�|U��qG��$��}U��!�4$u6J-��p�4��A�o$�N����Kx��oB�Ȍ@ ��l^�L��`bG���(P���֨�-���]�{(��+�-!
��RotF�����e�(��,�
�>0�}F� <x�v��.���~��}�(G�S"we�Vt�j��]}[���8�HЀf��.|@`Ʊ(.��\��9�}3F�\÷K�:�v�P ��f&"���m��0��U���˕�(�|����YŁ��,9�v@��XL$�ځ�@HBqW���߁,�Wx��@fU�r�$\�#}��\\-����Hau;	
�?��0u)�l1��nqh�L�d�r��F�ji��sH��@�R�{��}�:��__�;��v]n��Ѕ���W�;z��y�������G"w@]��Ad�U=��9�Q����	`�n�dƒC�]w�s!C�ZD�T�,Et�"p/��L��^�[� ������X�TX��L���� w�tm���?�6N�#��s kTc�_�%oL #zq�N�H�'/XD&:�YD�3#gc�������E�c
�]L!9zrw"ް��vi�?t�v+�\�� ��$P�,���א� �m�A�@��sV�U��Q��'�X���h�<�xu���B��w R�ȏ�yÔ�� [�搫q�P�0� :�Ń"
���:�,t �~f ������d0� O�ZAm�PR%D�h�%Z*-"�{ 8�W~��Zk?s;l;(t�"�f�i��P�x�'�g_4���hD� )��^�/���	�G�ߒJH��

u?Ƅ	!�<�S&'�ƪ�GwV�W�W�rI[6
��v�TR�ɛ�%�1���1���I{�9�� =���4��������Eؓ�n*f�~Y�BNf�*	�-��
v��A��'�&y��;�@	���c����=E~���Qjy�	�ʎ0����8��.��^�W��P����ڵIJh�B�;�~1R�4Z-�(�����j!� �cڣ�֕C�$��`l����<����$p�-�w���K�h���N@u�@�$�J��  ܏�0Q.�Õ�(�|N�7fR���Q<qC@@u"����9�ԣw���l��(��B��e�_���k�u�FŻ��� =����~� KF ��l� 
��)a3���d{@�Ā�rRdWRt���D0r��x��V���=�S���$���c���T�>��";E���E x� ���#�8@u�%pq�+"ۥV%ĕ��.�h�>A�:7�������H
fN�k���m�u��S�0Q�(ک̱o/\����:�p�@�xu[���;����Ӻ)��ݺ2`�T�����d�u�Pt��*��q(z͍�#�����ih�Up25����Gm��GK��ok# F9�o�Ы�9ܛ�	1/X#� ��lܨ���=�R��U4��T�`���������'X�w(�,W+��[:x�踴�$8fkP�	SC� �fUrF���ں֋��p����(VD�E����@�،���*� �rXVt]?b	O�]��Ac1ſ<�T��z�54�l�1P����ل�ҽ��s	 ��W�@Dv�mDA��wZY�X�9� �dU��t�p��!y��PM� �&���A�f��@�A��8�"�*��7���0���6�� ��ݷ�*N�M����ڮ��JG�PI.�;�{����k��5JN�
 :����RxRp@뙨�~J�tG�A���ս	�F�F
��4
&�1�R���؟PVV���O�r�0��۳�f�E��P�O)Į"�+4�d��}u��U�E�U�����ۮ�U(�}�W)hQ�u����Q�E䟚��V�H׍ݶ_Qr9v(ԃ"��� B�;Fh8a�ul^�a��*Z!*[�9��J���B��G�O��!�G,[�w}����.tf��+E0��8O$�x�HYjj��IL|��b�Z����$<����w�i63�2��ɒ��f��6��.�Y�����O�ҁ���_�� /=���b� fl2�?���"N�:N������ǟH��1l���:����\�J����ф[A�5v���-(S������g��һ�80��V�#�k >�u��ewPn8P"y���+����]�ą�	[v�D4$['R����9!��v���P��<r��*����� ls�-��e��$�'�EQFqi[R�@{ǆyi�wRܨ~��XO�Mm����'bP��@^O�q����i�0���I�9?t�B��T�~Q{{��T��cv
�?�F��0-�W�4Q[y���A��N��y�0t�0u�bk T�{�L�y��D5�KхQG#��[A��?���X*h6�n:�)XB���u"B��o+�O���0v�(���JD���h���Mf A�Q�ZG�˽�o��<�7��m�	5/k�Z��{,���@�&�z����-��mj2�F����[�F�k�B"-+Zs���V7F�(ZVu|�',�kuf��d-�����2��gB�F��Fƭ��u���/��)�Gl���9��P��lx/��C@$�Gl%�@�(��`Eo,o �j.~g1ɋL�	I$}���Dj�<�@2K��b$ ]�(�%)�&,f��S���4޺��{sN�;�&z��%1�V�`�AfTG�@]�1�8s�"Jh�8����A/��wˈ��D/Pդ�I���C��(��hCt�h~T��� <ި��0�f t}�@Z�͒�}(J�e^�B}�du�2�Ť�
�p����
"RR�@mG@C~� �m��-T@>ԫ��)�;E�#cU�E�U�o�'�G�T>�U8u��/,D�Uo���*��. ���3���H�d��lR�@h8(ނ���3ҥ�"������co��8+f	4t��غ3<%,��F��+�'�q�t`�H�x���tK�D�VA��f��B�t\�K-!T8c�o[k��j<�\ڲl9�YA�_������\��:�y���(�0*b�Q�,�@;WvP�]9�� 8�v��������¦F�����B|B�^E���W,-7h]m����xX��~��)`w-�E <
�Шh}E5
B�.t#5t������+-)�)j 8Q/ ��^�Ј�q�[ێݝ��uu_�4N���z�6 -�,(]C�i���wv�}�/¹]K��lQ�`�� aFup�`a<Sp��)���Q�Akn7��z��`Y9��r)�)T�
o*;U�JE�L�ЎU!A���Bpѐ+��	-L1�m"@�/!�6ӥ�r� T�!����@l��ZtA:,����4}(�?���(�捖�'Q�u���3"���F��N@���#�T���
:��х����� x"��u"���^�l4��AV�!2`�!P4 �'�,�=�	��XW�� GD���*�����'-0|��8��a���:ŦS��yKO/��y%�� 7�7	� �_�"�B�[�E(9�i@'��"�]������	11)$K<�:A�
�*���V��	�o'�j���%� K��#���(p�z � 	�Jw������@��^-7q�� ��Q�͇۬� ��l+P�:�J�n9qY���e���5� ��akp�:(\� ���G ���+�#�UAH���+�΢n� ��x���o�����z.���{<���(�����m��uNzL�������Ú�vW-uO���	 $��',ȪK��^�����C
��d�Ʉ��fw&yIzG�.'�.f bppt]�:Y9`��0t���
�V�-jZCd|t�V<��l`����{�������Aw:;�ΑAF�
��G����S���ʺ��7P��J���k��,0��Q[����)���)�j� �J?��r��L}����C�g�*�.��c��%��U����#V]��JpV���T���l��T]�@V|�� �F�RP�,���nS�H<�F��F/�\djN#�,	���;�|ܞl4�� |��؏���5b��%9 g��QgO�f�ۣ��u�4�o]?} �j0��"\Ġ#3vL��<'� �����0y�|U Vu������:B�Om�P����ܨ��Y�$�Im��Z㫊<�� ����/w犥^*m
#+�c<9~%�I�ꂃ4>̑!�J�Fm.kT�9�v�d�t/&��r�E�آ�EA`�¶<� ���|9��`!��
Cf�J��gǲ�X�J~����J�0���
x����/N�D#��E��+�xf4|p
�-X����|��ڭ�u��%�T�-���J�3cսq0�8�2g��*�zboz�$b	h���Tֲ;�D)�R��@����a1�B�_ato�����F�n�@��/��At��M�Yk��0{f8n�P���kuY(��W�u��K�lhR$~/
.aP9��[@�[0����:�ıS���_x��x	��;_4|���
-|�e	��،�GIp�#�G�M,t.���ߊ9�A;��(A��i�Q��n���4{�(z�F���r�	l^Vd� �����t4lh�l�]��:F ��$�A��~ț0ӅG�޾vP�@���:/ت@*_�-M3C$�ҁ�hs�����@��z0u�]WT�3
h�v��
d�t�"B��+^�Muѭqi�\ُْ�� �82��b#���
H��7�-h
	�H<v5է����)R-n|�y���h�z#PO�Xj��y'�����߷ ��~����`f�E�U�J�Z�2��v�F�n��1/����y���g� �Kj$�!�
���N苳7�*A�P� 	 gK3��5ԐHU�+ �t�����z7�'ۛ�`��@���V��pRv�a��Pv�+������0&N��gQ��$��L#D�
�=�`�/U���A�4ݟ!	u�N&HU+�YH���`��>��F�>%�C�:����/)���c��7��tj�	0��X0�@�rԉ�^��g��D�-(�˘�%��3�V�$'7���ʋ"O9����- ��*/c�oD��}WBx��tH�-f�}��)"P�~Ep�R��,;��N��7�N�#v��u)3�7�{�	���ADh˨0�$�� �1WWG�A�O�TK{-��Y�05؆�����Nq&ڠxu	uU�
=���[��T0~nu&��ϗ���Ap!6�b,y�F՚���RR#�"BU=�'9�� ���N	pt�R_^t�Yl�Cb�A&g�1�Ғ%/��F�(L&J�e�]uG�Ii�<���<-u%ˎo\�!<]�8F�s����B);�f��|��� �T­^,u��ty��	g�&,"	��ֳE7����y�P��۲����GH@;��0��%!HW��D &l	��Iz�d��d���=\	��Ru� x��<��:�[��}L� ��UC��xݐ��~�:��H��6s�#p<\p�Y��j�pl
�aVp��I���0�
o��-$�P��&�C��(tt�0t�EB �4?�;�B�,��fw�XN~F��zT���/�x�f��b��t���Ot�7M@O� ���tJa6�A��X>�s�Kؤg�u����m<��#^�����抁�t�y��\b���^q0)pb�(�K5��k��,k��>#S�B��j����<�A�m(�nos;�B0�-4�8.�d�&Io���N�~ �N�	��,�'���V��{Vju�Po-��Y�F�3t����B�n�%���
��B�e���J'�8з���@�f域 �h��	%t��n��P�����"k�
�P���l�@)~�P,aZ��(����l�>H��@@h��+⸏�/QŇ���*��V0���8CNE����	s���FEG+�6��D�)E�eK_\���F�A:�Y���Ek���䇆F(@��]Y���k���>`�-7А�N@�ٍ�.��횋N�t�U$����v�9j�TV�F�{Q�	D�<�8?@F ��ދ�9�W�G+(��b׋n8��fu���	�'lսT��{`	��¢�D��~��`��#�<�+	kC���#[��ܹc��9�Y=�����)w*�oo�Hug���$f����2��z�[�Z�)�3���mf�1��Z�xD����8�@4�p	N�E�p,�-`�E�\� :���B�-�m&*�-.>C�oT�u}�{��NXkK� !x�ƟXX�G�!�~�%���xM�ADl�m;��;0�z'����<�&�kU��L:�x_))�<
|\�Ы��[X����o�Gnw�Ta),�Ήۻ(x��@�G��((NF�4I<�M�H}M�·��QЏ����A�o�x`���'t�%�A2�1�yxךz--�ū.S��V�#=4נG�e��p�-��QR��X�T��� ��u<�`_��u0���V}4�f8����nO�;*����^��}F���F	[q0V�^�`�L��Q2���Fɱ�	�&���� !�U�Q�=�in ��F.���܈G}p�u(Y�l�������G�f۹����`��@�Z읙9Z��.�Q3�'
I͍e��I@m��H�G=utE)�m3�3�X\`����<���wF�#	9>�N��n\M�V�-�e�]���R,��ԥ�t2@8�V��,�8���e��0�+��2,�6V�����L���Hl"w��F1� �@, 	p����^��#dY#�� ��H�8������u�������~��j	��L��KW3����~|-�1�t0�EcGQ���t5B���y�!����⿩8Xww�	�tXq���!�<��F����T"KkX��.ꋽ"h�TXŷ����r�O�(�)ҕ�ǰ� �2���D��p�.D�P�gR�EP�tg�53�Q���W9\��=2�l��~ubw&o(AP,�b�j0.�*��M5j�b�@��pA4�%,d���ߕ��09��eL��A��Y� �Ŕj�A�>�ȪD�VOI���(΢��y��X m/�h^#��|�'���	�1h��x��!�lNC\��X�p+2E�juOOQu8���	2�@	e�B�@H`#
��(��H���
u�\q�zك�.�Gp�d+@�(��bA�e���E��n�!j�;:X�ؠ���h	(�&^ 2"G�k,����g�~)j�P�$�6[��������t�L�ofZ��B�f�Nu�<.���fF��V�n����b�u|�t�ݎ�Hz�|"w1�Z� n�9E~���tuu)�W�<$����m8@��o�;���-�E��B.��n�k�A�TC���iP�9Ht�4-֪�n�`��E���p�~�x@���>��x�[)�ؠv��x���x��{ma��Z��i°���:a����j�~h��XW� �	M���G�����*�|	l5k
A�~CD�u����A�}�u�9�����$xQG�	'��n�!��x)�؜�(����4��(��������Ȋ����:UPzۢK�Jb���;йj�t�VC���2W\��'6�D|��wu��p��L ��M	�Q  ;��3�/��B�����?H������F������*XR#����QQpVp&���2}]�	�=���N/�A�T��C���Nsκ)��=�}$�ޓ�S@�}:PPdOM���P`��0��u��w��7�Ã�F�6{E�D�S4Ϟ����@��A��� ��鎯�
�H���M(
ZP���	�[[�6��ē��-��ى�Jd���o52��RL�tnmBy�Pq��ڸ7�Ɇtg�k~�(�,��ȁ\�J�%PL����
| Lՙ$/���d�f�V�\���  K&7t�9��,�!X (��W��>��6]���1�I��*
����sƸ�08��= w�� ��	�h0�����A�C��<����5 
�A ���G���X���h5�dNq[E)fU�U��X[�ZG��OǷ [8���) usage: %s [ -C config_���ole ]qm map����v N |. 
�[`�?7s>b boot}g��_deviccgClr�=�LD12sF6i핝loader�d �B��lay;�#t�f�6��ve; S��e=pP ����x$�nor�r�7�� ri�w"w+���e��LRw�J�Rd7-I name�F��optisg�	�}�>u�U{�[�aB-H	 iUtalm��JlCto aciB ��P��sc"�AID-1)2׺�{A /F/X UNK?~;v�que/7at9a pard���6Mmb
��r�ex�}���� Lcv�;T hߔ�liZ�V^dd[5{n2��XHDd��pmp-#A*���qV���.�V.�s�nf�'
� �_1=0x%x23 �2BCM-���N`
CFLAGS = Or���iW�-DHAS_VERSION_HK�(R2bb920�0�`{8_BDATADSECS=3��`EVMS
IGNOR+�mPEL	��KEYBOARDmE_SHOT۰��P4S16mDI[�doCRFSWRIT/�B����LZSO�_C�IN�?�,�IRTUAL��xMDP/��A[����/  W�houJ �B��-pu*~��g�b�%d.%<]�K�eHe�sTZj7�clu	,fy��جF$'Max�ub�j� DYu���AX%GES���]�c=, sil7;�fd���B>�SCRCy�B�� _�T~X����/etc/Ơ.�m�j�  �?sy�)����purYAbBCdC��R�ImMP�STxZ cF���LpqtVXz �D ����  �-bX�Y� ��[�#�Rb:kup ����w|n raid-a-��Z�R b_s�cse��mdTRO�pP��&���s�h�ƞ>p � a����a�no����twy3
/�{1�)Nawd -���$RZnj%�mod09Pk�]څ-11S5dz��Z8Kpo* C��]�yr�h/(CV19+����-8 W"vAlmKb�J��g!u�vo�	��L<;9g07��� Johnff�n52�� 0511a�����nyi��8B[��s�e83Th���Mgnmv��is��B>UQK�VzLY �:�Nk]��TY�/f�A�n�ms�t�
d����{b'����TnCe PLڠ�F�[(34u	)�m��.�tfDc��fr[Ko2,F4�]� COPY�G,�o�k�pa�t�l~؁. Seg� ���#�17:�:34�G�8d�Bҷm�Rpnogk���lOL���wf '�',l��lrL'�y�so|�cifR{u�ebd���a m�n:fכ�Zis��t@�خ.�f�nsVs��J�J�mVR��G�w�)13� �.#������c�B����J&j H�!�j��c �N}cy������OMETh�-C��b8��+��LBA328��m�p�I0'�' �R{�˂���2��"<�:�L�zSBĬŜkAvPh9�e+݆00/24��ܰG��kZЎQ
l810#�m�Fy�Jm.;O;lF32DK���2Fn��bj抰�F��`4��m�ED'6�%BSթ$��N;O��p;=s y� �a�{�q�NU�6�|m�/�/" YyTtB#��NnFf0)�w�@�À@��\;p9��%�9h3���B�q�%md�4iX�l�eZD�u�R�k<v�z�KX�s�0\d#d���7�#[�cy]`��8Q*k��Q�$W	;�e�-���e��Pr��f݇���A�r�9�-#.6��6gU�('G��IH[E�hn��G8�ltt��f��hDL�<7�@l���7^7&No�6ZE�P�QX��2ki@�Ѿ]>u �n�$=v�kPC/5�
 =ah4��'sc������at*��e7��s�$��E|�!��� �Tb��u'B!��I-�{(%Aj��H`��o-Zn�op�sYe2v�jg'[5L�F L��A��(>15M)�ӫ��$u K��N�	t�O{�n-AZc� �a
��h��6QL���BJ0�[l�^���p ���Sf��1���c��dK�a��%J'8`Bqqy�D��%i�rF%&th%��N��Ͷ�m�Nv��M3phh))j�مn�fkltfv��� ��-ls""A�n�ԩc��aXЁ�5�m��-e�ީ��N<I�8�.x,%">�@�.h��f�t! V�����f�Uްǩ �q$�F��K�8R<\�L ���i� ����5P��2N��7��f�n'|q�f,��?Lk���=�|Oa#�
<��xz6�GA�kfo�֥!n(����B�%� ���QM�EX
N ~hx�D	SK �(`4x);�I�U�S �h�"�"hiHnf��K9���`M�I����� 7�hO���Q�f5��-de�4M'M+:M�RP�ÁBl ���f������2�@�?IFQv�4FӨKv3�fN[6�RO!n�vQ4J]a�x��O1v5#V��21�u՞�a��,Hs'��07Bi0M`R��Z-B�{��N�r�[a��K��j�vk� @80[2�U��):�sBY�.�X�,p��lu�Z"{*�${���f�x: ->53�59xۡ::q	�C*g �>`��r�
_I0X�j�SZ=Ip�""Fn)C����-HlW�aOf*|C_��Syn���mpx^:�8u)�bA�;�pc �i��#W;o%�,�x�͏W�嶆�@�T�Mt��cV�*�*�=�f_��_->e�8�
��e��9�&&��9w�ιa]u �e0$�� i� ���s>6&��6˦����'����<U���6 �����ٳM���a�����	/���l��l��W3[Ho�k��װl���{T7�w��*�Q7X����MV�`�Ka�S��1V�7�a8G�'�xf"8�b�9�\4MD�ݢ5��ELMIX�n�EW	� Ը"_m�BoF���e�%.�T�s፬�+Me�{'^�=U���_{���QS�f�@$:.o,�b!��4x�tqp;�AUTOg w�<���Z]6�#�BE��HR5�'N�u�\�c�� c_�,:S3Ah�.BY�m����c��l�.Y�g��k�^%�?'-%�-�0�����k��@�*�#Ģ�ox.h�JM�_{:[���k+N� v�F�d1h0T D#��[K�iq�%��*/'�Aw(�)cfx�&+�
ڲ��R�,���%�='��P`0l-%e���X�',/'UUn�"��#.���	����P�X<��*H�g^m��b����:=�R�m�`_.]xh�	�ev�l��)#<.9&N���v�M���GET_$Y_INF*�,Y:��h�#CqE����KOgm��V=�Gg	)'L��ms6�-{���Cj  �Y��M�sF1�ӄ�W��-�' �-�#��y �tnr�=jVb�b
�kM�bЄD�.p�7� ]��C��&��D;t԰åpH'e�_cn �/�P�aeɨdI+#Hp;�_�Y�ꚴfe'ҁ>�DI���s�E�,���b����a�=+��d	FylĬ�ٍ�Xv�~h'�c&�!! );���k�fB�B�%:ǥw,��6s3]�_B.Ytm:�>Ch��=�?��bɝ�e&<0�
$D�_���ݥH�ks
4zGŉ�>0!����[^J��7��Lw+,=Ja�hms�M(�a�'�;࢘�тp`:%%�^�# M��?��B*��u�A.wA��V)�@�V��;D3� DL��ؠgi�e��a� ͐�2���s*C9f������m'�Z�h�V�#�`.Y��=H?� �A{�q��gm�*.�I� �9��df��%їHol�Uՠ&(c�x�Q"C�r£�@�f:j]7c'\YE"j(k-m�*MςB�JM� CAC��X	4D���Є �hV��`9ch������Cjc��T;�(�� 3^��%�",���sV?��fM��!:?U��X��B
a`.�\;6)?cl�9�A�l`F
d��3.())%L�)"a�� zl��5��J9 �͠?�v�Y�9c0
5�H	K!����7 �`7�P��2x,�HҤ��I��f|�,61aX�ch�r��St`3a$���'^0�;\���28U���L��?!? ��0@(�!|���aj3�C��ݤ Q_�g�I�CTL¸5jmY%�;�%�V��nH�G-6`@^d~#xBًI%.4Yj�H�t�{K`'<`�.oT���v�wm c�vems/�_P�r�c�LC`�-��5����P�! �A!�	�ld'tf�䣬�, ci8*��M�lC��G:�	7F�f�$��_�C[kC`W6i>FS�#As�A	؍�_UNbK
74`�`645��G-ߒ 	��d�3(9����FId���!�mM0����l/PVs'�E��+��
��ѡ0�N�SP�#_�/Hv*3x ����
InVES������V(�hF&��?�	��).�*:F<
G�%6�� �&�i�F� l{O��_�QC��Iِ���N��)3za�qeyƘX�L+��)����h��L���	
��m%�Ît���Ebwi&��C� E`Y|`��x-��cT�XB0'�k�����n_}=����R�g8�u�Z�6>�h^82�B�&���.%5��j-<�dMR)!�H6S�$DS���r�^�gN#CESa��a\�����&ib<p��s~͝�y�� H�:s2K|`M Du���Ɗ"�"E��%L�
��;���$
C���,��V�lYp�p4��
r;��n	 ��q��+��i��'>^�B

 ^�aR�*��*���Bx Z31	�p0t�k<M��*q���A(N.$>�TVo�A��s��ap9�L:�4(NF�X,=/Emi�dXa?�?)G	A�jr�.�PD N�߂��gZ$[3���m5n�,l2.�GDF�m�PRQ(],�a�'HJOVV��*V��Q�#ϱSCo�t�h�dMYr�va�lHM��J�F��D�J	96��0/HPAC`&KL�u�r�xSDl�2�Z��`у�
$��z���?�:+8'�'�'md=���:�(���)do5�u���w^h/�ą| �  $L ��,Ya���!�f}�E�@�s�md2��8	/
fj�73��H� ?��A�&�DB��$"12��4�	[,)S�2�QKkno��sW�GPܛ,�%�"E�)� 18L�D����"�et&�pb]� ��D��H��f�@U�o��mD=255.�N6�s�63x��ԋ2u׾�P.PU�6�W���%'� ���@tK:w5(p)U�`�.ܴ���w�,�W�B����Rm�c�.^{��j�hGni�3�.��r.�{(�s;j��=`8ꪭ�pEh�T10BSZl�`60mff GAi�0+��l
��o�ULL�N�nXh���l�MBR��#�({1�e1�-���Ni�U��޺q��Bc! 3��HoR�fA˿A��VC=SAFEފm�i��'F0IĄ.�a�G�Y4��Iw��>��! �WH�o�S�7Z "@��p,2'v��go�xXR�[rF�`&�V$�� �=��"���jV1�n�������'� &Ȇt="CgHp"	�$;X�i�,</f'�����eX�$I�hR_7�e��.�4��\u6T��y��8��(mjZo!/l�@���w!gg��M91,M��g�C%�2�h'Fa� P�u���hR��(�h�; ȷ'0[Vl"#m.�_�p-�,������?$i��ͰCd+1)^I�-?zo�,�P���V�g��!V#f�ц	EnyL4bq�A�K�\ԶC1�a��Խ VfL�d+/	&C�&��݊�b�N��,!$�ߖ��#&rB �X�S����D�;,��2Hi�;�� @��N�H�L�3O/�nsŰ2go-þa��g��8�5xe��ׁXB�(���!s��Cv�:�l�L�4M- sm�f#3v[�D��ƽZA(-�aX`��6M.AWlѰTO�GD�h6?_ ��Itq�Un�i$2"�P�,eM4ls3�s���K{��PQ�.�#JĬ�t�@c-�� 7�0�"�8q�'Q���e�9H4�ch���aT�X[NV���/y]Y/n

R�2�N��$���`��,�n
c�pj��d!3y�`/��� �N��pF�t���)H�,W4W䐖��e4�GW���5'9NT,�0�1��XPlث&Ya�,�fU�h.�'ʱ��>���d-95S98ZjR���
Is�f��s�%�Vt��? 2f��r�(��f]�`m�j��j/�фb��S��t.�nQ�l: ����83�0f�y�A&�S1d0!�|r1hdts�r�rqpor�!nmlr�!�kji;lc�ahg��Cfe�lo�l��v!:��cba��:|/U+8���_4\�M�صP�\�u(��%��=0J -���s9?J�pc���d�v�	�C���)�.�� �@@I�/z�r5I�*0@�ܩI9����4<�D.u�  ��Qp��+fD�N���0nk.!T	L���({�C����#fԺe�xD�li ��:��4o�>,x��(:
	H0+�
�AD�u�wnmF�e-R�I&\���$0 $/Hx���E�d!����0��0�N�Q��v�Q�D* ij�0��K`m-��G'�E،eI�'u����l,\ڈ�j!��r�b0y)U���,3�Q��5�pT*�bo�L�3nSqld�&%�Wv�eĶ
E!��Z�D�9{��{�/�]��z�f_�9&�_���L�
�,N=��ԛͪ��Gbl+�,�'"=m֞+G�G-,%��b��H �M�4J!+5�"e�;�e}��,Ы'^�-Q�Lgued�[���l%��2а�u~��U��~�l� v�i�f,�@�b�_.���m�e$L	�i�B���el
s�1 U�Q+-�lp8�;'�;58z����%=&��0\ŤL���,�{dS��m j2K s��l%LO�D+w�QxYDs�
&��:	 V��*��~� VB1��%jV���)~D�g���G�l�I=`���n�M�=��u����'��X�@l6�H.f�c!���[��F�B�T�j�JR1���0�@�nЖvV��BP-_t~#�=�< k�t D�{j�F�,��I�"%"o��fE�Ƌ��Ul�/h�#h�v,CE�	�30���mdT�:�`9ts�bF�U*0�aF���-(�r)AɎJ�u�Cz��L5Ј:�E��*�&��[�{�9���6ٛ)QtHm�]d�X��)\�F�ba�X�(�o��s>v�iL\�d�/,�0's5	� U��C�;W3�*ËeF�@Sp�� ��`
d��cEA(FN� ,�zǤSX%�K:%�X��'�2���XZ��B(u�Y)�fѮKlX=$�@�T fЀ�)`�6{M8/�UlR��]M逷�d�}#=�`��#F�<����t�
��
i��C,�..�o�\Q}Q�f�%rဌ��.�	��1����]�7�iH��-�],��
���m��`$��kT/�Q�\N/(0ꉥ�=p<̑����"�cJa0�I��Ńb����c	$�E���Bc��" �s�Tyt�0xA(�)7AĆ~A��荊�d�%�$X� Ӝ�aF��EAY�b@�1C�fL{FjT�&��2�w� ����_�`��:�~d.���+s!+ͨ��4B�h�iosAƘcb�-�� 	r�E��zK�T�!f4)Va$bJ�8�t�H �!S`���x
�b�f]���g�l�WGDѫI��A�eIOn�=��%Xյ��b�h�c�c� �@�	rf��S2SY6	O�3 Ί�u�bd�A����ÛoWORDR-�3=;0�\���UCT�P5��
r.f-$�Q�(H�=���6�p�)n	K�Ir��[F��g� G���F'-�ֈ�F'��(Y= F���5�fy	6P
P�? �2�$p5!�0Q�+�ƌD��*-9E���/����T�LZ�;bL�&86�f$x�Fpf�
�A� Pu-Uq/ ߒ;@g�w�'�+�TZ��m5��s��`�p�n֢�C!�Lr����w�Z,��'�<�`܇kbv��P��KBfFAULTXձ$8q�IS�=x��2a��y`vm^#s+�VM\Z�� {.Xn�`Ґ�lq�5�al Y<0J_�,��}�a�Н)��X"IR���N�k'���I 4ׁ�}e�e�-j�lH�n|m��,y=�SըMrc�2U�f�oA�/\��i|�/N3&c!8�8Պ7~�=X �0��
~SHS-=���_�� �A���Lè���-aSTRO�Cg�&��6�IH�x�	(p��d�[6 �.)@�j��&+?*�4s�%�
$5�Y?`5s~�l�U'!T
E���+ֿ�ة4� Y"�w �Wk�h�TR�J����&bcU�p ��f�^-���3�B�gT����=����kʃd���j.� ��`�pw�l_�ܡze_nH��̬� b�T}8<> ���D�e �� �I�	�BbTG���`F�E�	���pY_n�`6#��Q �==!BQI��/nv���LTWo2�d�uT��C<��p��8E�b���,�j��xnYfv6�1���-)I_8]	���4�cG�@F,b4�l�<S�
'0=
�
�~�S`�Dm������*\ �p��u�j�Qa���G�
) �RRA�� ����V+(CGA�*`9aX���L� \c���0oF'�V�!��'`�L#[kAl�k�X��b�m%@�%��<,��w(x<JX}�T��1�E"�O��1��BPWe��Bne�h&h�2~�T�����T� ��a�V�֙�`.)�50��ʚ�U'qX��܀�� -;��I�\�e�((2)�@ K�I�V��cΟ��;A��b�~_��ł �9�����S/N��i5�q��h��ĆE�P=`0L�)��&�١ ��0©��p33j��M='�0'�&���i�=\|&��	pk��{	A- �X\�i��l�Nb�GR{VE� �Q�,�3$�my��%�u6 J�B�u x�q�(x�^^&��
�͔ *X��U?��B���o�j�;�)���=)=Z
	�.-��a�-~��H,��C;{iVS�I+OUT�4���20���1��� ��KX����I��qB3�P(�>I<0-3)T���dX<.>[,<bpsB��a�y�>] 7�j4�D{9Gp��f�n؄@7��F��N�O��/NhE�7�8J�`Y�&{+z�2IALgP�e��0�����PR�TL,��0[mLAYY�����Z���
�-�<T�-�b�ce�[L��Y"�2��@�����k�n⩁�l)L��� 1# ��!\�{���59:�39.5�İ�$AH#l&\@ 3 �`��a/t�sYյ�"���m0�r'w>5)`1��c'���x��zpun����h��GU��^��E/8+5�^m"��"�z�I-s"�ʹ�5�85L�(��&t_Ar�ޛl�sck〡�f+��!��}::,%9(���%�eEs}c5�F�_L_�1�Y°'u$4�-@'i W��(gƪf��	C�D3
������ONLY�_�ҡ&�J ĭTw YP�T�~����Y�/o--�s�B�=}UIDj�0�=>''����I:xa�R�''�x��
;�\�uW-��� 
3�4c���a� vs��h$m�aC�8a,̼ ֪^!�����M�D�N�I�2jE8�3� @�T�_oRX�*4e���Z�),Vkj�Z�m)$	&A`A�"H�vm��
�9A�3PB�S�D5�bD^�0S�6BY�2����T,����cfLÊ!8".�,�!V��$Q�7I� �W�s�v�(���(�,Nc�%��rNG���="�N)7d{K������0.,�i Q�mN�R�7Y� �=2,� {)Y�DOCKڼF�F��X {�e�U��=� .�N�"�iH��S�6!$E�w5�3��p}�w�(�e�C�ڋ�S�UlV�lrp%avw+n ��b-%���E��_��9�7!��f�L�(`M�huc�m� �j1FH0��&D��H�-#�T6�*�	)$3C�RrZ,���h����4�,�ن ���mQF2�t �b 	[�"X1,Y��eKdquo)dz%bd�ʞ�\�%(��Q���wW\n�ͨ�t\t~�����NlQ��B>|p���\-� T`n \WB(:u
A�����������B�,n�0N f8b�SŦ�.�ً�t
װ({�o^Q콳9ZC���(�����䈏�Xm�� �:�`��1�$\�f�N��l�:͖U�!�3ځ3��@���f�'��Vb-�.H�fԴa�Aj:�7\0!b� �l�oYyi64QV"�n_}�"���s�H?br.bP^����J�%�`b�	a�$YF�aFQ��;�#A^ T�.!A�XA[HX0� R�fP��5�- ��U��(1-:"h�ae�e��Mvx0 .]aCt �PT�^�p#�#�l��F�X%�'�dT*��Y�|M.�bV�ڞp��kQ_T16_K	32�v�X�FS8OSC4sD}	^R���2��dEmcQu���*Qa�å��x�:X��
+,Ҫ�)p��:9Z�d(t::b��D�^�f��!\�2��Ta3ڄ���E0�_K�_hi�@��*�IVle%8Q޵��@�A3 ]�a!`?�eE��Lr[k,BDMHEPN̠a��p�g_$�j�=�J6_���xq�9"��`d�bP�C[��Z)�ON=�D;$ln;�&$C�f��M���ot�̰�	$���!7�,9�NG`HѲE��`���"0"9_�#��fn�z��^��@�Cbs{��\��)Sh3��[��_#SK vY�%7P�XgA�.v�Q� �/j/
2&u�E�[2 � 2/�LA��������uHH��a�x3� ��&���ʭM�2Q_.rZ� �YzaaR�����Z`����3!��2�1Ԃ�E���S��c�Yf:`ڒ�	-�
��A�U_���.(K(Ǫ�a<.E�FIB�a�X-�o>��1-�4
If	�6`a,>Vх��5(F):�3��*djf�Iz�.3f0�ZV#�,dDY���c�RgFevj�laA�j�ld��X����#6�"M:XB{���LDR �
=B�N	[=d����VSWAPS�PsE2
-l9
�BW�8�P5l_I���Pۀ,b�n*9H�:�9d� 8ڂ����f������.ktlI�B�e,(JU�4=Y���ǆx���  	�ln�T.3	"D�<R�'l��#'%2	����N�H�	md�p� ��-j�Y�E�&�9���fdQ	�%7)�&C	l���%18�51142u����]k{�
�.ilr!d�x+ �C� ,�٩��	�ެUKMGT�f;ӥ�3u4{cbaok�%u , �8V<
�)�%�gXa|C:�`�H:SPCLiLo 22����.05.13.27X�$x�$������ePD�����5Me����ɘv7�
p��P|R�,&�ydx�^s�3� �\ɾ �Ox�
b��#`|�5p!Q���.A ���@0y�a)
���(��ru
�)s+�cQ0�f�
Is"CDϓ1{mk�
��8�13;-;��V{8Y5	�487��`�1
./�@���\���NI� fE8�$cRz�c!FA
14�4	T=m�sϾlbadbu�g�_(j)L >���?Ce��YHeF��Q�7H63 �%�2�{�bV������v�L$]��
�^U��Q�E�zIB�;PX�x��0� �$kX�0���`����
('G3Wf�E��^.8�'-@%2�&lN� �1}
	�� 4.�RC��2bH/x��"���u�n*p	{%�e+2%��Dlm��-�Hor�I��dkfQ�ꐪ�,{�e�G:k�L]3�A�c����d�
zLM�\sSĚ�s��Q�l�f� KC����6n^M�Û=��6X(��
ޅS��\�P,�8(0��Ut :m:%lV:;�4�7�:5:0�hF��Y,�f�:�fT��b�@��Z�Z���Ȃ�^C��T�sJ��bW+����:�-�V١�(%�U�NJ�XD`����,�# *#��!  �|�ΠA*E	l�f-!DAPGaFF�*kD.S��u&(�H������G  �$�e0�g/��&��GDL��I$NFc�8��&(	(DAn��Z풩 �� y��	PCcsP�Jѡ���D����gDɟ0 #��;p c�Id��0�
䊑1F�M��{�j|ӢM#����.5�p�n Ds��;����%0�`F��A��=E��A��Sߪf�̺�h!�ް�b���fu�J�n~��5�wp�H=̰�:
" �
�0v��v��U#64a35����6%�10���d482`خ�)56<���L3Y+���160C��h;��
�vp�
�
H�X	�
a�r �Z�Xf��b C��Ǌڰa]fT,��1l�TM�
^ PTt�m�x��B(l)�C(S�+	u�<�L�hRSBT��d E��Z��l��9DA�������= <">�G&V���e-��ȖŖ�.7/pK��&�FlZP*0޲66�)XW(X~4����MZV�H��A̡g�G�MC:�uV/"��^�S%_HP��-D�2�M�jXd���lN�a��x`��`�&
N��m5ۀ�x|�,z� �, 3���R7 89�y���12345$�w�6 -�#H�27H>�
>^����i�����H�i�n�W<2�tͲ��'%�4M�4M�l����4�ׅ����.�4M��  )i���/6[`e�i��:>BFK��i�PUZ_d�c-�C�(�,h�����W�V x�%"p��r@�M��R��Qv(Y(�"x�ym?DN���Z>F7�&�̝A�pLn��d.^),���Gm+&X-s N�dQEf��%M1:P�����o���"3'h��,a��S#z�7��5���eȨ�� |�-M�&l�b{3�z�2�1�����os&X`ofR:pUO:SoF����Pu�:.q�)a bx�r��q
Th�)r^��M�hi Hg����bύ*�Q��v������q��D.a��s�p.(L_�u��X[]x? %���Mp��s�p$+-� ��12��*R�.^K2��D�@I H�9 �bd_` <")���$/^��FF�B�޲�Q����)ca���Z�'i��Ä0�;[P�C]�������c.\��sM/y��C�I�ˀ�r2�a�I�K�xM&��U�X Ap���Tf�fP�
O�B2�,:�&C���Edy��u���f%]@tMp�KX
p�w��A!L)acq�� �C)!T)���Q)�W)`7,6 H*�iN)(H)1&� D %�l�lI'
�,v
L�VD@݂����P)A
B)0%3��  ցu% � ��=BwUL-�9�C�8w��-T�[��/���E�XE)��I�`�^S
p_e�n;���J��Oh���I{#
#�d5+(`:Kt��]  �=�_�KF�,;��=Sw�2�I%��Xk�\�o#<�&4K��a�eD�r?~40\��b����j�-Q��|����&��
NFNs?LNZI��,�k��� ����kq3��Bb�Hq�`���i� &)��7�)��P `�T�B����3  OB�� ()={+�`����F�""7��5=� 0  ��   +y�|`��@.{a!�Ź쁅?��F;�T�GU������@m��9�����(�FA����ߎ���������������������������������������������������������������������������������������������������������������������KZ���������������������������������������������������������������������������������������������������������������������������������������Ltm�� 
�o�
P;@���� �     ]��"����[�   � �!x	�# $� &�p�V���| +�(�4��g � o��4 5 6 7 8 9 �; <�h��>-op��OA B� D� F �V�G�� J�(P������ Q� /p�F[� V� X ���Y Z [ \ ] ^ _9?�B@{�}�K�s� � � � � � � ����� � t � � � ���B@̑ � � � � � � ����� � � � � � � � � � � � � � � � �KD�� � � � � � � �ٱE�� � � � � � � ����T� � � � ��� ���R�� � � � � � � ����� � � � � � � � � � � � � � � � �oP�� � � � � � �� ���� � � � � � � � � � � � � �S� � � � ���o%� � � � � � � � �v)�cITZUT�F�^<<.#1�V��,M4.1.010�07�X��1"����"##$ %%&&�m
[؅W(YlGG#�)u:-TTnm0x� 
�m�/�LjztqZ	=W,7��-]K�Z��?|xX���FeEgGaACScs`+0-#'Ik�{tJ��O��̈́� ���bđS�>L(
BN��"Aޒ�&�h�?�@Ɇp�A�+t�r�5w�	���%�͢/�:%�h)P&E#.rg'nبI*�E^  �a�TBB<����iuVTF�a[d�e��('cei�0���n�ţJB��P
�v Ak�D���pXB1٥B�l�I�fD�ruS�A1~y���B�TK��ABB��
���0mIsG�� a/�Sp8@p��؄�B�ahY(��,:r" -{��)���d뭀��(��}ADR��͂CG����4Kr�p�U Æ���Z5�d�.  L(Xn�.a`��dxz.Z���o���s!��"V4	�F)8$��9�vbCw���
�����z�Z�mbo��b-6���
&)�<ICiѠI��#�&͊Iq�����Lc 2~#`'p��
X��3�L�NP	�Uk>��/Ԛ�7VaWa"���l��O �mf�HƄ){�&���h;E#
%����td1cMj�s���f��k�-�ظ��mT����@Y�L��� ���-s�$��˒6z��E�-tu�wh�%�=
x3�Lڄ��2�l���*�s)sAd�`����Sr� ؁B^�٬��}:[��d�*M�P��h���D���[�f�ra@͂ܞc¬`�'��W�aڍ��ao~�F^��Q��V��3k��N�U�	 ���sx
h��b��
��)�A5$.� �|a.�Mh�.D	�W�&Fsߗ@6M�0���vl�� �ZlY��@��E�;@�?wS�$���e�34x#V�|�.�eM�H ��@5�qoXQ2���Y��Ji|����p'cY�DwrX6�q�Lja�Wd/X�q�Dl��"<H.�D�f�xA*�;��"Y�p=(#�8��2���'��ĥN���=r Z�grK��4� N+�'0�czISa�y#ز�ZC��1/����?!H� �/e�W,��[�U�/ci�a�07�'�# ���
8J����t5�>��eqJR�Fr��Te��T�!ku�f�%Jr`����'5h�e��rw*�
@SzN�YEj��j�8 �N܀+6�H�XENIX�c;J�f/��Iו_�UIV�2�I/O�}P/��a�$fA%5i���\~W`]6�YY ��� # l�?r+t-�Z�i�f�^hr|sr��:=IvM7X��#(H�|K!PW}/H7�#^+ee�e�?�Y*l��Φ��w/6�]������7/�- �C�4��B�+d��/I#���O^��#�kWC��*{`D����`�?�*d-T[� � �*�� �h i�4*|��Qo��UYq �	*K v w x  ���z??���?S`��M�T:W�X�T F)SatJ
l�Febr�Q��yJ#lAug�lO��v�o�`c( 0:0���� ?'<7�ᬎ��$G���}�뺿?(knN>O�*��r��Iɱ5���aSA.��Z� �@���?��AC��GO_{�	���gݐ'@���������4��p+��ŝiզ��Ix��o�������G���������~�Q����Ǒ����Fu��uv�HM�����]=�];���Z�� �R`�)J���W*C��xH1�rD��"s[���R��y|L���W��V�n����y��AA�� �;�
i	8      � ��  �9     f�� D�/�����쿌��x�r��� Ą���s��H/7�3��r�\n\�<�P�8��u]s�@�C��������`�# �7��-�? 	}Ö�#��� "  M���?T' &[��  ��ϖw  �A&���{��l�r"/�r�#110 153061k6�2244899�Z��38572?���660 NnOoEe0D��o3ckbgcrmywKBGCRMYW�v�x{�W��T��a�;��W�W�<Z�^�{��MN�W�J�p��W��c٨{��䕼���W�z-ix%��?l^�+�w�M��M��JY�� \ɛq\�Y�W��'�M�Mȕ�DQ;�z야�~�M�O+ye��~�S�J^�NQO��C6�=���R'���W�z�W���R���1�J �����WNOߖ����W�UNe��;�8� � rB�����,怒�� re�ƅ�l��rT� r%���<Y��.�u��O��GV�_�<����� \���cA�C>��0aE߷�+y��?�*�wWc_���,!6 ���;�}'	���"֬��:���|(�약ț�c�yǲW��oO�oc�야�o�n;�`@�oC�";�j�J�'kqO�*{�c'�ݗr���(uU�	q�J^%��2�w^s��c�o�rnw;﬏@��W��O�V	�7#��
c�w��(��$�'��,�M�
Dl�Y6M��H�0c~C>ħ�Crٜ����a�����Ms�����ї]�l���	�K���u'+��s�Nv�2a��g��Jx�5���		 Typ/�c�e  Boot  Start En���d
Sector#ss?o��}Extee!BIOS Da; Ari��e(EBDA)+<ɽ�#vice>s@���!\	��LILO}���]����м�RXV���1�`� �����6�a��f�
�aL�\`���u�����\�v�Ѐ�0�x
<s�F@u.����f�vf	�t#R���S�[rW�ʺ���/lf1�@�` f;��t��ZSD�������� ��f���u)^h�1�����K/j��K��
��u��u���
U�I�ϖ�@� ��<� �N ����t��a�\����`UUfPSjj��S��`tp���� t��U�A�r��U������V�uA�r�Q���������Y���@I��?A�ᓋD*T
9�s�������9�w���$������AZ����B[� `o��oCsMt��aM��YX�_x�����dG�f��t
f�+��F�_�������$'����@`���+Xx;�C�tb(�N��7}�J������.���������-���1�1���0������h~��A���B��t0���K���J�	j �6x�|	wX�v�[����;&�E�������z �.���,
�ˎێÁ��o��^�9�v��&����7�V	�O �T	��)����Ӊ�P��m>RQ
�MAGEu�m��>unSfo���@����*�&�d�%�t��㷫ɫdf��u7���߸��$��#������
�� o���ǁ��#r���fh�������o8t������B���o��
s%�-��t�E2�tW�u6��w۹6��u�_���6����
r)�6B&��#��� d��o�� ��#��#��#�C7����?��u	�mk�l	�L�G�F�ֽ����r���90��i_��x%��������#��뙷�Sg�[C9�v�#�����/����p����f���n�]hO������n���D	r8>:t,|K�d��w�+$�[��=d�U&d��d�}��od��&f��d�6wo��~&�<>�M+� uC����oA���>V,�U���n�v[�����E���� h�R'��֪A����a#��J����S��u��_pop� p	&�F��������m�(%�<	t�<?t�f<t\<m���tv<tTw�<tQ<tM< r�w8G?���oj�t���C]�[l0���u��r݈Ķ��?�t�j@8�u�}�&�������{��� �� S����<sk��[�E辟���w����0��n��������u����nĀ� uK��_(MW<nobdu| wh�{����4vga='�u��#ܦ��%k'=F~���x6locku�k��dO'mem�n�F�v�t�z���������}:��{Qo�g��+�m��K��KS���{;��[���K����֚Xc�L>�u���7L}d�~s���6���@D�G2u��t��.�!�޿,��G����s-�������u�6�D�N�6��9 ����t0�*S++���]�۹L�=P���X[<y���`<Y����6���-��P�����g?�f��U���؎�z��>� ;:��D/+0,w7���^� 's�6�cG�/�7�*���	3���V�GO�?ܶt�
��m�1�A�߶�)�WV�v���
�^���*��֗h�!^_�AQ�~v��B�.�Y��][	�m�q���}�)����=�h�[�ow�^V�-,�; �?
�ƺ���VC \��P�x6֭�ވX=Ut=TucQ�]/P�
|���,��!��V�a����PXjP��I�v��
��\t5����C��B�&;�.���}�O�o�A���D����W�ߴ�	�� ^����{�M߶k����G&��S
�&Wa��t�-Z+p��7�����T&�Z��ڱL?����;㿵Af�܌�9�v��ܶ�v�eQ� Y��[NG_&�9(GH�t&� ���>&�B&w�Fs�v>+�OC "���-�$i�^A*[�&P�X.[��Z��	�t�I��
��m����C
	>UX���g�����X���(Z����x���P�@��ƥ	��["�(�.����~�x�֣ (f�S[|kGޓ��.���������o����[K���;���pho���m��F���R�>Hdrђ(|�@H�Ez�7�!�huo��H5��T
/Ж�*�V�d�� x��>f���/�C���5f)�s��}��ú�[or�f��E����*������(�&YB?�&�>"�X1q�5rb�����'�*��#5.��IwI�
1�w�4���#�.nۀ&!�+�v�>�u������!������Z4_��bP��h�\�Xtu�a����h�@�[PQV�[�Zm�.�> ����о�^YX:&�	��)��V�R�D����6n5�,�&*Rj��-��(Z-dk�ۻ�rh�skc����'���nl�]�࣠[ ة�V?���<U<zw, �­�m:�#a3��J���3m�-<
�˦�$ <�S��;6�{�[{ CF���u��!S~��~[�R.8�dăGh��P�Z�����K���X�Zá}��K�vu"-,-G��w"�$u��X��
��A"�[�c%>�V��mZJ$_$R��`� �Y���Fd	Q�!���-�xDAp .���{���4mrM�?n�m�&�a���ޥ��F���q�.��Zkhz�.�uၭ��L�8���r �.�P��خJ�����G��[:[�{0G� ��B� s `��Kр��6J,�U.�{�+��z�a�k�����V���K�'�����s`E8����aB�u�^�+tc��9�7�~r�"��� �.�6T��v�NiU`�V�aPT��Y������� y�@���wk�{����_��(��f`���r)��"f�hXMVf���}ǺX��m� f�f9��6fI�f��s{,E����`�d$���D���`�4�u�-VW�|��AH�����sF��f���� ��s_�\�3F����f��_^�?[�O��� Y�n�} ��x1����{	��]��tifR����PAMS���J��ԇfZrUf=ۍ��uMf��uG��:u�V�3�m/�$

����\
uX�k��G6w�f�����z��f����U���񂸘�br;u׵�%��Ө�v-ZW�����9��/l�{<�8��f]=�V��u���.�ۘd<0v2�[p7�f����v[0�,��n�Kc�C/r'[^3�J�~E�Nx�KA��f��������"�������ߔ�OX ��7؋D2$ ZM$ek R攭��b��:�1�z7pBVX:��[�&.8�_>�x]l��v����L�U����u�c��^�7�{�
?ߪ�n�0 l;��x[���h~�PR�j@[ �.����[���t�.���R+}�[���R��BOlo�uB�l��������1���.�Z�Q��-�ՇT�[�-EBoM�/�U})��f!�fol[����	^řy]޾��Z�t�Pr�!�f11�c�����n� Ѡ.۶lm�!Q4��i�mkY"�$C�p�9��l�;�*>�5� @���ݻ�fwOW�v�B��]��5�e�.l�}�	��5ضō@)�}�����*�6S4��<��!��|
3Fõ�m�E.����7kW�*��ӻ��[���_�W'��}�0#EgE���������ܺ�vT2��Ҩ)U�1�nE_��RL�ڎ[y�?�Fmjt��L��*Pv�)���߾r��z)�P�6��u�c���.)����~�2Kƅ�Gl��8v����E,��7=%��8�d����		��3��]{����]�P��������%�eVSR��S��x��Xx�C9�w5P����HXr*I$7JKl�[�P��WQ�KPyEB�mo�w  �oSPOč����d�r|F�`r�XZ9�sd��n�?�^(���z�t+�tZ[g9�ډ�[[,�J[;_ls��ك,��)�u�����+�� U�Mt�o�7�fB3��@MY����[�Y^v`��]������W�&�
q��GG!8S�"9.č���X#m��w�f�ty63ق�=���d��h��v��IG�"u�#Gt��I���h�n�F��*v�;�E��/#*�U�)/u���
�9���ށ�V�ʀ�V���7CC9����t��W��7�A�r����[6]�#}���s/��k�P�V~YU������Չ�� ��	Cf�M��҅@7X�/r���¡O
Error: Duplicat��mVolu� IDҵV�Q������2Yr!8�s�ʹ�����Kq�����r&~�-4���_VA�?ሿӀ�.b�
.����'	8�u�Vp�[X^��[�'��d�7.�d.�J�������������B*N�~�Y�7�Q;&�>L 	�u;�Ǫ/�K�s3`r.x�Z�^m�02!"[���I'=,��mkFzP v@�ݕ(R���V�{f�A���D��=iLo�a��� J~����� �����8�.�v�H^�l��j��o4L�R.3�̟Z���𫑫C:R�o�
<2�W�H��ڻ�M!_"���FD�76�`^`j!>V�>z{kg�X=>X���VɄ嫓��+�8��}���r{����wlV��-��u_<r[o�ʭ��4�Z�!C,6 hۻ-������Oj4w[ M5!����'��VE�=SAu�OI>��#��R��+@�PQ�R�R/t.SWZ��yQ����yY����o������zy"���ŘY�M��P&x�M����LY�����y��U�vTR:w�y�B��[�otJWȾ@�_���־�����i,DÕ��B�`d�>W�Z�NT51��j,0r
r',4��ά�r^�o�
�5�<,�6����ɻ�=��t������뮷��.�d��>rl�����&;g<�~{�Z�û�>��X�C����^�1��R,�6�'C�(���t\��8�t�C�K�w����XN���^��f�7�����yQ�%f�G����ASK]���6�EXTENDED
NN�5��ORMAL�Q�>)��ol�� kt�T��gt
m.Nf�[4GK��c F5*��($Ou�����V���r6(@uuF��:��T+aw|д�t
v]kUz]5����-��[���)��R_��j�	�<z<a���9wH0rCuFII�<Xtx��v�z�F��'8�Q��T��sR6�Z4�5��
�	��7�	Z�r�F���(l*EW'�=V�h�R�4������Ċ����.rt%y�u����w�^�6V������^�_+[�-��O�6����b��*��:#oading�棧dchecksucces�@��sful�bypa
_	��s 0x No "h image. /�~�[Tab]hows C�st.���o-O - T FVmp m};k[+t2Dcrip{o1S9qLm e\�
�>Key4bl�5j�Fvd/!rnelhkD���Initr�?��myJonftDSign���mquB n�foun»�X�1/� [qu|s�i�n7�c va��vAe$Ma�fiw��j�Y;�}c�d��d=%Iv�h�WRI� �OCT?��`��Xb��Za�;k�@�.�ڶ�^ovl< �}�;��dg{WARNI���NG:|���Zk٧=��nv	��mk,�n�D�y��
��g�G�-v+/l�?�y/n�*I�k���u*�U���'�xpk)EOFPշ�:�w�dS>.#�`h[Vdi#
���`>�m�ې���r8d^{�hOl@bkA�l�tvChla�^+4�I�7�V�w��ސms9���a�buff.@:�:l6B� S���mtiyrzdGo�l鏇� 4Mᐄb���m>�c�poiu�23.2R%� :߆S!�au��:��BO%_I� r% �vԝ $ G �"`r%G2�烜�G�"�"���" 达TN!c���#Ѝ�@�"3�2�U���9�s�ɏ�� ,��+M��+,ry�$�� WI��j ��O,Z+�J�,��ê�vFX�+٪��(++��+���<(�	�TN�9���H��"�+���%$
�wU�=�"������"�d�"Yu����"�/z
�ja[�@��m��P(F�A���i0�Uv��B�m����6��crdH��"������5�#6���<#����󰟪oK5*)�GY�e�!��ka{G�eyYw�VR���U>��%t��P�X���&#u��q,]o��#pS��"�hm!�yH�[+����#A��ͪ&�%�"�<�&##���Q���\�H^�"���nխ�tU&`Q���_�9�x��=��-khq[[�֫���:�p{)�ti6x�H��9�������[�d��mSuP~Ս1�A%'[e�u��A��� ,#d��#�"~�j��$!Z���Ad�����Ae��!��-�DB���A��X�0BhAh��[��
�LAUߎ�2��$��|�A#�����N�"i��Y��A(A���(`(��U�4A#�d(m���"��"�C6�"�"%� ���� �ꀌ��*�2�}!�b麰�PX��AG.#��"R�"�",�j�SޕA�"}9Ȁ&�"����,VD�4����2����"G �y�|���-��+�r�����|�n#� D+��x0��EV=�"4CW �"�"T�/��"���V=��2T�"�uN����C&.�nE��<�E�I_ .��V�t�U�RFY��Z���]j��ۍ6(~'���'Q:6s
��+������E���zE݋z��#*�Z9$���"�"V��!�%-�j{�W�T���
d��*�"^�9�"�"�"�	i��"�"��ȯr<��"�"L����"�"�"*UC ��aɑ����>��_u�2���0� �!M�%C�E8�V�*%��� ����"�" 9Q �"�9���"�"�"!��e�"�"�"�"�����"�"�"|�*�i"����"�����"���z��(�����"�"��gլ���"�r@�\�"�"��`���?{���<�C�"L�CF^H*2�"�22�d�222dBN&222���22@��222��+222�9222�i2222#�J2$2ȶ"+2�F22��R��\XU��+$�@r2++��*w+~��9��2&��*2�" �Ar�222%W¹2 ���A C��sɲL�������҉���C���x�)Ó�۵<�����.���ɉ~�x��Q�	fhvÍ����0�Y���5r6
R$.X����0�����ۛ~vW'QSPXP��(�	���v
[Y=R��^t����2����ZIQ��y}���� �.?�tOPV����%$�����*Cx��Q��斴�;.�$�Fl��e����YQ��ۃ,�t·�^j`m�ط�L��cP^*��Ĉ�QL��-� ���::�d:D�-�S����ctA��#�"�����u������ ����Ŀ������ͻ�������Ⱥ�ķ���Ӻ�͸���Գ�ͳ�Ŵ��׶��ص������ι������������������GqGNp��`�P�R�"&���(�u�ҰcE)\t��6��]/|����+V��%���'�s�6H@L����r9�r��F�����LeN�\����(���S�7����<1�ÈRZ��������<���P	 �ư��1���kE�����v��ERo�.|VR���
ZZm�]���	�V6�h�y&m������^�Q�.To�uR�R���H���6�-��������n	������V��l���HY(�u�~W�Dq�J����k�N��QRPO�_9�Fwۥ�����]�M�q�Q��DW�U�7Q�F�
@u�L�	}��ܰW�	t��t�P`�B�t����ZX�O��J�āp����o���.v�끡F�#�B;aw�H�Z���n��Y�ƋX��}�j(�������]y^k�6�;hS��ӭ
�����[��[��S�F_�	v�]x�1ҡ�9�rd�Jt9�)�(.D\��ں{�Z]��Pt���Ht�6��Z+Ot�GtŠ�Bk�~��M�BvA���r��!Iu�ވ��
Q� ��-�BKuk�SMÿ@p���:�`�ꋰ�ݏ����`e0�{����
������}�.Ze�--�����";�F��tQ��#�&��6Q��ڽ���
 mض��*�
1���
�R�������� �:�e�"ے{P�Z�4n0:*�%~{ �@�<��h<���wOS��F�]c��M, �W�AA�'�n�_R�)��� �������m�Z���X÷j�P?MEN3��W�ֈ�NL	�G��;�ߩ���n��=% s.j�QT�>$nX��_�GJ/L� � ,x -��G�Z�	�Me���`%8: Hit, Kiy0y��fc7tJ��^�outM-v�'Us�����#w%s&ma`h	�l�[��ion E�o��/U & ops, h\)��CR0� ��'�!�	��A~"����n�ۑ�J�"��x�L��}����"�"� ����!�!�!H,#�\r�� �+��5�p�,
S�2�>��o������I�;� H
�+�DA�<�ɤ`&-2�L&8��d{
ʀ����@��`&���$��\ɑx�� ��*%*%% �c��?��$ (�tr�/�SA%%6%��#��m&�����
�.��-�9+X�-._.�c!"9"�"���*i>�
.�
��H.��� ��-*r��--��-�A*���L7.Gr���?�$��%�Y�n��%���$�t+)�f*���,5Q��vy�*��$f�oP��%��!��F%g�� �`E%���o$����Àx��
�A
�@9�%G�,��׹.'�ȭ���E't����oG%u��.kpaȑb3�=�Z�SӠ#����D��;%�Rp{�J'�$�F%�Ur@F%���F@�ӏ�<�$/>��%�G%��!)x[�����Ӽ|���$��F%����)p�����[�V��by.���J'F%.��d��.F%� y!F%%���6�U���.��BW�
�&۹k�K�$�l:�y ?��#����h!G�Ss�=)�s�
��䐂�4�K��̛/��E%�!y!�� �$�0d�tqe���&*�*��g9$*�6�L ��F%*�"y�%t�9 %%Cr���$H'wr!� #��B��t,�!�.��m��䐂Ca���G.#��$O�$�$r`�Sޒ&�$���$(�$!�2 t6t��\r4P�/y%z"���'��!�;�!�--�a��IΦ�w��&-��?���\�$��6@ȋ�$�$_$#��$u�!�$�e�db�$�))v<�����4+u
`,��6���$M$�䁡 %%��72�,-��n���u!�2I�Ѩ,�y %%�$�4��$k�$���$�<��$�|��$�$�$�$$�	,R9��`�00����"�y<��w#�hrrɐ^00��,X"�?� ���$�$� 9Q%%e�9�&%%%�!��"%%%%䨒�%%t�|�*�$��	%Z��%��h����*�% ��%p!��[>�$%r�ȓ%%�R`�{���9 %� 9d��#4�)��44�I&9444@&�d444�(�44dH�444#��444�9�444d9�f4444<B�4�$Cr!�-44\�?!Z���O-�@r�4--�w$-~� y��^4�J�(4�$r�$^4L��4h^()��@.��@�
d��e��������璄�x�h$�`_DMѥ٥���-�d}����m����[��De=�rw���_�����K�#�A�)�8���.�������9�����/����4-�H��:P-��n�w�6-*v���R�ߠU��k@�����IV����M~�G�ݚ�-����.������ry� ��޶���Ȗ��4-���7�`@[h��9G�N���V/�a=�M-�x^��~�Z]�����;a"J�L,�&cW���6e_6�,�ٽg3����6:hF-j�ro�mLV6N-�.��i-0Y�:�x��ڷ��h@-�
:-����J��L�L��AA��Q�k����\��_�!ո��2-�0�69���o��8-),����PQ�&�l[s
v 4�W����P���%�7��[��X(���F'.ŭ��6�)ѯ��wst~���jp�����XI$���m9^د+��ǈ��-l�)���$�ϡF�6@P([��m|�u��ϑ,&����A�ƀ��-
,��o���u���f��a�F�x��\zY���.�4�����@`��o�!�[N���������D�������Kk�P��׉F��F�V+���^&���o�-��P��#P�g8'XtP���~�İ�& %X�
GEk�Z�8tnD�4#�eX�l�mg�B	
��n@�P�u��;(l�ɭ������N�^�V�v��v��߂�2�v�����c��艴Tsml�?����'�P&��龬���������ت���l��W�u�[��_k�~{�o�9~���K|+���P���G��?_kE���F��u�f ��vY2w99�0��l���RAZ� ��lm����
�.���E���mW���Q�z�^�F�&�?B�&����-�(tt_�mi��P�/�t��Bǣ��]�V��Kl/<&�?.2}G&�b���g
����㻿�Y�uM�uEC�Ķ@:G��01i&��v��	�� �ws�͒���7�P(�VBE2.�%"���=O����wf�=VEnYOj_��)\���mqٖ
�u���Q	 �@�������f� f�A	���aߪo�% ��}t���@�1$<.�\�w�O[t1���.��'� �<]�v�tK�nm�,1�8���.�,$�6�^��f�7b��S���~w��U(�?���L7��و��Z[�ot��~�=�F`^��o��P�l
W���n���	��Kvʡ��R�o(,t{�v����������&#O�˾k	�>���[�#Hx������?a�39� w���M1�
8.�QR��z�	�Ǌm#>`���ƭ��t��Sw�pC��P[��Z�
��\`#�(�q���υ��C��D\Nr��[h��K�k���:�����τ�%W�K7��)��
V�ڻ����~����B��-g��?���S�x��;"9w��t��עU&�2���H.
D�
��L���\0��~���7�nuU���V��������u�.��uF��*��q��V���� ��i��t����s8�
�㖈Ș��m�v2&*�@q���Nu���n���^Ţ�O6$��ꐃ�P$��2 #9��%1��#�1�6?�%%�"�l� ������.F%@ȑ����.�x����6.&d�M7+ n� 6����H��6@6�E7(XD�/�.*�1�&� |^����	��D�� ���͵��."|���SVR�αQ�"�"zuۥ�V�\��/fPf%������ 
Q����ѿ�VA}"B�󒾾^�(8C���x3������p m��i� a�����ve
$y�e����PT2��kD6�o�X= �>�}K�KܩX<���^[��Ħ�m*Xs sv��injN`��Et#��7�	�B�?R�"!PtC��Q���|g�h��"����\>���lM�*�?����DG���f� �*`绯B2@��9�-e��	?�p���f��f�>�m (x��n}x!����\���*2�t8.� 
���8�DKt<S�`�|���Hޓ���?J�Y�g�q� #�����+�僰=����&#��хw�h>X �Z �>T]��^�;�u�<�u!�&�
����$�ĉD8�u��[���/m�������r�$|�~�uO&�<�rI<����wE	�?)5(u\x��5�� xa#��՝m�w� �vǷP$�6=TfMw�/޾ ��b�����:�
:P�Q XP�
�x 8��v�(�Z���� �|�2�K��������Ԡ�(��7XīF���þ�&8]��KD�����{��V�0��,5�A�/H�M�L���V2�R�8�u����I��}i�=�,���΁����Z�����^PSn���6�?�t�u7P�G�@@dX�g�u(6y.f����͠L.��w�&f��V��ֲ��D��h!e�.���M�$W�GG&��%uJ��� e<��B�TUC_�׽���@t�H��a�W�Mf6�O��ms���Q�-���-��kl�B9``a4�0F�� ����
$��	�� �0U܀è��msn��b,A�Rъ�?�q��B^UB%Z#l<�.��������u��^�F�F*n ��2����F���3fb��
,��]" �
�se�FvjS���d������a)+;��UTC-��$?  ����0��G��6���9 �W`��i��s$���V@vd�DG����_�gdGe�߈c�^��[ �c�a�{KЂ��[�c��[�@��9�㼥ͤtgQ����>��PN�aP�qk�,�j��j�7�B�H�T�����7�������q�YI��σ�7	q��R�>)��O�q������N�9�N�����L(���K���@��K���TG���CAk[S�ž󿥀��Z �      @��        @�"�        �  @     ����GCC: (Gentoo 4.5 p1.2,����ie-0)  .shstrtab	o�y�inittexfrod��aeh_frame	cQrs�s�ldjcr")es���l-got.pl=��=bs*comm�  曦�'Ԁ�@�d��f��O4���$H$� i��'@@ �\�e� %M�{9��jkw/�\6�'d�do�� 6ll��=tt3 HBx3 CHxO|H3$M|xTH���]pۺ% �p'l�� ݕ?c'�����l��dhO06$|�'*�s@h�'�q�    H  �    UPX!        g �g  �ZXY�`�T$ ��   `�t$$�|$,����������F�G�u����ۊr�   �u�������s�u	�����s�1Ƀ�r���F���tv���u�������u������u A�u�������s�u	�����s���� ������/����v�B�GIu��^�����������w���H����T$$T$(9�tH+|$,�T$0�:�D$aÉ��1���<�r
<�w��t,�<w"8u�f������)�����������؃��a�QPR�
 $Info: This file is packed with the UPX executable packer http://upx.sf.net $
 $Id: UPX 3.07 Copyright (C) 1996-2010 the UPX Team. All Rights Reserved. $
 jZ�   PROT_EXEC|PROT_WRITE failed.
Yj[jX̀�jX̀^�E��8)���@H�  % ���jP1�j�j2�jQP��jZX̀;���������P��PQR�P��D$V�Ճ�,�]����=  \  I ۷��WS)ɺx  ���)��	 �Y�ww����)��$ą�u��"��� ��o =�3� �N�/proc/sm���elf/exe [jUX̀��x�^@�o�� 
S�SH���
�� ���R)�f�����{u�P���G��H���T$`G�d���o��$Y[��@Z���PO6<��?��u�PP)ٰ[�'��w�ogu����	W�� s�����[u����@�H����_�S�\$jZ۷��[� WV��S��9��s
j�k��7����t�G�B��s)3�9��{U��/�Ӄ�E3}{����E܃: ��GU�������m� �M���UPX!u�>)��M��_um9�w�;�oo�w�s_E���u�P�wQ�}w��v�Ub�GϋU�;cuǊE�������t"��t�� �w9u��P�۶�E�PR9��4��F��<���
��U���v)�R��A�e��������t�u	9t����1���[�mg�S�D������o���]U����[������M��x�J,�]���������w�����1�W"Jx�;f����9�s��S9��� ���>�*)���8:�[��Gj j�PSV�8����ډ�y-)��E�  y��y, ����i�L}����� t ��qu-̺&����K�����%����8��HL�@bQs��������Z�m�O�B���Ճe�|�֡�ǍK�o�4[�x�)׋A�J��^p|yP?���P=�m/`����2���V���FPW�_���v��9ǌ� ��+/�76��u�7��j��u��n*XZ����!�%/a�y�t9�7t���@����gcCx�uV�@tEP�XQ:���M�;Pu����%:��[���k�4�z��Lu��7.@=�a�t���ۆ@1����Ƈ����4[���j}t�����o��;s�j2���o��)�S�o��Z�e쭱ʩb���7
�j[F���QA,�=v��� 9
�#/��ˈT�	�j-.�5\����aZ�<�I�����6���}��u�ll�W4zC ?�n�p�bE eV����n������O, 7�:���]$��*�]����*]�h(��mso�4�R����P_���^���	4����lU��wf�d�p_fi~O���v,3jL1��I^oE��jj�x�@xݷÉ�j=�s���ur�(ox�{��j�/M�p���{��j2B��i`�����|�5�      � �  UPX!*N  @  �� I 2�                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   