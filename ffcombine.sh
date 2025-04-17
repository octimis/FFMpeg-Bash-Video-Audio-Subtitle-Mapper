#!/bin/bash
# Execute script in subfolder containing 
#   only media files you wish to combine.
# /full/path/to/this_script.sh
# No arguments are passed.

# Only output final command; placed after options (getopts)
[[ "$@" =~ "dryrun" ]] && dryRun=true || dryRun=false

vidCodec=""
audCodec=""
subtitleFile=""
subtitleFormat=""
defaultExt=""
vidFile=""
audFile=()                      #if >1 aud files
# Amound of non-video streams in video file:
declare -A streamCount=(["audio"]=0 ["subtitle"]=0)	# mapping
vidFileInput=()			# '-i vid.mp4'
vidAudFileMap=( '-map' '0' )	# copy all streams from 1st input file
subtitleArr1=()                 # input syntax: '-i file.srt'
declare -A subtitleArrSUB_IDX   # VobSub files	
subtitleArr2=()	                # map syntax	''
subtitleArr3=()                 # metadata lang map
declare -A subLangArr		# traverse subtitle file
outputCodec=( '-c' 'copy' )
outputFilename=$(echo $PWD | sed 's:.*/::')  #Folder name
oldIFS=$IFS

buildFFMpeg () {
   # [ffmpeg] [-i input files] [mapping of input files]
   # [optional subtitle metadata] [output name]
   vidFileInput+=( '-i' "$vidFile" )
   
   case $defaultExt in  
      'mp4')
         [[ $audCodec == 'opus' ]] \
            && outputCodec+=( '-c:a' 'aac' )         
         ;;
      'webm')
         [[ $audCodec != 'opus' ]] \
            && outputCodec+=( '-c:a' 'opus' )
         ;;
      *) ;;
   esac

   if [[ -n $audFile ]]; then	        # External audio is provided
      for i in ${!audFile[@]}; do	# ['-i' "#1"  '-i' "#2"]
         if (( $i % 2 )); then	        #  '-map 1:a' '-map 2:a'
            mapLabel_prefix=$(( $(( ($i+1)/2 )) ))
            vidAudFileMap+=( '-map' $mapLabel_prefix':a' )
         fi
      done      
   fi
   # Call function, build map syntax for subtitle files
   [[ -n $subtitleArr1 ]] && populateSubArrays
   # If pair of VobSUB [.idx+.sub files]
   #    add to middle of subArr1 [input -i array]
   [[ -n "${subtitleArrSUB_IDX[*]}" ]] && alignSubIDXparam
   #Output will be an mkv file
   if [[ -n $subtitleArr2 ]] || [[ "${#audFile[@]}" > 2 ]] || \
      ([[ "${streamCount["audio"]}" > 0 ]] && [[ "${#audFile[@]}" > 0 ]]); then
      defaultExt="mkv"
   fi
   outputFilename+="."$defaultExt
}

execFFMpeg () {
   IFS=$oldIFS
   ffmpegCMD=( 'ffmpeg' "${vidFileInput[@]}"
   	       "${audFile[@]}" "${subtitleArr1[@]}"
   	       "${vidAudFileMap[@]}" "${subtitleArr2[@]}"
   	       "${subtitleArr3[@]}" "${outputCodec[@]}"
   	       "../""$outputFilename" )
   echo "${ffmpegCMD[@]@Q}"
   [[ $dryRun = false ]] && eval "${ffmpegCMD[@]@Q}"
}

getSubLanguage () {
   pattern1="([0-9]{1,2})"
   pattern1+="(:[0-5][0-9]){2}((\.|,)[0-9]{1,3})"   
   # Look for 'Language: English' around beginning of file content
   while read -r line; do
      [[ "$line" =~ "$pattern1" ]] && break  # HH:MM:SS.0 triggers exit
      pattern2="^.*[Ll]anguage"
      if [[ "$line" =~ $pattern2 ]] ; then   # Language: found
         for i in "${line[@]}"; do
   	    IFS=' ' read -a iArray <<< "$i"  # 
   	    for j in "${iArray[@]}"; do
      	       if [[ $j == *$BASH_REMATCH* ]]; then
      	          continue
      	       else
      	          subLang+=$j
      	          [[ "${#subLang}" > 20 ]] && break
      	       fi
   	    done
	 done
	 break #exit while loop
      fi
   done < $1  
   echo $subLang
}

alignSubIDXparam () {
   tempArr=()
   lastIndexReached=0
   for i in "${!subtitleArrSUB_IDX[@]}"; do
      #['-i' 'sub1.vtt' '-i' 'sub2.idx' '-i' 'sub3.vtt']
      #        idx:1  ^^       idx:3           idx:5
      #               ^^
      #E.g.: Insert element after idx:1 (arbitrary)
      # Element of subtitleArrSUB_IDX[i]: '-f vobsub -sub_name "*file*.sub"'
      for j in "${!subtitleArr1[@]}"; do
         lastIndexReached=$j
         if (( $j % 2 )); then
            if [[ $(basename "${subtitleArr1[$j]%.*}") == \
                  $(basename "${i%.*}") ]]; then	 # if *x*.idx == *x*.sub
               #convert SUB_IDX from string to array first; drop quotes from *.sub
               IFS=$'\n' subSyntax=( $(xargs -n1 <<< \
                                    "${subtitleArrSUB_IDX[$i]}") )
               # delete '-i' added in 2nd else statement            
               unset tempArr[-1]               
               tempArr+=( "${subSyntax[@]}" )            # '-f vobsub -sub_name *.sub'
               tempArr+=( "${subtitleArr1[(( $j-1 ))]}"	 # '-i'
                          "${subtitleArr1[$j]}" )   	 # '*.idx'
               break					 # goto next i, not j
            else
               if [[ $(basename "${subtitleArr1[$j]##*.}") == 'idx' ]]; then
                  unset tempArr[-1]
               else
                  #check if non_idx sub file is already added
                  tempArr+=( "${subtitleArr1[$j]}" )
               fi
            fi
         else
            tempArr+=( "${subtitleArr1[$j]}" )
         fi
      done
   done
   
   subArrSize=${#subtitleArr1[@]}
   indexResume=$(( $lastIndexReached + 1  ))
   # Add the rest of the array to temporary
   if [[ $indexResume < $subArrSize ]]; then	## PRONE TO ERROR #############
      for ((i=$indexResume; i<$subArrSize; i++)); do  #########################
         tempArr+=( "${subtitleArr1[$i]}" )
      done
   fi  
   subtitleArr1=( "${tempArr[@]}" ) 
}

populateSubArrays () {
   mapAdjust=$(( ${#vidFileInput[@]}/2 + ${#audFile[@]}/2 ))  # video streams; audio if
   #-map 0 -map 1:0[or 0:1] -map 2:0 -map 3:0	  #0:1 video had own audio
   #    vid w/o ^^^ audio   ‾ ‾ ‾ ‾ ‾ ‾ ‾ ‾ ‾          
   #-metadata:s:s language=eng
   for i in "${!subtitleArr1[@]}"; do
      if (( $i % 2 )); then		# pass index: 1,3,5
         subtitleArr2+=( '-map' )	# Avoid adding whitespace
         subtitleArr2+=( "$(( $i/2 + $mapAdjust ))"":s" )
      fi
   done
   
   # Assoc Array is unordered, -metadata:s0 may be 
   # placed after metadata:s1 in final command
   if [[ -n "${subLangArr[*]}" ]]; then
      for i in "${!subLangArr[@]}"; do
         [[ "$i" ]]
         counter=0
         for j in "${!subtitleArr1[@]}"; do
            if (( $j % 2 )); then        
               if  [[ "$i" == "${subtitleArr1[$j]}" ]]; then
                  metaData1="-metadata:s:s:"
                  metaData1+=$(( ${streamCount["subtitle"]} + $counter ))
                  subtitleArr3+=( $metaData1 )	  #'-metadata:s:s:0
                  metaData2="language="
                  metaData2+="${subLangArr[$i]}"  # language=en'
                  subtitleArr3+=( $metaData2 )
               fi
               (( counter++ ))
            fi            
         done
      done
   fi
}

getFileType () {
   stream=$(\
          ffprobe \
          -v error \
          -show_entries stream=codec_type \
          -of csv=p=0 "$1" | head -1)
   case $stream in      
      'video')
         defaultExt=$(basename "${1##*.}")
         vidCodec=$(\
                    ffprobe \
                    -v error \
                    -show_entries stream=codec_name \
                    -of csv=p=0 "$1")
         vidFile="$1"
         # How many other non-video streams are in video file
         #    Required for adjusting subtitle/audio metadata
         while read -r count streamType; do
            case $streamType in
               'audio')
                  streamCount["audio"]="$count"
                  ;;
               'subtitle')
                  streamCount["subtitle"]="$count"
                  ;;
               *)
                  ;;
            esac
         done < <(\
                  ffprobe \
                  -v error \
                  -show_entries stream=codec_type \
                  -of default=nw=1:nk=1 "$1" | uniq -c)
         ;;
      'audio')
          audCodec=$(\
                     ffprobe \
                     -v error \
                     -show_entries stream=codec_name \
                     -of csv=p=0 "$1")
          audFile+=( '-i' "$1" )
          ;;
      'subtitle')
          subtitleFile="$1"
          subtitleFormat=$(\
                           ffprobe \
                           -v error \
                           -show_entries stream=codec_name \
                           -of csv=p=0 "$1")
         if [[ $(basename "${1##*.}") == 'sub' ]]; then
            # Assoc arrays can't store array, hence string
            subFile_Syntax="-f vobsub -sub_name \""$1"\""
            subtitleArrSUB_IDX["$1"]="$subFile_Syntax"
         else
            subtitleArr1+=( '-i' "$1" )
         fi
         #FFMpeg reads stream>tags>language
         #   and automatically appends info
         if [[ ! $(ffprobe \
                   -v error \
                   -show_entries \
                   stream_tags=language \
                   -of csv=p=0 "$1") ]]; then
            [[ $(basename "${1##*.}") == "vtt" ]] \
               && subLanguage=$(getSubLanguage "$1")
            if [[ -n "$subLanguage" ]]; then
               subLangArr["$1"]="$subLanguage"
            fi
         fi
         ;;
      *)
         echo 'Improper filetype. Ignored...'
         ;;
   esac
}
while read line; do   # Analyze all files in $PWD
   getFileType "$line"
done < <(find . -maxdepth 1 -type f ! -regex '.*\(txt\|sh\)' \
              ! -name '.*'  | sort) # Exclude hidden files
buildFFMpeg
execFFMpeg
