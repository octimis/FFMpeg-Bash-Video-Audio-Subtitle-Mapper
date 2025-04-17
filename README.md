# FFMpeg-Bash-Video-NonVideo-Mapper
FFMpeg video-multi-media mapper.
This combines one video file in a subdirectory with other non-video, 
   ffmpeg compatible media in that same directory.  
The output file name will take the name of the subfolder they are
   located in and will be placed in the the parent directory (../).  
If *.vtt subtitle file has a line 'Language: <x>', script will append
  metadata info.  
Add dryrun to only show command to be executed, but don't send it to ffmpeg.
