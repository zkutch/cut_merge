#!/usr/bin/perl
#
#Copyright (C) 2016 zkutch@yahoo.com

# This file is free software; you can redistribute it and/or
# modify it under the terms of the GNU Library General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.

# Utility is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Library General Public License for more details.

# You should have received a copy of the GNU Library General Public
# License along with the GNU C Library; see the file COPYING.LIB.  If
# not, write to the Free Software Foundation, Inc., 675 Mass Ave,
# Cambridge, MA 02139, USA.  

# This utillity cuts $amount_of_parts parts from $amount_of_parts video files and concatenates them in one result
# For working utility uses ffmpeg, mplayer2, melt, mencoder, exiftool, mkvmerge and MP4Box, which is part of gpac on Debian.

#TODO 1. work with command line options
#     2. log file

use warnings; 
use strict;
use Time::HiRes qw(time gettimeofday);
use POSIX qw/strftime/;
use Cwd;
use File::Basename;   
use POSIX;
# use List::Util;
use List::MoreUtils qw(uniq);
use Term::ANSIColor qw(:constants);

#VARIABLES
my $dir = getcwd;
my $verbose = 1;
my $first_file = '';
my $second_file = '';
my $result_file ;
my $start_time = ''; # format HOUR:MINUTES:SECONDS.MILLISECONDS
my $time_interval =""; # format HOUR:MINUTES:SECONDS.MILLISECONDS
my $out;
my $amount_of_parts;
my $merge_command = "empty";
#my $miliseconds_delimiter = '(\.|:|\,)';
my $time_regex = '^([0-5][0-9]):([0-5][0-9]):([0-5][0-9])((\.|:|\,)(([0-9])|([0-9][0-9])|([0-9][0-9][0-9])))?$';
my $natural_number_regex = '^[1-9][0-9]*$'; 
my $debug = 0;
my $duration;
my $temp_file = "cut_merge.txt";
my $fd;
my ($base_name, $parent_dir, @extension) ;
my @file_info;
my @ffmpeg_formats;
my @mkvmerge_formats;
my @MP4Box_formats;
my @melt_formats;
my @mencoder_formats = qw(mpg asf avi wav swf flv rm au nut mov mp4 dv mkv);
my @temp = ();
my %dpkg_status = ( 			# http://www.fifi.org/doc/libapt-pkg-doc/dpkg-tech.html/ch1.html   July 2016
				"Want" => {
								"unknown" => [u =>  'PKG_WANT_UNKNOWN'],
								"install" => [i =>  'The package is selected for installation'], 
								"remove" => [r =>  'Marked for removal (not in pkg-namevalue.c, but in man)'],
								"purge" => [p =>  'The package is selected to be purged (i.e. we want to remove everything from system directories, even configuration files)'],
								"hold" => [h =>  'A package marked to be on hold is not handled by dpkg, unless  forced  to  do  that  with option --force-hold'],
								"deinstall" => ['' =>  'The package is selected for deinstallation (i.e. we want to remove all files, except configuration files)'],
							},
				"Error_flag" => {
								"reinstreq" => [r => 'A package marked reinst-required is broken and requires reinstallation. These packages cannot be removed, unless forced with option --force-remove-reinstreq'],
								# "hold" => [h => 'Hold'],
								# x => 'Both: Hold-Reinst-required',
								"ok" => ['' => 'ok'],
							},
				"Status" => {
								"not-installed" => [n => 'The package is not installed on your system'], 
								"installed" => [i => 'The package is correctly unpacked and configured'],
								"config-files" => [c => 'Only the configuration files of the package exist on the system'],
								"unpacked" => [U => 'The package is unpacked, but not configured'],
								"half-configured" => ['' => 'PKG_STAT_HALFCONFIGURED'], 
								# "failed-cfg" => [F => 'Failed to remove configuration files'],
								"half-installed" => [H => 'The installation of the package has been started, but not completed for some reason'],
								"triggers-awaited" => [W => 'Triggers-awaiting - The package awaits trigger processing by another package'], 
								"triggers-pending" => [t => 'Triggers-pending - The package has been triggered'],
							},				
				);
#VARIABLES
	
	
print "\n" if($verbose);
write_to_output("Start working.") if($verbose);
if(package_status("ffmpeg")) 	#check status of ffmpeg
	{
		write_to_output("Found ffmpeg.");
	}
else
	{
		write_to_output("Not found ffmpeg. Exiting.");
		goto END;
	}

write_to_output("Enter amount of video parts you would like to cut and merge, please.");
$amount_of_parts = <STDIN>;
$amount_of_parts = clean($amount_of_parts);
if ( $amount_of_parts =~ /$natural_number_regex/ )
	{
		write_to_output("Firstly we should cut $amount_of_parts parts.") if($verbose);
	}
else
	{
		write_to_output("Entered $amount_of_parts is not natural number. Exiting.")  if($verbose);
		goto END;
	}
$result_file = $amount_of_parts + 1;
push @extension, 0;
eval
{	
	
	for (my $i = 1; $i <= $amount_of_parts; $i++)		# cycle through chosen files, cut chosen parts and fill extension array
		{
			cut_from_file("$i");									
		}
	if($amount_of_parts==1)			# finish program if only 1 video file is given
		{
			write_to_output("Nothing to merging.");
			goto END;
		}		
	for (my $i = 1; $i <= $amount_of_parts; $i++)		# check if in extensions array we have different ones, so merge need rendering
		{
			my $m = grep {$_ eq "$extension[$i]"} @extension; 			
			if ( $m != $#extension  )
				{
					write_to_output("Found mixed extensions in choosed files. Merge should use rendering and, possibly, take some time. ");
					@melt_formats = `melt -query "formats" 2>/dev/null `;
					chomp @melt_formats;
					shift @melt_formats for 1..2 ;	
					pop @melt_formats;
					foreach (0..$#melt_formats)
						{
								$melt_formats[$_] =~ s/\s*-\s*//g;				
						}
					print "melt_formats have ".($#melt_formats+1)." units.\n" if($debug);
					print "@melt_formats \n"  if($debug);
					if(package_status("melt") and  ((grep {".$_" eq "$extension[$#extension]"} @melt_formats) > 0 )) 	#check status of melt
						{
							write_to_output("Found melt.");
							melt_rendering();
						}
					else
						{
							write_to_output("Not found melt. Exiting.");
							goto END;
						}					
				}			
		}	


 # FORMATS
	if(package_status("gpac"))
		{
			# @MP4Box_formats = `MP4Box -h format | sed "1 d" | sed -n '/Supported/!p'| cut -d "." -s -f2,3,4,5,6,7| cut -d "(" -f1 |tr " " "\n"| sed 's/\.//'| sed 's/\,//'  `;
			@temp = `MP4Box -h format`;
			shift @temp; 
			chomp @temp;
			@temp = grep /\S/, @temp;
			@temp = grep !/(Supported)|(ISO-Media)/, @temp;
			foreach (0..$#temp)
				{
					$temp[$_] =~ s/\)//;
					my @member = $temp[$_ ] =~ m/(\.[^ ]*)/g  ;
					push @MP4Box_formats, @member;		
				}
			@MP4Box_formats = uniq @MP4Box_formats;	
			print "MP4Box formats have ".($#MP4Box_formats+1)." units.\n" if($debug);
			print "@MP4Box_formats\n"  if($debug);
		}	
	
	if (package_status("mkvtoolnix"))
		{
			# @mkvmerge_formats = `mkvmerge -l |  sed "1 d" | cut -d "[" -f2 | tr " " "\n" | tr "]" " "`;
			@temp = `mkvmerge -l`;
			shift @temp;	
			foreach (0..$#temp)
				{
					$temp[$_] =~ s/\]//;
					my ($mm) =  $temp[$_ ] =~ m/(\[.*)$/g  ;
					$mm =~ s/\[//;
					my @member = split(" ", $mm)  ;			
					push @mkvmerge_formats, @member;		
				}
			@mkvmerge_formats = uniq @mkvmerge_formats ;
			print "mkvmerge formats have ".($#mkvmerge_formats+1)." units.\n" if($debug);
			print "@mkvmerge_formats\n"  if($debug);	
			# foreach (0..$#mkvmerge_formats)
				# {print "member[$_] = $mkvmerge_formats[$_]\n";}
		}
	
		
	# @ffmpeg_formats = `ffmpeg -formats 2>/dev/null |  tr E,D " " | cut -d " " -s -f5`;	
	@temp = `ffmpeg -formats 2>/dev/null `;
	shift @temp for 1..4;	
	foreach (0..$#temp)
		{
			$temp[$_] =~ s/E|D//g;
			$temp[$_] =~ s/^\s*//;					
			my @member = split(" ", $temp[$_]);
			my $m = $member[0];
			@member = split(",", $m);
			push @ffmpeg_formats, @member;
		}
	@ffmpeg_formats = uniq @ffmpeg_formats;	
	print "ffmpeg formats have ".($#ffmpeg_formats+1)." units.\n" if($debug);
	print "@ffmpeg_formats\n"  if($debug);	
	
 # FORMATS
 
 
 #BRAIN
	my $m = grep {$_ eq "concat"} @ffmpeg_formats; 	
	
	# $out = `ffmpeg -formats 2>/dev/null  | grep "concat"`;
	if( $m > 0  and  ((grep {".$_" eq "$extension[$#extension]"} @ffmpeg_formats) > 0 ) )
		{
			write_to_output("Found ffmpeg format concat. Try to use for merging.")  if($verbose);			
			open($fd, ">", "$dir/$temp_file") or (write_to_output("Cannot write to $dir/$temp_file, error is: $!. Exiting.") and goto END);
				for (my $i = 1; $i <= $amount_of_parts; $i++)		# cycle through chosen files and prepare format file
					{						
						print $fd "file "."'"."$i$extension[$i]"."'\n";		
					}
			close $fd;			
			$merge_command = "ffmpeg -f concat -i $dir/$temp_file -c copy $dir/$result_file$extension[$#extension] 2>/dev/null";
		}
	elsif ( package_status("mencoder") and  ((grep {".$_" eq "$extension[$#extension]"} @mencoder_formats) > 0 ) )	# check for mencoder
				{					
					write_to_output("Found mencoder.")  if($verbose);					
					$merge_command = "mencoder -ovc copy -oac pcm -o $dir/$result_file$extension[$#extension] ";
					for (my $i = 1; $i <= $amount_of_parts; $i++)		# cycle through chosen files and prepare merge command
						{							
							$merge_command .= " $dir/$i$extension[$i]";				
						}
					$merge_command .= " 2>/dev/null";
				}
	elsif ( $#MP4Box_formats >-1  and  ((grep {"$_" eq "$extension[$#extension]"} @MP4Box_formats) > 0 ))	# check status for MP4Box
				{					
					write_to_output("Found gpac for MP4Box.")  if($verbose);
					$merge_command = "MP4Box -add ";
					for (my $i = 1; $i <= $amount_of_parts; $i++)		# cycle through chosen files and prepare merge command
						{							 
							$merge_command .= "$dir/$i$extension[$i] -cat ";				
						}
					$merge_command =~ s/ -cat $//;			
					$merge_command .= " $dir/$result_file".$extension[$#extension]." 2>/dev/null";	
				}
	elsif ( $#mkvmerge_formats > -1 and  ((grep {".$_" eq "$extension[$#extension]"} @mkvmerge_formats) > 0 ) )	# check for mkvmerge
			{
				write_to_output("Found mkvmerge.")  if($verbose);
				$merge_command = "mkvmerge -o $dir/$result_file".$extension[$#extension];
				for (my $i = 1; $i <= $amount_of_parts; $i++)		# cycle through chosen files and prepare merge command
					{							
						$merge_command .= " $dir/$i$extension[$i] + ";				
					}
				$merge_command =~ s/ \+ $//;	
				$merge_command .= " 2>/dev/null";
			}		
	
	else
		{
			write_to_output("No more methods for merging.")  if($verbose);
			goto END;
		}		
#BRAIN		
	unlink("$dir/$result_file$extension[$#extension]" ) if( -f "$dir/$result_file$extension[$#extension]" );
FINISH:
	write_to_output("$merge_command")  if($verbose);
	$out = `$merge_command`;
	unlink("$dir/$temp_file" ) if( -f "$dir/$temp_file" );		
	
	if( -f "$dir/$result_file$extension[$#extension]" )
		{
			write_to_output("Successfully concatenated to file $dir/$result_file$extension[$#extension].")  if($verbose);
		}
	else
		{
			write_to_output("Problem with file $dir/$result_file$extension[$#extension]. Output is $out. Exiting.")  if($verbose);
			goto END;
		}
};
 if($@)
	{
		write_to_output("Error for whole cut-merging process is: ".$@."Exiting.");
		goto END;
	}

END: write_to_output("Finish working")  if($verbose);
print "\n" if($verbose);


sub Duration
{
    my $file = shift;
    $duration = undef;	
    if(package_status("mplayer2"))	# check status for mplayer
        {
            write_to_output("Found mplayer.");
            $duration = `mplayer -identify -frames 0 -vo null -ao null -nosound "$file" 2>&1 | grep ID_LENGTH | cut -d "=" -f2 `; # get video full duration by mplayer
            $duration = clean($duration);
            write_to_output("Found file $file with total seconds length $duration");
            $duration = translate_seconds_to_time_format($duration);
        }
    elsif(package_status("libimage-exiftool-perl")) 	# check status for exiftool
        {
            write_to_output("Found exiftool.");
            $duration = `exiftool "$file" 2>/dev/null | grep Duration | cut -d ":" -f2,3,4`;
        }	
    $duration = `ffmpeg -i "$file" -vcodec copy -acodec copy -f null - 2>&1 | grep Duration | cut -d "," -f1` if( not defined $duration);		# get video full duration by ffmpeg					
    $duration = clean($duration);						
    write_to_output("File $file formated $duration");
    return $duration;

}

# ??? Seadare zedas
# sub Duration
# {
#     my $file = shift;
#     $duration = undef;	
#     if(package_status("mplayer2"))	# check status for mplayer
#         {
#             write_to_output("Found mplayer.");
#             $duration = `mplayer -identify -frames 0 -vo null -ao null -nosound "$file" 2>&1 | grep ID_LENGTH | cut -d "=" -f2 `; # get video full duration by mplayer
#             $duration = clean($duration);
#             write_to_output("Found file $file with total seconds length $duration");
#             $duration = translate_seconds_to_time_format($duration);
#         }
#     elsif(package_status("libimage-exiftool-perl")) 	# check status for exiftool
#         {
#             write_to_output("Found exiftool.");
#             $duration = `exiftool "$file" 2>/dev/null | grep Duration | cut -d ":" -f2,3,4`;
#         }	
#     $duration = `ffmpeg -i "$file" -vcodec copy -acodec copy -f null - 2>&1 | grep Duration | cut -d "," -f1` if( not defined $duration);		# get video full duration by ffmpeg					
#     $duration = clean($duration);						
#     write_to_output("File $file formated $duration");
#     return $duration;
# 
# }

sub third_colon_2_dot
{
	my $string = shift;
	my $n = 4;
	$string =~ s/(\:)/--$n == 1 ? ".":$1/ge;	
	return $string;
}

sub last_colon_2_dot
{
	my $string = shift;
	$string =~ s/(.+)\:/$1\./; 		# s/\:(?!.*\:)/\./g;
	return $string;
}
sub melt_rendering
{					# 	https://www.mltframework.org/docs/melt/
	unlink("$dir/$result_file$extension[$#extension]" ) if( -f "$dir/$result_file$extension[$#extension]" );
	$merge_command = "melt";
	for (my $i = 1; $i <= $amount_of_parts; $i++)		#  create merge command for melt
		{
			$merge_command .= " $dir/$i$extension[$i]";											
		}
	$merge_command .= "  -consumer avformat:$dir/$result_file$extension[$#extension] 2>/dev/null";
	goto FINISH;	
}

sub clean
{
	my $item = shift;
	chomp $item;
	$item =~ s/^\s+|\s+$//g; # Trim spaces
	$item =~ s/^'|^"|"$|'$//g; # Trim quotation
	# print "item is $item\n";
	return $item;
}

sub cut_from_file
{
	my $order_number = shift;
	write_to_output("Enter ".CYAN."$order_number video file path,".RESET." please.");
	$first_file = <STDIN>;
	$first_file = clean($first_file);	
	if( not (-f  "$first_file"))
		{
			write_to_output("There is no file $first_file. Exiting");
			goto END;
		}
	else
		{
			 if($debug) 	# getting duration can take a lot of time
				{
					Duration($first_file) if($verbose);					
				}			
		}
	write_to_output("Enter ".RED."starting time for $order_number".RESET." video file, please.");	
	$start_time = <STDIN>;
	$start_time = clean($start_time);		
	unless( $start_time =~ /$time_regex/ ) 
		{
			write_to_output("Starting time should be in HOUR:MINUTES:SECONDS.MILLISECONDS format. Exiting");
			goto END;
		}
	write_to_output("Enter ".MAGENTA."time interval for  $order_number".RESET." video file, please.");
	$time_interval = <STDIN>;	
	$time_interval = clean($time_interval);
	unless( $time_interval =~ /$time_regex/ ) 
		{
			write_to_output("Time interval should be in HOUR:MINUTES:SECONDS.MILLISECONDS format. Exiting");
			goto END;
		}
	($base_name, $parent_dir, $extension[$order_number]) = fileparse("$first_file", qr/\.[^.]*$/);
	unlink("$dir/$order_number$extension[$order_number]" ) if( -f "$dir/$order_number$extension[$order_number]" );
	$start_time = third_colon_2_dot($start_time);
	$time_interval = third_colon_2_dot($time_interval);
	$start_time =~ s/\,/\./g;
	$time_interval =~ s/\,/\./g;
	
	# https://www.ffmpeg.org/ffmpeg.html
	# Monday, February 17 2020
	#-ss position (input/output)
    #When used as an input option (before -i), seeks in this input file to position. Note that in most formats it is not possible to seek exactly, so ffmpeg will seek to the closest seek point before position. When transcoding and -accurate_seek is enabled (the default), this extra segment between the seek point and position will be decoded and discarded. When doing stream copy or when -noaccurate_seek is used, it will be preserved.
    #When used as an output option (before an output url), decodes but discards input until the timestamps reach position.
    
    #-t duration (input/output)
    #When used as an input option (before -i), limit the duration of data read from the input file.
    #When used as an output option (before an output url), stop writing the output after its duration reaches duration. 
    
    #1) -ss -i -t
	
	write_to_output("ffmpeg -ss ".$start_time." -i  ".$first_file."  -vcodec copy -acodec copy -t ".$time_interval." $dir/$order_number$extension[$order_number] 2>/dev/null");
	my $out = `ffmpeg -ss "$start_time" -i  "$first_file" -t "$time_interval" -vcodec copy -acodec copy $dir/$order_number$extension[$order_number] 2>/dev/null `;
	
# 	2) -t -i -ss     output 00:00:00.00
# 	
# 	write_to_output("ffmpeg -t ".$time_interval." -i  ".$first_file."  -vcodec copy -acodec copy -ss ".$start_time." $dir/$order_number$extension[$order_number] 2>/dev/null");
# 	my $out = `ffmpeg -t "$time_interval" -i "$first_file" -ss "$start_time" -vcodec copy -acodec copy  $dir/$order_number$extension[$order_number] 2>/dev/null `;
#     
#     3)  -ss -t -i
# 	
# 	write_to_output("ffmpeg -ss ".$start_time." -t ".$time_interval." -i  ".$first_file."  -vcodec copy -acodec copy $dir/$order_number$extension[$order_number] 2>/dev/null");
# 	my $out = `ffmpeg -ss "$start_time" -t "$time_interval" -i  "$first_file"  -vcodec copy -acodec copy $dir/$order_number$extension[$order_number] 2>/dev/null `;
# 	
# 	4) -t -ss -i same as 3)
    
# 	
# 	5) -i -ss -t 
# 	
# 	write_to_output("ffmpeg -i ".$first_file."  -vcodec copy -acodec copy -ss ".$start_time." -t ".$time_interval." $dir/$order_number$extension[$order_number] 2>/dev/null");
# 	my $out = `ffmpeg -i  "$first_file" -ss "$start_time" -t "$time_interval" -vcodec copy -acodec copy $dir/$order_number$extension[$order_number] 2>/dev/null `;	
# 	
# 	6) -i -t -ss same as 5)	
# 	
# 	
# 	
# 	7)  -noaccurate_seek -ss -i -t
# 	
# 	write_to_output("ffmpeg -noaccurate_seek -ss ".$start_time." -i  ".$first_file."  -vcodec copy -acodec copy -t ".$time_interval." $dir/$order_number$extension[$order_number] 2>/dev/null");
# 	my $out = `ffmpeg -noaccurate_seek -ss "$start_time" -i  "$first_file" -t "$time_interval" -vcodec copy -acodec copy $dir/$order_number$extension[$order_number] 2>/dev/null `;
# 	
# 	8)  -noaccurate_seek -ss -t -i
#     
# 	write_to_output("ffmpeg -noaccurate_seek -ss ".$start_time." -t ".$time_interval." -i  ".$first_file."  -vcodec copy -acodec copy $dir/$order_number$extension[$order_number] 2>/dev/null");
# 	my $out = `ffmpeg -noaccurate_seek -ss "$start_time" -t "$time_interval" -i  "$first_file"  -vcodec copy -acodec copy $dir/$order_number$extension[$order_number] 2>/dev/null `;
# 	
# 	9)  -noaccurate_seek  -i -ss -t
#   
#     write_to_output("ffmpeg -noaccurate_seek -i ".$first_file."  -vcodec copy -acodec copy -ss ".$start_time." -t ".$time_interval." $dir/$order_number$extension[$order_number] 2>/dev/null");
# 	my $out = `ffmpeg -noaccurate_seek -i  "$first_file" -ss "$start_time" -t "$time_interval" -vcodec copy -acodec copy $dir/$order_number$extension[$order_number] 2>/dev/null `;	   

	
	
	
	write_to_output("ffmpeg output is $out.")  if($out ne "" and $verbose);
	if( -f "$dir/$order_number$extension[$order_number]" )
		{
            if($verbose)
            {
                write_to_output("Successfully processed file $order_number.") ;
                Duration("$dir/$order_number$extension[$order_number]");
#                 $duration = `ffmpeg -i "$dir/$order_number$extension[$order_number]" -vcodec copy -acodec copy -f null - 2>&1 | grep Duration | cut -d "," -f1`;		# get duration by ffmpeg					
#                 $duration = clean($duration);						
#                 write_to_output("File "."$order_number$extension[$order_number]"." $duration");
            }
		}
	else
		{
            
            {
                write_to_output("Problem with file $order_number. Output for ffmpeg is $out. Exiting.") if($verbose);                
                goto END;
			}
		}
	return $extension[$order_number];
}

sub translate_seconds_to_time_format
{
	my $total = shift;
	return undef if($total !~ /^([1-9]|([1-9][0-9]*))(\.[0-9]*)?$/);
	my $sec = floor($total);	
	my $millisec;	
	( $millisec ) = $total =~ /(\.[0-9]*)$/ ;	
	$millisec =~ s/\.//;		
	my $hours = floor($sec/3600);	
	my $sec_minutes = $sec - $hours*3600;
	my $minutes = floor($sec_minutes/60);	
	my $seconds = $sec_minutes%60;	
	return undef if($hours>99 or $minutes >59 or $seconds> 59 or $millisec > 999);	
	return sprintf("%02d:%02d:%02d.%d", $hours, $minutes, $seconds, $millisec);
}
sub write_to_output
{
	my $message = shift;
	print my_time()."\t".$message."\n"  if($verbose);
}

sub my_time
{
	return strftime( q/%H:%M:%S./, localtime ) . ( gettimeofday )[1];
}

sub my_date
{
	return strftime "%d\.%m\.%Y", localtime;
}

sub package_status
{				# takes package name, return 1 if package installed and 0 in all other cases, if $debug = 1 return detailed report about package
	my $package = shift;
	my @sami; my $status; my @tri;
	my @out = `dpkg -s $package 2>&1`;
	foreach(@out)
		{
			if(/^Status\:(.*)/)
				{
					$status = $1;
					@tri = split " ", $status;
					if($#tri == 2)
						{
							for my $key (keys %{$dpkg_status{"Want"}})
								{
									if($key =~ /^$tri[0]$/i )
										{
											$sami[0] = ${$dpkg_status{"Want"}{$key}}[1];
											last;
										}
								}
							foreach my $key (keys %{$dpkg_status{"Status"}})
								{
									if($key =~ /^$tri[2]$/i)
										{
											$sami[2] = ${$dpkg_status{"Status"}{$key}}[1];
											last;
										}
								}
							foreach my $key (keys %{$dpkg_status{"Error_flag"}})
								{
									if($key =~ /^$tri[1]$/i)
										{
											$sami[1] = ${$dpkg_status{"Error_flag"}{$key}}[1];
											last;
										}
								}
							write_to_output("For package $package we have status: $status. \n\t\tPackage selection state is: $sami[0]. \n\t\tPackage error flag is: $sami[1]. \n\t\tPackage state is: $sami[2].") if($debug);	
						}
					else
						{
							write_to_output("Unknown output for dpkg -s $package: $status.");
							return 0;
						}
					last;
					}
		}
	return 1 if(defined $tri[2] and $tri[2] eq "installed");
	return 0;
}
